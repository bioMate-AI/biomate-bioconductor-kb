"""
Real-Time Cost Service (Redis-backed)

Maintains a live cost ledger per user in Redis so the frontend can poll
or stream the current spend without hitting Lago or a SQL database.

Key design:
  - Every cost event (LLM call, Batch job update, S3 write) writes to Redis.
  - Redis keys expire after 35 days (covers current + previous billing month).
  - A background thread refreshes running-job estimates every POLL_INTERVAL seconds.
  - The REST API reads from Redis → sub-millisecond response.

Redis Key Schema:
  cost:{user_id}:month:{YYYY-MM}:llm           HSET  input_usd, output_usd, calls
  cost:{user_id}:month:{YYYY-MM}:compute       HSET  vcpu_usd, gpu_usd, mem_usd, seconds
  cost:{user_id}:month:{YYYY-MM}:storage       HSET  s3_usd, puts, gets
  cost:{user_id}:month:{YYYY-MM}:transfer      HSET  out_gb, usd
  cost:{user_id}:month:{YYYY-MM}:total         STRING (float, recomputed on each write)
  cost:{user_id}:job:{job_id}:running          HSET  vcpus, gpu, mem_gb, started_ms, est_usd, instance
  quota:{user_id}:month:{YYYY-MM}:limit        STRING (float — set by plan tier)
  quota:{user_id}:month:{YYYY-MM}:alert_sent   STRING (1 if 80% alert already sent)
"""

import json
import logging
import os
import time
import threading
from datetime import datetime, timezone
from typing import Optional

import redis

from .cost_calculator import CostCalculator

log = logging.getLogger(__name__)

REDIS_URL      = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
TTL_SECONDS    = 35 * 24 * 3600   # 35 days
POLL_INTERVAL  = 10               # seconds between running-job estimate refreshes

calculator = CostCalculator()


def _month_key() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


