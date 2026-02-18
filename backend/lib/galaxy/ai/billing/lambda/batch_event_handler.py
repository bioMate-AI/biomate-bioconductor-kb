"""
AWS Lambda: AWS Batch Job State Change Handler

Triggered by EventBridge rule:
  source: ["aws.batch"]
  detail-type: ["Batch Job State Change"]

Handles job transitions to RUNNING, SUCCEEDED, and FAILED.
Writes cost events to the billing backend via an internal HTTP call
(or directly to Redis + Lago if co-located).

Deploy this as a Lambda function.  Set these environment variables:
  BILLING_API_URL   - internal URL of the BioMate billing service
  BILLING_API_KEY   - shared secret for service-to-service auth
  LAGO_API_URL      - Lago base URL
  LAGO_API_KEY      - Lago API key
  REDIS_URL         - ElastiCache endpoint

The job tags (set when submitting the Batch job) carry the user context:
  job.tags.user_id      - BioMate user ID
  job.tags.workflow_id  - BioMate workflow run ID
  job.tags.org_id       - Organisation ID (for team plans)
"""

import json
import os
import time
import logging
import boto3

# When running as Lambda, import from Lambda layer or vendored packages
try:
    import redis
    import httpx
except ImportError:
    redis  = None  # type: ignore
    httpx  = None  # type: ignore

log = logging.getLogger()
log.setLevel(logging.INFO)

BILLING_API_URL = os.environ.get("BILLING_API_URL", "")
BILLING_API_KEY = os.environ.get("BILLING_API_KEY", "")

batch_client = boto3.client("batch")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _describe_job(job_id: str) -> dict:
    """Fetch full job detail from AWS Batch API."""
    try:
        resp = batch_client.describe_jobs(jobs=[job_id])
        jobs = resp.get("jobs", [])
        return jobs[0] if jobs else {}
    except Exception as exc:
        log.error("DescribeJobs failed for %s: %s", job_id, exc)
        return {}


def _extract_user_tags(job: dict) -> tuple[str, str, str]:
    """Pull user_id, workflow_id, org_id from job tags."""
    tags = job.get("tags", {})
    return (
        tags.get("user_id", "unknown"),
        tags.get("workflow_id", "unknown"),
        tags.get("org_id", "unknown"),
    )


def _get_instance_info(job: dict) -> tuple[str, float, int, int, bool]:
    """
    Returns (instance_type, vcpus, memory_mb, gpu_count, is_spot).

    AWS Batch exposes container.vcpus and container.memory.
    The actual EC2 instance type is in attempts[0].container.networkInterfaces
    or can be inferred from the compute environment.
    For a simpler path, store instance_type in job tags when submitting.
    """
    container     = job.get("container", {})
    vcpus         = float(container.get("vcpus", 1))
    memory_mb     = int(container.get("memory", 2048))

    # GPU: look for resourceRequirements list.
    # AWS Batch supports multiple GPU resource types; any of these count as GPUs.
    _GPU_TYPES = {"GPU", "NVIDIA_GPU", "AMD_GPU", "TRAINIUM", "HABANA"}
    gpu_count = 0
    for req in container.get("resourceRequirements", []):
        if req.get("type", "").upper() in _GPU_TYPES:
            gpu_count += int(req.get("value", 0))

    # Instance type from tags (recommended: set this when submitting the job)
    tags          = job.get("tags", {})
    instance_type = tags.get("instance_type", "FARGATE")
    is_spot       = tags.get("capacity_type", "ON_DEMAND").upper() == "SPOT"

    return instance_type, vcpus, memory_mb, gpu_count, is_spot


def _notify_billing_api(event_type: str, payload: dict) -> None:
    """
    POST to the BioMate billing service.
    Fire-and-forget — Lambda does not wait for billing to process.
    """
    if not BILLING_API_URL or httpx is None:
        log.warning("BILLING_API_URL not set; skipping billing notification")
        return
    try:
        with httpx.Client(timeout=10.0) as client:
            client.post(
                f"{BILLING_API_URL}/internal/billing/{event_type}",
                json=payload,
                headers={"X-Internal-Key": BILLING_API_KEY},
            )
    except Exception as exc:
        log.error("billing notify failed: %s", exc)


# ---------------------------------------------------------------------------
# Lambda handler
# ---------------------------------------------------------------------------

def handler(event: dict, context) -> dict:
    """
    EventBridge event shape:
    {
        "source": "aws.batch",
        "detail-type": "Batch Job State Change",
        "detail": {
            "jobId": "...",
            "jobName": "...",
            "status": "RUNNING" | "SUCCEEDED" | "FAILED",
            "jobQueue": "...",
            "startedAt": 1700000000000,   # ms epoch (only when RUNNING+)
            "stoppedAt": 1700003600000,   # ms epoch (only when terminal)
            "container": { "vcpus": 4, "memory": 8192, ... }
        }
    }
    """
    detail = event.get("detail", {})
    job_id = detail.get("jobId")
    status = detail.get("status")

    if not job_id or not status:
        log.error("EventBridge event missing jobId or status: %s", json.dumps(detail))
        return {"statusCode": 400, "body": "missing jobId or status"}

    log.info("Batch job %s → %s", job_id, status)

    # Fetch full job details (tags, resource requirements)
    job = _describe_job(job_id)
    if not job:
        log.warning("Job %s not found in Batch API", job_id)
        return {"statusCode": 404}

    user_id, workflow_id, org_id = _extract_user_tags(job)
    instance_type, vcpus, memory_mb, gpu_count, is_spot = _get_instance_info(job)

    # -----------------------------------------------------------------------
    if status == "RUNNING":
        started_at_ms = job.get("startedAt", int(time.time() * 1000))
        log.info("Job STARTED user=%s job=%s instance=%s vcpu=%.1f gpu=%d",
                 user_id, job_id, instance_type, vcpus, gpu_count)
        _notify_billing_api("job_started", {
            "user_id":       user_id,
            "job_id":        job_id,
            "workflow_id":   workflow_id,
            "instance_type": instance_type,
            "vcpus":         vcpus,
            "memory_mb":     memory_mb,
            "gpu_count":     gpu_count,
            "started_at_ms": started_at_ms,
            "is_spot":       is_spot,
        })

    # -----------------------------------------------------------------------
    elif status in ("SUCCEEDED", "FAILED"):
        started_at_ms = job.get("startedAt")
        stopped_at_ms = job.get("stoppedAt", int(time.time() * 1000))

        if not started_at_ms:
            # Job never reached RUNNING (failed at scheduling) → zero cost
            log.info("Job %s %s before RUNNING — no compute charge", job_id, status)
            return {"statusCode": 200}

        duration_seconds = (stopped_at_ms - started_at_ms) / 1000.0
        log.info("Job %s user=%s duration=%.1fs vcpu=%.1f gpu=%d",
                 status, user_id, duration_seconds, vcpus, gpu_count)

        _notify_billing_api("job_completed", {
            "user_id":          user_id,
            "job_id":           job_id,
            "workflow_id":      workflow_id,
            "status":           status,
            "instance_type":    instance_type,
            "vcpus":            vcpus,
            "memory_mb":        memory_mb,
            "gpu_count":        gpu_count,
            "duration_seconds": duration_seconds,
            "is_spot":          is_spot,
        })

    return {"statusCode": 200}
