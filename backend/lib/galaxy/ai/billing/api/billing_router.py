"""
BioMate Billing API Router (FastAPI)

Public endpoints (require user JWT auth):
  GET  /api/billing/usage           — current month breakdown
  GET  /api/billing/usage/history   — past N months
  GET  /api/billing/quota           — plan limits and current usage %
  GET  /api/billing/jobs/running    — in-flight jobs with live cost estimate

Internal endpoints (require X-Internal-Key header, not exposed to public):
  POST /internal/billing/job_started    — called by Batch Lambda on RUNNING
  POST /internal/billing/job_completed  — called by Batch Lambda on SUCCEEDED/FAILED
  POST /internal/billing/s3_put         — called by S3 Lambda on upload
  POST /internal/billing/s3_delete      — called by S3 Lambda on delete
  POST /internal/billing/add-credits    — called by Stripe webhook to top up quota
  GET  /internal/billing/admin/users    — admin: all users' live costs this month
  GET  /internal/billing/admin/health   — admin: system health (Redis, Lambda, Lago)

Lago webhook endpoint:
  POST /webhooks/lago               — subscription events, invoice events
"""

import os
import hmac
import hashlib
import logging
from datetime import datetime, timezone
from typing import Optional

import jwt as _jwt
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel

from ..core.cost_calculator import CostCalculator
from ..core.lago_client import get_lago_client, LAGO_API_KEY as _LAGO_API_KEY
from ..core.realtime_cost_service import get_cost_service, _month_key
from ..core.quota_enforcer import ensure_quota_set

log = logging.getLogger(__name__)

INTERNAL_API_KEY    = os.environ.get("BILLING_INTERNAL_KEY", os.environ.get("BILLING_API_KEY", "change-me"))
if INTERNAL_API_KEY == "change-me":
    log.warning(
        "BILLING_INTERNAL_KEY is not set — internal billing endpoints are using the insecure "
        "default key. Set BILLING_INTERNAL_KEY in production."
    )
LAGO_WEBHOOK_SECRET = os.environ.get("LAGO_WEBHOOK_SECRET", "")
if not LAGO_WEBHOOK_SECRET:
    log.warning(
        "LAGO_WEBHOOK_SECRET is not set — Lago webhook signature verification is disabled. "
        "Any caller can trigger subscription/invoice events. Set LAGO_WEBHOOK_SECRET in production."
    )
_JWT_SECRET         = os.environ.get("JWT_SECRET", "")
_JWT_ALGORITHM      = "HS256"

router    = APIRouter()
calculator = CostCalculator()


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------

def require_internal_key(x_internal_key: str = Header(...)):
    if x_internal_key != INTERNAL_API_KEY:
        raise HTTPException(status_code=403, detail="Forbidden")


def current_user_id(authorization: str = Header(...)) -> str:
    """
    Decodes the Bearer JWT produced by AuthService._create_jwt_token().
    Token payload: {'user_id': int, 'email': str, 'exp': ..., 'iat': ...}
    Returns user_id as a string so it matches the Redis key schema.
    """
    token = authorization.removeprefix("Bearer ").strip()
    if not _JWT_SECRET:
        # Dev fallback: accept raw user_id strings when JWT_SECRET is not set
        if not token:
            raise HTTPException(status_code=401, detail="Empty user_id")
        return token
    try:
        payload = _jwt.decode(token, _JWT_SECRET, algorithms=[_JWT_ALGORITHM])
    except _jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except _jwt.InvalidTokenError as exc:
        raise HTTPException(status_code=401, detail=f"Invalid token: {exc}")
    user_id = payload.get("user_id")
    if user_id is None:
        raise HTTPException(status_code=401, detail="Token missing user_id claim")
    uid = str(user_id).strip()
    if not uid:
        raise HTTPException(status_code=401, detail="Token contains empty user_id claim")
    return uid


# ---------------------------------------------------------------------------
# Public API: Usage
# ---------------------------------------------------------------------------

@router.get("/api/billing/usage")
def get_usage(
    month: Optional[str] = None,
    user_id: str = Depends(current_user_id),
):
    """
    Returns real-time cost breakdown for the current (or requested) month.
    Reads from Redis → <5ms response.

    Response includes committed costs + running-job estimates.
    """
    svc  = get_cost_service()
    data = svc.get_current_costs(user_id, month)
    return data