class RealtimeCostService:
    """
    Write cost events into Redis and expose current-period totals.
    Thread-safe: uses Redis atomic INCRBYFLOAT / HINCRBYFLOAT.
    """

    def __init__(self, redis_url: str = REDIS_URL):
        self._r = redis.from_url(redis_url, decode_responses=True)
        self._running_jobs: dict[str, dict] = {}   # job_id → metadata
        self._lock = threading.Lock()
        self._pool_check_counter = 0  # Check pool health every N poll cycles
        self._poller = threading.Thread(target=self._poll_running_jobs, daemon=True)
        self._poller.start()

    # -----------------------------------------------------------------------
    # Write helpers (called by event handlers)
    # -----------------------------------------------------------------------

    def record_llm_cost(
        self,
        user_id: str,
        input_usd: float,
        output_usd: float,
        input_tokens: int,
        output_tokens: int,
    ) -> None:
        month = _month_key()
        key   = f"cost:{user_id}:month:{month}:llm"
        pipe  = self._r.pipeline()
        pipe.hincrbyfloat(key, "input_usd",    input_usd)
        pipe.hincrbyfloat(key, "output_usd",   output_usd)
        pipe.hincrby(key, "input_tokens",  int(input_tokens))
        pipe.hincrby(key, "output_tokens", int(output_tokens))
        pipe.hincrby(key, "calls", 1)
        pipe.expire(key, TTL_SECONDS)
        pipe.execute()
        self._update_total(user_id, month, input_usd + output_usd)

    def record_batch_job_cost(
        self,
        user_id: str,
        job_id: str,
        vcpu_usd: float,
        gpu_usd: float,
        mem_usd: float,
        duration_seconds: float,
    ) -> None:
        month = _month_key()
        key   = f"cost:{user_id}:month:{month}:compute"
        pipe  = self._r.pipeline()
        pipe.hincrbyfloat(key, "vcpu_usd",  vcpu_usd)
        pipe.hincrbyfloat(key, "gpu_usd",   gpu_usd)
        pipe.hincrbyfloat(key, "mem_usd",   mem_usd)
        pipe.hincrbyfloat(key, "seconds",   duration_seconds)
        pipe.hincrby(key, "jobs", 1)
        pipe.expire(key, TTL_SECONDS)
        # Delete running estimate atomically in the same pipeline flush
        pipe.delete(f"cost:{user_id}:job:{job_id}:running")
        pipe.execute()
        with self._lock:
            self._running_jobs.pop(job_id, None)
        self._update_total(user_id, month, vcpu_usd + gpu_usd + mem_usd)

    def record_s3_put(
        self,
        user_id: str,
        size_bytes: int,
        storage_usd: float,
        request_usd: float,
        object_key: str = "",
    ) -> None:
        month = _month_key()
        key   = f"cost:{user_id}:month:{month}:storage"
        pipe  = self._r.pipeline()
        pipe.hincrbyfloat(key, "storage_usd", storage_usd)
        pipe.hincrbyfloat(key, "request_usd", request_usd)
        pipe.hincrbyfloat(key, "bytes_stored", size_bytes)
        pipe.hincrby(key, "puts", 1)
        pipe.expire(key, TTL_SECONDS)
        # Per-object metadata for delete reversal (keyed by truncated sha256 of object path)
        if object_key:
            import hashlib
            key_hash = hashlib.sha256(object_key.encode()).hexdigest()[:20]
            obj_meta_key = f"s3:{user_id}:obj:{key_hash}"
            pipe.hset(obj_meta_key, mapping={
                "put_at":      int(time.time()),
                "size_bytes":  size_bytes,
                "storage_usd": str(storage_usd),
                "month":       month,
            })
            pipe.expire(obj_meta_key, TTL_SECONDS)
        pipe.execute()
        self._update_total(user_id, month, storage_usd + request_usd)

    def record_s3_delete(
        self,
        user_id: str,
        object_key: str,
    ) -> float:
        """
        Credit back the unused portion of pre-charged storage cost when an
        object is deleted before the 30-day retention period ends.

        Returns the refund amount in USD (≥ 0.0).
        """
        import hashlib
        key_hash    = hashlib.sha256(object_key.encode()).hexdigest()[:20]
        obj_meta_key = f"s3:{user_id}:obj:{key_hash}"
        meta = self._r.hgetall(obj_meta_key)
        if not meta:
            log.debug("record_s3_delete: no PUT metadata found for user=%s key=%s",
                      user_id, object_key)
            return 0.0

        put_at      = int(meta.get("put_at", 0))
        storage_usd = float(meta.get("storage_usd", 0.0))
        month       = meta.get("month", _month_key())

        if storage_usd <= 0.0 or put_at <= 0:
            return 0.0

        # Prorate: credit back (retention_days_remaining / 30) of storage cost.
        # emit_s3_put charged for 30 days upfront (30 * 24 gb_hours).
        RETENTION_DAYS = 30
        elapsed_days   = (time.time() - put_at) / 86400.0
        remaining_days = max(0.0, RETENTION_DAYS - elapsed_days)
        refund         = storage_usd * (remaining_days / RETENTION_DAYS)

        if refund > 0.0:
            cost_key = f"cost:{user_id}:month:{month}:storage"
            self._r.hincrbyfloat(cost_key, "storage_usd", -refund)
            self._r.incrbyfloat(f"cost:{user_id}:month:{month}:total", -refund)
            log.info(
                "S3 delete refund user=%s key=%s storage_usd=%.6f "
                "elapsed_days=%.1f refund=%.6f",
                user_id, object_key, storage_usd, elapsed_days, refund,
            )

        # Remove per-object metadata (object is gone)
        self._r.delete(obj_meta_key)
        return refund

    def record_s3_get(
        self,
        user_id: str,
        size_bytes: int,
        request_usd: float,
        transfer_usd: float,
    ) -> None:
        month = _month_key()
        key   = f"cost:{user_id}:month:{month}:storage"
        pipe  = self._r.pipeline()
        pipe.hincrbyfloat(key, "request_usd", request_usd)
        pipe.hincrbyfloat(key, "transfer_usd", transfer_usd)
        pipe.hincrby(key, "gets", 1)
        pipe.expire(key, TTL_SECONDS)
        pipe.execute()
        self._update_total(user_id, month, request_usd + transfer_usd)

    # -----------------------------------------------------------------------
    # Running job tracking (estimate while job is alive)
    # -----------------------------------------------------------------------

    def register_running_job(
        self,
        user_id: str,
        job_id: str,
        instance_type: str,
        vcpus: float,
        memory_mb: int,
        gpu_count: int,
        started_at_ms: int,
        is_spot: bool = False,
    ) -> None:
        meta = {
            "user_id":       user_id,
            "instance_type": instance_type,
            "vcpus":         vcpus,
            "memory_mb":     memory_mb,
            "gpu_count":     gpu_count,
            "started_at_ms": started_at_ms,
            "is_spot":       is_spot,
        }
        key = f"cost:{user_id}:job:{job_id}:running"
        self._r.setex(key, TTL_SECONDS, json.dumps(meta))
        with self._lock:
            self._running_jobs[job_id] = meta

    def _check_connection_pool_health(self) -> None:
        """
        Monitor Redis connection pool health and log warnings if utilization is high.
        Called periodically from the polling thread.
        """
        try:
            pool = self._r.connection_pool
            max_conn = pool.max_connections

            # Get current pool stats
            in_use = len(pool._in_use_connections) if hasattr(pool, '_in_use_connections') else 0

            if max_conn and in_use:
                utilization_pct = (in_use / max_conn) * 100

                # Log warning if utilization exceeds 80%
                if utilization_pct > 80:
                    log.warning(
                        "Redis connection pool utilization high: %.1f%% (%d/%d connections in use)",
                        utilization_pct,
                        in_use,
                        max_conn
                    )
                # Log info at 60% threshold for early awareness
                elif utilization_pct > 60:
                    log.info(
                        "Redis connection pool utilization elevated: %.1f%% (%d/%d connections)",
                        utilization_pct,
                        in_use,
                        max_conn
                    )
        except Exception as exc:
            log.debug("Connection pool health check failed: %s", exc)

    def _poll_running_jobs(self) -> None:
        """Background thread: refresh running-job cost estimates."""
        while True:
            try:
                # Check connection pool health every 6 cycles (60 seconds)
                self._pool_check_counter += 1
                if self._pool_check_counter >= 6:
                    self._check_connection_pool_health()
                    self._pool_check_counter = 0

                with self._lock:
                    jobs = dict(self._running_jobs)
                now_ms = int(time.time() * 1000)
                for job_id, meta in jobs.items():
                    est = calculator.estimate_running_job_cost(
                        instance_type=meta["instance_type"],
                        vcpus=meta["vcpus"],
                        memory_mb=meta["memory_mb"],
                        gpu_count=meta["gpu_count"],
                        started_at_ms=meta["started_at_ms"],
                        now_ms=now_ms,
                        is_spot=meta["is_spot"],
                    )
                    key = f"cost:{meta['user_id']}:job:{job_id}:running"
                    stored = self._r.get(key)
                    if stored:
                        data = json.loads(stored)
                        data["est_usd"] = round(est, 6)
                        data["elapsed_seconds"] = (now_ms - meta["started_at_ms"]) / 1000
                        self._r.setex(key, TTL_SECONDS, json.dumps(data))
            except Exception as exc:
                log.error("running job poll error: %s", exc)
            time.sleep(POLL_INTERVAL)

    # -----------------------------------------------------------------------
    # Total maintenance
    # -----------------------------------------------------------------------

    def _update_total(self, user_id: str, month: str, delta: float) -> None:
        key = f"cost:{user_id}:month:{month}:total"
        self._r.incrbyfloat(key, delta)
        self._r.expire(key, TTL_SECONDS)
        self._check_quota(user_id, month)

    def _check_quota(self, user_id: str, month: str) -> None:
        """Fire a soft-limit warning if the user crosses 80% of their plan quota."""
        total_key    = f"cost:{user_id}:month:{month}:total"
        limit_key    = f"quota:{user_id}:month:{month}:limit"
        alert_key    = f"quota:{user_id}:month:{month}:alert_sent"
        exceeded_key = f"quota:{user_id}:month:{month}:exceeded_sent"

        total = float(self._r.get(total_key) or 0)
        limit = self._r.get(limit_key)
        if not limit:
            return
        limit = float(limit)
        pct   = total / limit if limit > 0 else 0

        if pct >= 1.0 and not self._r.exists(exceeded_key):
            self._r.setex(exceeded_key, TTL_SECONDS, "1")
            log.warning("QUOTA_EXCEEDED user=%s month=%s total=%.4f limit=%.4f",
                        user_id, month, total, limit)
            self._notify_quota(user_id, pct * 100, total, limit)
        elif pct >= 0.8 and not self._r.exists(alert_key):
            self._r.setex(alert_key, TTL_SECONDS, "1")
            log.info("QUOTA_80PCT user=%s month=%s total=%.4f limit=%.4f",
                     user_id, month, total, limit)
            self._notify_quota(user_id, pct * 100, total, limit)

    def _notify_quota(self, user_id: str, pct: float, used_usd: float, quota_usd: float) -> None:
        """POST to the Node.js notification endpoint to send a quota warning email."""
        import urllib.request
        import urllib.error
        notify_url = os.environ.get("NOTIFY_URL", "http://localhost:5000")
        key        = os.environ.get("BILLING_INTERNAL_KEY", os.environ.get("BILLING_API_KEY", "change-me"))
        payload    = json.dumps({
            "user_id":   user_id,
            "pct":       round(pct, 1),
            "used_usd":  round(used_usd, 4),
            "quota_usd": round(quota_usd, 4),
        }).encode()
        req = urllib.request.Request(
            f"{notify_url}/internal/notify/quota",
            data=payload,
            headers={"Content-Type": "application/json", "X-Internal-Key": key},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                log.info("quota notify sent user=%s pct=%.1f status=%s", user_id, pct, resp.status)
        except urllib.error.URLError as exc:
            log.warning("quota notify failed user=%s: %s", user_id, exc)

    # -----------------------------------------------------------------------
    # Read API
    # -----------------------------------------------------------------------

    def get_current_costs(self, user_id: str, month: Optional[str] = None) -> dict:
        """
        Returns full cost breakdown for the given month (defaults to current).
        Sub-millisecond response — reads from Redis only.
        """
        month = month or _month_key()

        def hget(suffix: str) -> dict:
            key = f"cost:{user_id}:month:{month}:{suffix}"
            return {k: float(v) for k, v in (self._r.hgetall(key) or {}).items()}

        llm     = hget("llm")
        compute = hget("compute")
        storage = hget("storage")

        # Add running-job estimates
        running_total = 0.0
        running_jobs  = []
        pattern = f"cost:{user_id}:job:*:running"
        for key in self._r.scan_iter(pattern):
            data = self._r.get(key)
            if data:
                job_data = json.loads(data)
                est = job_data.get("est_usd", 0.0)
                running_total += est
                running_jobs.append({
                    "job_id":          key.split(":")[3],
                    "instance_type":   job_data.get("instance_type"),
                    "elapsed_seconds": job_data.get("elapsed_seconds", 0),
                    "estimated_usd":   est,
                })

        total_committed = float(self._r.get(f"cost:{user_id}:month:{month}:total") or 0)
        limit = self._r.get(f"quota:{user_id}:month:{month}:limit")

        return {
            "user_id":  user_id,
            "month":    month,
            "currency": "USD",
            "breakdown": {
                "llm": {
                    "total_usd":     round(llm.get("input_usd", 0) + llm.get("output_usd", 0), 6),
                    "input_usd":     round(llm.get("input_usd", 0), 6),
                    "output_usd":    round(llm.get("output_usd", 0), 6),
                    "input_tokens":  int(llm.get("input_tokens", 0)),
                    "output_tokens": int(llm.get("output_tokens", 0)),
                    "calls":         int(llm.get("calls", 0)),
                },
                "compute": {
                    "total_usd":     round(compute.get("vcpu_usd", 0) + compute.get("gpu_usd", 0) + compute.get("mem_usd", 0), 6),
                    "vcpu_usd":      round(compute.get("vcpu_usd", 0), 6),
                    "gpu_usd":       round(compute.get("gpu_usd", 0), 6),
                    "memory_usd":    round(compute.get("mem_usd", 0), 6),
                    "total_seconds": round(compute.get("seconds", 0), 1),
                    "jobs":          int(compute.get("jobs", 0)),
                },
                "storage": {
                    "total_usd":    round(storage.get("storage_usd", 0) + storage.get("request_usd", 0) + storage.get("transfer_usd", 0), 6),
                    "storage_usd":  round(storage.get("storage_usd", 0), 6),
                    "request_usd":  round(storage.get("request_usd", 0), 6),
                    "transfer_usd": round(storage.get("transfer_usd", 0), 6),
                    "puts":         int(storage.get("puts", 0)),
                    "gets":         int(storage.get("gets", 0)),
                },
            },
            "running_jobs":        running_jobs,
            "running_estimate_usd": round(running_total, 6),
            "committed_usd":       round(total_committed, 6),
            "total_usd":           round(total_committed + running_total, 6),
            "quota_usd":           float(limit) if limit else None,
            "quota_pct":           round((total_committed + running_total) / float(limit) * 100, 1) if limit else None,
        }

    def set_quota(self, user_id: str, quota_usd: float, month: Optional[str] = None) -> None:
        month = month or _month_key()
        key   = f"quota:{user_id}:month:{month}:limit"
        self._r.setex(key, TTL_SECONDS, str(quota_usd))

    def add_to_quota(self, user_id: str, amount_usd: float, month: Optional[str] = None) -> float:
        """
        Add credit to a user's monthly quota cap (called after a successful
        one-time credit top-up payment).  Returns the new limit.
        """
        if amount_usd <= 0:
            raise ValueError(f"amount_usd must be positive, got {amount_usd}")
        month = month or _month_key()
        key   = f"quota:{user_id}:month:{month}:limit"
        current = self._r.get(key)
        new_limit = (float(current) if current else 0.0) + amount_usd
        self._r.setex(key, TTL_SECONDS, str(new_limit))
        log.info("add_to_quota user=%s +$%.2f → limit=$%.2f", user_id, amount_usd, new_limit)
        return new_limit

    def is_over_hard_limit(self, user_id: str) -> bool:
        """Returns True if the user has exceeded their quota — block new jobs."""
        month = _month_key()
        total = float(self._r.get(f"cost:{user_id}:month:{month}:total") or 0)
        limit = self._r.get(f"quota:{user_id}:month:{month}:limit")
        if not limit:
            return False
        return total >= float(limit)


# ---------------------------------------------------------------------------
# Singleton
# ---------------------------------------------------------------------------
_service: Optional[RealtimeCostService] = None

def get_cost_service() -> RealtimeCostService:
    global _service
    if _service is None:
        _service = RealtimeCostService()
    return _service
