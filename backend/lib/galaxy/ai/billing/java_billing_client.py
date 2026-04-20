"""
Java Billing Service Client for BioMate

BioMate billing architecture (BioMate should ONLY talk to Java service, not Lago directly):

  BioMate → Java service (pricing/business logic) → Lago (metering) → Stripe (invoicing)

The Java service is the single source of truth for pricing. It wraps Lago so that price
changes, plan changes, and quota rules can be managed in one place without touching
Lago's admin UI directly.

Remote Lago (production) billable metric codes:
  "llm"   — LLM token usage (sum aggregation on "value" field)
  "ec2"   — Batch/EC2 compute (sum aggregation on "value" field = duration_seconds)
  "gp3"   — S3/EBS storage (sum aggregation on "value" field = duration_seconds)

All methods are fire-and-forget: they log on failure and never raise,
so billing issues never block user-facing requests.

Configuration (env vars):
  JAVA_BILLING_SERVICE_URL  — base URL of the Java service (e.g. http://35.86.137.71:8080)
  JAVA_BILLING_ENABLED      — set "true" to activate; default "false"
"""

import os
import time
import uuid
import logging
import threading
from datetime import date
from typing import Optional

import httpx

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

JAVA_BILLING_URL: str = os.environ.get("JAVA_BILLING_SERVICE_URL", "").rstrip("/")
JAVA_BILLING_ENABLED: bool = os.environ.get("JAVA_BILLING_ENABLED", "false").lower() == "true"

_TIMEOUT = 2.0          # seconds — short timeout for fire-and-forget billing
_RETRY_DELAYS = (1.0,)  # single retry; emit methods run in daemon threads so no blocking concern


# ---------------------------------------------------------------------------
# externalId convention — single place to change when Q1 is answered
# ---------------------------------------------------------------------------

def external_id(user_id: str) -> str:
    """Map a BioMate user_id to the externalCustomerId used in the Java service.

    Current convention: "bm_{user_id}" (prefix avoids collisions with other tenants).
    Change the return value here when Q1 (externalId format) is decided.
    """
    return f"bm_{user_id}"


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