@router.get("/api/billing/usage/history")
def get_usage_history(
    months: int = 3,
    user_id: str = Depends(current_user_id),
):
    """Past N months of cost data (from Redis, falls back to Lago)."""
    months = max(1, min(months, 24))   # clamp: 1–24 months
    svc     = get_cost_service()
    now     = datetime.now(timezone.utc)
    results = []

    for i in range(months):
        # Compute month string for i months ago
        month_dt = now.replace(day=1)
        for _ in range(i):
            # subtract one month
            month_dt = month_dt.replace(day=1)
            if month_dt.month == 1:
                month_dt = month_dt.replace(year=month_dt.year - 1, month=12)
            else:
                month_dt = month_dt.replace(month=month_dt.month - 1)
        month_str = month_dt.strftime("%Y-%m")
        results.append(svc.get_current_costs(user_id, month_str))

    return {"user_id": user_id, "history": results}


@router.get("/api/billing/quota")
def get_quota(user_id: str = Depends(current_user_id)):
    """Returns plan limit, current usage, and overage warning."""
    svc   = get_cost_service()
    costs = svc.get_current_costs(user_id)
    return {
        "user_id":    user_id,
        "quota_usd":  costs.get("quota_usd"),
        "used_usd":   costs.get("total_usd"),
        "quota_pct":  costs.get("quota_pct"),
        "over_quota": (costs.get("quota_pct") or 0) >= 100,
    }


@router.get("/api/billing/jobs/running")
def get_running_jobs(user_id: str = Depends(current_user_id)):
    """Returns in-flight AWS Batch jobs with live cost estimates."""
    svc   = get_cost_service()
    costs = svc.get_current_costs(user_id)
    return {
        "user_id":          user_id,
        "running_jobs":     costs["running_jobs"],
        "running_total_usd": costs["running_estimate_usd"],
    }


# ---------------------------------------------------------------------------
# Internal API: Batch job events
# ---------------------------------------------------------------------------

class JobStartedPayload(BaseModel):
    user_id: str
    job_id: str
    workflow_id: str
    instance_type: str
    vcpus: float
    memory_mb: int
    gpu_count: int
    started_at_ms: int
    is_spot: bool = False


class JobCompletedPayload(BaseModel):
    user_id: str
    job_id: str
    workflow_id: str
    status: str
    instance_type: str
    vcpus: float
    memory_mb: int
    gpu_count: int
    duration_seconds: float
    is_spot: bool = False


@router.post("/internal/billing/job_started", dependencies=[Depends(require_internal_key)])
def internal_job_started(payload: JobStartedPayload):
    svc = get_cost_service()
    svc.register_running_job(
        user_id=payload.user_id,
        job_id=payload.job_id,
        instance_type=payload.instance_type,
        vcpus=payload.vcpus,
        memory_mb=payload.memory_mb,
        gpu_count=payload.gpu_count,
        started_at_ms=payload.started_at_ms,
        is_spot=payload.is_spot,
    )
    log.info("registered running job %s for user %s", payload.job_id, payload.user_id)
    return {"ok": True}


@router.post("/internal/billing/job_completed", dependencies=[Depends(require_internal_key)])
def internal_job_completed(payload: JobCompletedPayload):
    # Calculate actual cost
    cost = calculator.batch_job_cost(
        job_id=payload.job_id,
        user_id=payload.user_id,
        workflow_id=payload.workflow_id,
        instance_type=payload.instance_type,
        vcpus=payload.vcpus,
        memory_mb=payload.memory_mb,
        gpu_count=payload.gpu_count,
        duration_seconds=payload.duration_seconds,
        is_spot=payload.is_spot,
    )

    # Write to Redis
    svc = get_cost_service()
    svc.record_batch_job_cost(
        user_id=payload.user_id,
        job_id=payload.job_id,
        vcpu_usd=cost.vcpu_cost,
        gpu_usd=cost.gpu_cost,
        mem_usd=cost.memory_cost,
        duration_seconds=payload.duration_seconds,
    )

    # Emit to Lago
    lago = get_lago_client()
    lago.emit_batch_job(
        user_id=payload.user_id,
        job_id=payload.job_id,
        vcpus=payload.vcpus,
        gpu_count=payload.gpu_count,
        memory_gb=payload.memory_mb / 1024,
        duration_seconds=payload.duration_seconds,
    )

    log.info(
        "job %s complete user=%s cost=$%.6f (vcpu=%.6f gpu=%.6f mem=%.6f)",
        payload.job_id, payload.user_id,
        cost.total_cost, cost.vcpu_cost, cost.gpu_cost, cost.memory_cost,
    )
    return {"ok": True, "total_cost_usd": cost.total_cost}


