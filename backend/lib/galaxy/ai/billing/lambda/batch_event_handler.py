"""
AWS Lambda: AWS Batch Job State Change Handler

Triggered by EventBridge rule:
  source: ["aws.batch"]
  detail-type: ["Batch Job State Change"]

Design principle: NO extra AWS API calls. The EventBridge event already contains
all fields we need (container.environment, container.vcpus, startedAt, stoppedAt).
Calling describe_jobs() or any other AWS API fails when the Lambda's VPC subnets
lack a NAT gateway route — this handler avoids that entirely.

Billing data is written DIRECTLY to Redis. Keys follow realtime_cost_service.py:
  billing:batch:job:{job_id}           HSET — per-job record (kept 30 days)
  cost:{user_id}:month:{YYYY-MM}:total INCRBYFLOAT — monthly aggregate in USD

User context arrives via container environment variables set by nextflow_executor.py:
  BIOMATE_USER_ID  — BioMate user ID string
  BIOMATE_RUN_ID   — Nextflow run UUID

Required environment variable:
  REDIS_URL — ElastiCache endpoint (redis://host:6379)
"""

import json
import os
import time
import logging
import uuid
import urllib.request
from datetime import datetime, timezone

try:
    import redis as redis_lib
except ImportError:
    redis_lib = None  # type: ignore

log = logging.getLogger()
log.setLevel(logging.INFO)

REDIS_URL = os.environ.get("REDIS_URL", "")

# ---------------------------------------------------------------------------
# EC2 on-demand pricing (USD/vCPU-hour, us-west-2, 2026-Q1)
# ---------------------------------------------------------------------------
_USD_PER_VCPU_HOUR = {
    "m5.large":    0.096 / 2,
    "m5.xlarge":   0.192 / 4,
    "m5.2xlarge":  0.384 / 8,
    "m5.4xlarge":  0.768 / 16,
    "g4dn.xlarge": 0.526 / 4,
    "p3.2xlarge":  3.06  / 8,
}
_DEFAULT_USD_PER_VCPU_HOUR = 0.096 / 2  # m5.large fallback


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _redis_client():
    if not REDIS_URL or redis_lib is None:
        raise RuntimeError("REDIS_URL not set or redis package unavailable")
    return redis_lib.from_url(REDIS_URL, decode_responses=True, socket_timeout=5)


def _parse_container(detail: dict) -> tuple[str, str, float, int, str]:
    """
    Parse user_id, run_id, vcpus, gpu_count, instance_type from EventBridge detail.

    EventBridge 'Batch Job State Change' detail shape (relevant fields):
      detail.container.environment  — list of {name, value}
      detail.container.vcpus        — allocated vCPUs (string or int)
      detail.container.resourceRequirements — [{type: GPU, value: N}]
      detail.tags.instance_type     — set at job submit time (optional)
    """
    container = detail.get("container", {})

    # User context from container environment (injected by nextflow_executor.py)
    env_list = container.get("environment", [])
    env = {item["name"]: item["value"] for item in env_list if "name" in item}
    user_id = env.get("BIOMATE_USER_ID", "unknown")
    run_id = env.get("BIOMATE_RUN_ID", "unknown")

    # Resource info
    vcpus = float(container.get("vcpus", 1) or 1)
    _GPU_TYPES = {"GPU", "NVIDIA_GPU", "AMD_GPU", "TRAINIUM", "HABANA"}
    gpu_count = 0
    for req in container.get("resourceRequirements", []):
        if req.get("type", "").upper() in _GPU_TYPES:
            try:
                gpu_count += int(req.get("value", 0))
            except (ValueError, TypeError):
                pass

    # Instance type from job-level tags (optional, best-effort)
    tags = detail.get("tags", {})
    instance_type = tags.get("instance_type", "m5.large")

    # Memory in MiB (present in Batch EventBridge events as container.memory)
    memory_mib = int(container.get("memory", 0) or 0)

    return user_id, run_id, vcpus, gpu_count, instance_type, memory_mib


def _estimate_cost_usd(instance_type: str, vcpus: float, duration_seconds: float) -> float:
    rate = _USD_PER_VCPU_HOUR.get(instance_type, _DEFAULT_USD_PER_VCPU_HOUR)
    billable_seconds = max(duration_seconds, 60.0)  # 1-min minimum
    return round(rate * vcpus * (billable_seconds / 3600.0), 6)


# ---------------------------------------------------------------------------
# Lago emission — uses same event codes as lago_client.py emit_batch_job()
# ---------------------------------------------------------------------------

_LAGO_URL = os.environ.get("LAGO_API_URL", "").rstrip("/")
_LAGO_KEY = os.environ.get("LAGO_API_KEY", "")


def _sub_id(user_id: str, plan_code: str = "base") -> str:
    ext_id = f"bm_{user_id}" if not user_id.startswith("bm_") else user_id
    return f"{ext_id}_{plan_code}"