class JavaBillingClient:
    """
    Thin httpx wrapper around the Java billing service REST API.
    Mirrors the LagoClient pattern: singleton, connection pooling, retry on
    transient network errors, fire-and-forget semantics.
    """

    def __init__(self, base_url: str = JAVA_BILLING_URL):
        self._base = base_url
        self._client = httpx.Client(
            base_url=self._base,
            headers={"Content-Type": "application/json"},
            timeout=_TIMEOUT,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _post(self, path: str, payload: dict) -> bool:
        """POST with retry. Returns True on success, False on any failure."""
        last_exc: Exception = RuntimeError("no attempts made")
        for attempt, delay in enumerate(_RETRY_DELAYS):
            try:
                r = self._client.post(path, json=payload)
                if r.status_code in (200, 201):
                    return True
                # 4xx errors are not retried — log and bail
                body = r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text[:200]
                log.warning("[java_billing] POST %s → %s %s", path, r.status_code, body)
                return False
            except (httpx.TimeoutException, httpx.ConnectError) as exc:
                last_exc = exc
                if attempt + 1 < len(_RETRY_DELAYS):
                    log.warning("[java_billing] POST %s attempt %d/%d: %s — retrying in %.1fs",
                                path, attempt + 1, len(_RETRY_DELAYS), exc, delay)
                    time.sleep(delay)
                else:
                    log.error("[java_billing] POST %s failed after %d attempts: %s",
                              path, len(_RETRY_DELAYS), exc)
            except Exception as exc:
                log.error("[java_billing] POST %s unexpected error: %s", path, exc)
                return False
        return False

    def _get(self, path: str, params: dict) -> Optional[dict]:
        """GET with single attempt. Returns parsed data dict or None on failure."""
        try:
            r = self._client.get(path, params=params)
            if r.status_code == 200:
                envelope = r.json()
                if envelope.get("code") == 0:
                    return envelope.get("data")
            log.warning("[java_billing] GET %s → %s", path, r.status_code)
            return None
        except Exception as exc:
            log.error("[java_billing] GET %s error: %s", path, exc)
            return None

    # ------------------------------------------------------------------
    # Customer registration
    # ------------------------------------------------------------------

    def register_customer(
        self,
        user_id: str,
        name: str,
        email: str,
        currency: str = "USD",
    ) -> bool:
        """Create or update a customer in the Java billing service.

        New customers are auto-subscribed to the default Lago plan.
        Idempotent — safe to call on every login or re-registration.
        """
        ok = self._post("/api/billing/customers", {
            "externalId": external_id(user_id),
            "name": name,
            "email": email,
            "currency": currency,
        })
        if ok:
            log.info("[java_billing] customer registered: user_id=%s ext_id=%s",
                     user_id, external_id(user_id))
        return ok

    # ------------------------------------------------------------------
    # Usage events — mirrors lago_client.py EventCode exactly so the
    # Java service can forward the same codes to the remote Lago.
    # ------------------------------------------------------------------

    def emit_llm(
        self,
        user_id: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        transaction_id: Optional[str] = None,
    ) -> bool:
        """Report an LLM call: sends two events (input + output) with separate codes.

        Runs in a daemon thread — never blocks the caller.

        Remote Lago metrics required:
          llm_input_tokens  — sum_agg on 'tokens' field
          llm_output_tokens — sum_agg on 'tokens' field
        """
        ts = time.time()
        uid = transaction_id or f"llm-{user_id}-{uuid.uuid4().hex[:12]}"

        def _run():
            ok_in = self._post("/api/billing/usage/events", {
                "externalCustomerId": external_id(user_id),
                "code": "llm_input_tokens",
                "transactionId": f"{uid}-in",
                "timestamp": ts,
                "properties": {"tokens": input_tokens, "model": model},
            })
            ok_out = self._post("/api/billing/usage/events", {
                "externalCustomerId": external_id(user_id),
                "code": "llm_output_tokens",
                "transactionId": f"{uid}-out",
                "timestamp": ts,
                "properties": {"tokens": output_tokens, "model": model},
            })
            if ok_in and ok_out:
                log.info("[java_billing] llm events sent: user=%s model=%s in=%d out=%d",
                         user_id, model, input_tokens, output_tokens)

        threading.Thread(target=_run, daemon=True, name="java-billing-llm").start()
        return True

    def emit_batch_job(
        self,
        user_id: str,
        job_id: str,
        instance_type: str,
        vcpus: float,
        memory_mb: int,
        gpu_count: int,
        duration_seconds: float,
    ) -> bool:
        """Report a completed AWS Batch job: sends vCPU-sec, mem-sec, GPU-sec events.

        Runs in a daemon thread — never blocks the caller.

        Remote Lago metrics required:
          batch_vcpu_seconds   — sum_agg on 'seconds' field
          batch_memory_gb_sec  — sum_agg on 'gb_seconds' field
          batch_gpu_seconds    — sum_agg on 'seconds' field (only sent for GPU jobs)
        """
        ts = time.time()
        memory_gb = memory_mb / 1024.0
        vcpu_seconds = round(vcpus * duration_seconds, 3)
        mem_gb_sec = round(memory_gb * duration_seconds, 3)

        def _run():
            ok_vcpu = self._post("/api/billing/usage/events", {
                "externalCustomerId": external_id(user_id),
                "code": "batch_vcpu_seconds",
                "transactionId": f"batch-vcpu-{job_id}",
                "timestamp": ts,
                "properties": {"seconds": vcpu_seconds, "instanceType": instance_type},
            })
            ok_mem = self._post("/api/billing/usage/events", {
                "externalCustomerId": external_id(user_id),
                "code": "batch_memory_gb_sec",
                "transactionId": f"batch-mem-{job_id}",
                "timestamp": ts,
                "properties": {"gb_seconds": mem_gb_sec, "instanceType": instance_type},
            })
            ok_gpu = True
            if gpu_count > 0:
                gpu_seconds = round(gpu_count * duration_seconds, 3)
                ok_gpu = self._post("/api/billing/usage/events", {
                    "externalCustomerId": external_id(user_id),
                    "code": "batch_gpu_seconds",
                    "transactionId": f"batch-gpu-{job_id}",
                    "timestamp": ts,
                    "properties": {"seconds": gpu_seconds, "instanceType": instance_type},
                })
            if ok_vcpu and ok_mem and ok_gpu:
                log.info("[java_billing] batch events sent: user=%s job=%s vcpu_sec=%.1f mem_gb_sec=%.1f gpu=%d",
                         user_id, job_id, vcpu_seconds, mem_gb_sec, gpu_count)

        threading.Thread(target=_run, daemon=True, name="java-billing-batch").start()
        return True

    def emit_s3_put(
        self,
        user_id: str,
        size_bytes: int,
        key: str,
        transaction_id: Optional[str] = None,
    ) -> bool:
        """Report an S3 upload: sends PUT request count + storage GB-hours events.

        Runs in a daemon thread — never blocks the caller.

        Remote Lago metrics required:
          s3_put_requests    — sum_agg on 'count' field
          s3_storage_gb_hours — sum_agg on 'gb_hours' field
        """
        ts = time.time()
        uid = transaction_id or uuid.uuid4().hex[:12]
        gb = size_bytes / (1024 ** 3)
        gb_hours = round(gb * 24 * 30, 6)   # 30-day retention projection

        def _run():
            ok_put = self._post("/api/billing/usage/events", {
                "externalCustomerId": external_id(user_id),
                "code": "s3_put_requests",
                "transactionId": f"s3-put-{uid}",
                "timestamp": ts,
                "properties": {"count": 1, "key": key},
            })
            ok_store = self._post("/api/billing/usage/events", {
                "externalCustomerId": external_id(user_id),
                "code": "s3_storage_gb_hours",
                "transactionId": f"s3-store-{uid}",
                "timestamp": ts,
                "properties": {"gb_hours": gb_hours},
            })
            if ok_put and ok_store:
                log.info("[java_billing] s3_put events sent: user=%s bytes=%d gb_hours=%.6f",
                         user_id, size_bytes, gb_hours)

        threading.Thread(target=_run, daemon=True, name="java-billing-s3").start()
        return True

    # Keep old emit_ec2 / emit_ebs as thin aliases so existing callers in
    # billing_router.py still compile — they will be migrated to emit_batch_job
    # and emit_s3_put in the next pass.
    def emit_ec2(self, user_id: str, instance_type: str, region: str,
                 duration_seconds: float, transaction_id: Optional[str] = None) -> bool:
        """Deprecated: use emit_batch_job() for full detail. Kept for compatibility."""
        return self.emit_batch_job(
            user_id=user_id, job_id=transaction_id or uuid.uuid4().hex[:12],
            instance_type=instance_type, vcpus=1.0, memory_mb=2048,
            gpu_count=0, duration_seconds=duration_seconds,
        )

    def emit_ebs(self, user_id: str, volume_type: str, size_gb: float,
                 duration_seconds: float, transaction_id: Optional[str] = None) -> bool:
        """Deprecated: use emit_s3_put() instead. Kept for compatibility."""
        size_bytes = int(size_gb * (1024 ** 3))
        return self.emit_s3_put(user_id=user_id, size_bytes=size_bytes,
                                key=f"legacy/{volume_type}", transaction_id=transaction_id)

    # ------------------------------------------------------------------
    # Quota (concurrent resource slots)
    # ------------------------------------------------------------------

    def acquire_quota(self, user_id: str, spec_code: str, resource_id: str) -> bool:
        """Acquire a concurrent resource slot before starting a job.

        Call before submitting a Nextflow/Batch run.
        Always call release_quota() in the completion/failure path.
        """
        return self._post("/api/billing/quota/acquire", {
            "externalCustomerId": external_id(user_id),
            "specCode": spec_code,
            "resourceId": resource_id,
        })

    def release_quota(self, user_id: str, spec_code: str, resource_id: str) -> bool:
        """Release a concurrent resource slot after a job ends (idempotent)."""
        return self._post("/api/billing/quota/release", {
            "externalCustomerId": external_id(user_id),
            "specCode": spec_code,
            "resourceId": resource_id,
        })

    # ------------------------------------------------------------------
    # Query endpoints (used for proxying to frontend)
    # ------------------------------------------------------------------

    def get_current_usage(self, user_id: str) -> Optional[dict]:
        """Fetch current billing period usage from Java service (live from Lago)."""
        return self._get(
            "/api/billing/usage/current",
            {"externalCustomerId": external_id(user_id)},
        )

    def get_usage_summary(
        self,
        user_id: str,
        start_date: str,   # "YYYY-MM-DD"
        end_date: str,     # "YYYY-MM-DD"
    ) -> Optional[dict]:
        """Fetch usage summary with daily trend data."""
        return self._get(
            "/api/billing/usage/summary",
            {
                "externalCustomerId": external_id(user_id),
                "startDate": start_date,
                "endDate": end_date,
            },
        )

    def get_usage_details(
        self,
        user_id: str,
        start_date: str,
        end_date: str,
        page: int = 0,
        size: int = 20,
    ) -> Optional[dict]:
        """Fetch paginated event-level detail from Java service local DB."""
        return self._get(
            "/api/billing/usage/details",
            {
                "externalCustomerId": external_id(user_id),
                "startDate": start_date,
                "endDate": end_date,
                "page": page,
                "size": size,
            },
        )

    def get_quota(self, user_id: str) -> Optional[dict]:
        """Fetch plan quota limits and current usage from Java service."""
        return self._get(
            "/api/billing/quota/usage",
            {"externalCustomerId": external_id(user_id)},
        )

    def get_invoices(
        self,
        user_id: str,
        page: int = 0,
        per_page: int = 10,
    ) -> Optional[dict]:
        """Fetch invoice list for a user (cached from Lago)."""
        return self._get(
            "/api/billing/invoices",
            {
                "externalCustomerId": external_id(user_id),
                "page": page,
                "perPage": per_page,
            },
        )

    def close(self) -> None:
        self._client.close()


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------

_client: Optional[JavaBillingClient] = None


def get_java_billing_client() -> Optional[JavaBillingClient]:
    """Return the singleton JavaBillingClient, or None if not enabled.

    Returns None when JAVA_BILLING_ENABLED is not "true" or when
    JAVA_BILLING_SERVICE_URL is not set — callers must guard with `if jbc:`.
    """
    global _client
    if not JAVA_BILLING_ENABLED or not JAVA_BILLING_URL:
        return None
    if _client is None:
        _client = JavaBillingClient()
        log.info("[java_billing] client initialised → %s", JAVA_BILLING_URL)
    return _client