# ---------------------------------------------------------------------------
# Internal API: S3 events
# ---------------------------------------------------------------------------

class S3PutPayload(BaseModel):
    user_id: str
    workflow_id: str
    bucket: str
    key: str
    size_bytes: int


class S3DeletePayload(BaseModel):
    user_id: str
    workflow_id: str
    bucket: str
    key: str


@router.post("/internal/billing/s3_put", dependencies=[Depends(require_internal_key)])
def internal_s3_put(payload: S3PutPayload):
    cost = calculator.s3_put_cost(
        user_id=payload.user_id,
        bucket=payload.bucket,
        size_bytes=payload.size_bytes,
    )
    svc = get_cost_service()
    svc.record_s3_put(
        user_id=payload.user_id,
        size_bytes=payload.size_bytes,
        storage_usd=cost.storage_cost,
        request_usd=cost.request_cost,
    )
    get_lago_client().emit_s3_put(
        user_id=payload.user_id,
        size_bytes=payload.size_bytes,
        key=payload.key,
    )
    return {"ok": True, "total_cost_usd": cost.total_cost}


class AddCreditsPayload(BaseModel):
    user_id: str
    amount_usd: float      # e.g. 10.0, 25.0, 50.0
    payment_id: str = ""   # Stripe PaymentIntent or CheckoutSession ID (for audit log)


@router.post("/internal/billing/add-credits", dependencies=[Depends(require_internal_key)])
def internal_add_credits(payload: AddCreditsPayload):
    """
    Called by the Stripe webhook handler after a successful credit top-up payment.
    Increases the user's Redis quota cap by the purchased amount.
    """
    if payload.amount_usd <= 0:
        raise HTTPException(status_code=400, detail="amount_usd must be positive")
    svc = get_cost_service()
    new_limit = svc.add_to_quota(user_id=payload.user_id, amount_usd=payload.amount_usd)
    log.info(
        "Credits added: user=%s +$%.2f (payment=%s) → new_limit=$%.2f",
        payload.user_id, payload.amount_usd, payload.payment_id, new_limit,
    )
    return {"ok": True, "new_quota_usd": new_limit}


@router.post("/internal/billing/s3_delete", dependencies=[Depends(require_internal_key)])
def internal_s3_delete(payload: S3DeletePayload):
    # TODO: subtract storage cost for remaining days of the retention period
    log.info("S3 delete user=%s key=%s", payload.user_id, payload.key)
    return {"ok": True}


# ---------------------------------------------------------------------------
# Admin / Monitoring Endpoints  (X-Internal-Key required)
# ---------------------------------------------------------------------------

@router.get("/internal/billing/admin/users", dependencies=[Depends(require_internal_key)])
async def admin_all_users():
    """
    Return live cost data for ALL users this month.
    Used by admin dashboards and monitoring scripts.

    Response:
      { "month": "2026-02", "users": [{ "user_id", "total_usd", "quota_usd",
        "pct", "llm_usd", "compute_usd", "storage_usd" }, ...] }

    Example (curl):
      curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
           http://localhost:8081/internal/billing/admin/users
    """
    svc = get_cost_service()
    month = _month_key()
    r = svc._r  # Redis client

    # Scan all quota keys to find every tracked user this month
    pattern = f"quota:*:month:{month}:limit"
    user_ids = []
    cursor = 0
    while True:
        cursor, keys = r.scan(cursor, match=pattern, count=500)
        for k in keys:
            # key format: quota:{user_id}:month:{month}:limit
            parts = k.decode() if isinstance(k, bytes) else k
            uid = parts.split(":")[1]
            user_ids.append(uid)
        if cursor == 0:
            break

    users = []
    for uid in sorted(set(user_ids)):
        costs = svc.get_current_costs(uid, month)
        quota = float(r.get(f"quota:{uid}:month:{month}:limit") or 0)
        total = costs.get("total_usd", 0)
        users.append({
            "user_id": uid,
            "total_usd": round(total, 4),
            "quota_usd": round(quota, 2),
            "pct": round(total / quota * 100, 1) if quota else 0,
            "llm_usd": round(costs.get("llm", {}).get("total_usd", 0), 4),
            "compute_usd": round(costs.get("compute", {}).get("total_usd", 0), 4),
            "storage_usd": round(costs.get("storage", {}).get("total_usd", 0), 6),
        })

    # Sort by total spend descending
    users.sort(key=lambda u: u["total_usd"], reverse=True)
    return {"month": month, "user_count": len(users), "users": users}