def _emit_to_lago(user_id: str, job_id: str, vcpus: float, gpu_count: int,
                  memory_mib: float, duration_seconds: float) -> None:
    """Emit batch compute events to Lago using the same event codes as lago_client.py."""
    if not _LAGO_URL or not _LAGO_KEY:
        log.info("Lago not configured (LAGO_API_URL/LAGO_API_KEY missing) — skipping emit for job %s", job_id)
        return
    ts = int(time.time())
    sub = _sub_id(user_id)
    memory_gb = memory_mib / 1024.0
    events = [
        {
            "transaction_id": f"batch-vcpu-{job_id}",
            "external_subscription_id": sub,
            "code": "batch_vcpu_seconds",
            "timestamp": ts,
            "properties": {"seconds": round(vcpus * duration_seconds, 3)},
        },
        {
            "transaction_id": f"batch-mem-{job_id}",
            "external_subscription_id": sub,
            "code": "batch_memory_gb_sec",
            "timestamp": ts,
            "properties": {"gb_seconds": round(memory_gb * duration_seconds, 3)},
        },
    ]
    if gpu_count > 0:
        events.append({
            "transaction_id": f"batch-gpu-{job_id}",
            "external_subscription_id": sub,
            "code": "batch_gpu_seconds",
            "timestamp": ts,
            "properties": {"seconds": round(gpu_count * duration_seconds, 3)},
        })
    payload = json.dumps({"events": events}).encode("utf-8")
    try:
        req = urllib.request.Request(
            f"{_LAGO_URL}/api/v1/events/batch",
            data=payload,
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {_LAGO_KEY}"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            log.info("Lago batch emit accepted for job=%s user=%s vcpus=%.1f duration=%.1fs",
                     job_id, user_id, vcpus, duration_seconds)
    except Exception as exc:
        log.warning("Lago emit failed for job %s (non-fatal): %s", job_id, exc)


# ---------------------------------------------------------------------------
# Redis writes
# ---------------------------------------------------------------------------

def _record_started(r, job_id: str, user_id: str, run_id: str,
                    vcpus: float, gpu_count: int, instance_type: str,
                    started_at_ms: int) -> None:
    key = f"billing:batch:job:{job_id}"
    r.hset(key, mapping={
        "user_id": user_id, "run_id": run_id,
        "instance_type": instance_type, "vcpus": str(vcpus),
        "gpu_count": str(gpu_count), "started_at_ms": str(started_at_ms),
        "status": "RUNNING",
    })
    r.expire(key, 86400 * 30)
    log.info("Recorded STARTED job=%s user=%s vcpu=%.1f", job_id, user_id, vcpus)


def _record_completed(r, job_id: str, user_id: str, run_id: str,
                      vcpus: float, gpu_count: int, instance_type: str,
                      memory_mib: float, duration_seconds: float, status: str) -> None:
    cost_usd = _estimate_cost_usd(instance_type, vcpus, duration_seconds)
    month = datetime.now(timezone.utc).strftime("%Y-%m")

    job_key = f"billing:batch:job:{job_id}"
    r.hset(job_key, mapping={
        "status": status,
        "duration_seconds": str(round(duration_seconds, 3)),
        "cost_usd": str(cost_usd),
    })
    r.expire(job_key, 86400 * 30)

    if status == "SUCCEEDED" and user_id != "unknown":
        r.incrbyfloat(f"cost:{user_id}:month:{month}:total", cost_usd)
        r.expire(f"cost:{user_id}:month:{month}:total", 86400 * 90)
        r.incrbyfloat(f"billing:run:{run_id}:compute_usd", cost_usd)
        r.expire(f"billing:run:{run_id}:compute_usd", 86400 * 90)
        # Emit to Lago using established billing event codes
        _emit_to_lago(user_id, job_id, vcpus, gpu_count, memory_mib, duration_seconds)

    log.info("Recorded %s job=%s user=%s duration=%.1fs cost=$%.6f",
             status, job_id, user_id, duration_seconds, cost_usd)


# ---------------------------------------------------------------------------
# Lambda handler
# ---------------------------------------------------------------------------

def handler(event: dict, context) -> dict:
    """
    EventBridge 'Batch Job State Change' handler.
    All data is read from the event itself — no external API calls.
    """
    detail = event.get("detail", {})
    job_id = detail.get("jobId")
    status = detail.get("status")

    if not job_id or not status:
        log.error("Missing jobId or status: %s", json.dumps(detail))
        return {"statusCode": 400}

    log.info("Batch job %s → %s", job_id, status)

    user_id, run_id, vcpus, gpu_count, instance_type, memory_mib = _parse_container(detail)

    try:
        r = _redis_client()
        r.set("billing:last_batch_event_ts", str(time.time()), ex=3600)
    except Exception as exc:
        log.error("Redis unavailable: %s — billing event lost for job %s", exc, job_id)
        return {"statusCode": 500, "body": "redis unavailable"}

    if status == "RUNNING":
        started_at_ms = int(detail.get("startedAt") or time.time() * 1000)
        _record_started(r, job_id, user_id, run_id, vcpus, gpu_count, instance_type, started_at_ms)

    elif status in ("SUCCEEDED", "FAILED"):
        started_at_ms = detail.get("startedAt")
        stopped_at_ms = int(detail.get("stoppedAt") or time.time() * 1000)

        if not started_at_ms:
            log.info("Job %s %s before RUNNING — no compute charge", job_id, status)
            return {"statusCode": 200}

        duration_seconds = (stopped_at_ms - int(started_at_ms)) / 1000.0
        _record_completed(r, job_id, user_id, run_id, vcpus, gpu_count,
                          instance_type, memory_mib, duration_seconds, status)

    return {"statusCode": 200}