@router.get("/internal/billing/admin/health", dependencies=[Depends(require_internal_key)])
async def admin_health():
    """
    Health check for the entire billing pipeline.
    Returns status of Redis, Lambda reachability (via recent events), and Lago.

    Response:
      { "redis": "ok"|"error", "active_jobs": N,
        "last_batch_event_age_sec": N,   # seconds since last Lambda event
        "lago": "ok"|"disabled"|"error",
        "total_users_tracked": N }

    Example (curl):
      curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
           http://localhost:8081/internal/billing/admin/health
    """
    svc = get_cost_service()
    r = svc._r
    month = _month_key()
    result: dict = {}

    # Redis ping
    try:
        r.ping()
        result["redis"] = "ok"
    except Exception as exc:
        result["redis"] = f"error: {exc}"

    # Active jobs tracked in Redis
    try:
        job_keys = r.keys("cost:*:job:*:running")
        result["active_jobs"] = len(job_keys)
    except Exception:
        result["active_jobs"] = -1

    # Last Lambda event timestamp (stored by batch_billing handler)
    try:
        ts = r.get("billing:last_batch_event_ts")
        if ts:
            age = int(datetime.now(timezone.utc).timestamp()) - int(ts)
            result["last_batch_event_age_sec"] = age
        else:
            result["last_batch_event_age_sec"] = None
    except Exception:
        result["last_batch_event_age_sec"] = None

    # Lago reachability
    lago = get_lago_client()
    if not _LAGO_API_KEY:
        result["lago"] = "disabled (LAGO_API_KEY not set)"
    else:
        try:
            import urllib.request
            req = urllib.request.Request(
                f"{lago._base}/api/v1/billable_metrics?per_page=1",
                headers=lago._headers,
            )
            with urllib.request.urlopen(req, timeout=3):
                result["lago"] = "ok"
        except Exception as exc:
            result["lago"] = f"error: {exc}"

    # Total users tracked this month
    try:
        cursor, keys = r.scan(0, match=f"quota:*:month:{month}:limit", count=1000)
        result["total_users_tracked"] = len(keys)
    except Exception:
        result["total_users_tracked"] = -1

    result["month"] = month
    return result


# ---------------------------------------------------------------------------
# Lago Webhook
# ---------------------------------------------------------------------------

def _verify_lago_signature(body: bytes, signature: str) -> bool:
    if not LAGO_WEBHOOK_SECRET:
        return True  # skip verification in dev
    expected = hmac.new(
        LAGO_WEBHOOK_SECRET.encode(), body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


@router.post("/webhooks/lago")
async def lago_webhook(request: Request):
    """
    Lago sends webhook events for:
      - subscription.started      → set quota in Redis
      - subscription.terminated   → remove quota
      - invoice.created           → log / notify user
      - customer.checkout_url_generated → redirect user
    """
    body      = await request.body()
    signature = request.headers.get("X-Lago-Signature", "")

    if not _verify_lago_signature(body, signature):
        raise HTTPException(status_code=401, detail="Invalid signature")

    import json
    payload = json.loads(body)
    event   = payload.get("webhook_type", "")
    log.info("Lago webhook: %s", event)

    if event in ("subscription.started", "subscription.terminated", "subscription.updated"):
        _handle_subscription_event(payload)
    elif event == "invoice.created":
        _handle_invoice_event(payload)

    return {"ok": True}


def _handle_subscription_event(payload: dict) -> None:
    sub     = payload.get("subscription", {})
    user_id = sub.get("external_customer_id")
    plan    = sub.get("plan_code", "free")
    if user_id:
        ensure_quota_set(user_id, plan)
        log.info("Updated quota for user=%s plan=%s", user_id, plan)


def _handle_invoice_event(payload: dict) -> None:
    invoice = payload.get("invoice", {})
    log.info("Invoice created: %s amount=%s",
             invoice.get("number"), invoice.get("total_amount_cents"))
    # TODO: notify user via email / in-app notification
