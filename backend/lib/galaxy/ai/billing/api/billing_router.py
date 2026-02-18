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

Lago webhook endpoint:
  POST /webhooks/lago               — subscription events, invoice events
"""

import os
import hmac
import hashlib
import logging
import time
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
        object_key=payload.key,
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
    svc    = get_cost_service()
    refund = svc.record_s3_delete(
        user_id=payload.user_id,
        object_key=payload.key,
    )
    log.info("S3 delete user=%s key=%s refund_usd=%.6f",
             payload.user_id, payload.key, refund)
    return {"ok": True, "refund_usd": refund}


# ---------------------------------------------------------------------------
# Internal API: User registration
# ---------------------------------------------------------------------------

class RegisterUserPayload(BaseModel):
    user_id: str
    email: str
    name: str
    plan: str = "free"      # Lago plan code, e.g. "free", "basic", "pro"
    metadata: dict = {}     # optional key-value tags forwarded to Lago


@router.post("/internal/billing/register_user", dependencies=[Depends(require_internal_key)])
def internal_register_user(payload: RegisterUserPayload):
    """
    Called when a new BioMate user signs up.
      1. Creates / updates the Lago customer record (idempotent)
      2. Subscribes the customer to their plan in Lago (so usage events are billed)
      3. Sets initial quota in Redis based on the plan
    """
    lago = get_lago_client()

    # 1. Upsert Lago customer
    lago.upsert_customer(
        user_id=payload.user_id,
        email=payload.email,
        name=payload.name,
        metadata=payload.metadata or {},
    )

    # 2. Assign the plan subscription in Lago
    lago.assign_plan(payload.user_id, payload.plan)

    # 3. Set quota in Redis so the quota enforcer can gate job submissions immediately
    ensure_quota_set(payload.user_id, payload.plan)

    log.info(
        "User registered: user_id=%s email=%s plan=%s",
        payload.user_id, payload.email, payload.plan,
    )
    return {"ok": True, "user_id": payload.user_id, "plan": payload.plan}


# ---------------------------------------------------------------------------
# Admin monitoring endpoints
# ---------------------------------------------------------------------------

@router.get("/internal/billing/admin/health", dependencies=[Depends(require_internal_key)])
def admin_health():
    """System health: Redis connectivity, active jobs, Lago status, Lambda heartbeat."""
    import urllib.request
    svc = get_cost_service()
    r   = svc._r
    month = _month_key()

    # Redis
    try:
        r.ping()
        redis_status = "ok"
    except Exception as exc:
        redis_status = f"error: {exc}"

    # Active in-flight Batch jobs
    try:
        job_keys     = r.keys("cost:*:job:*:running")
        active_jobs  = len(job_keys)
    except Exception:
        active_jobs  = -1

    # Lambda heartbeat
    try:
        last_ts = r.get("billing:last_batch_event_ts")
        last_age = int(time.time() - float(last_ts)) if last_ts else None
    except Exception:
        last_age = None

    # Lago connectivity
    if not _LAGO_API_KEY:
        lago_status = "disabled (LAGO_API_KEY not set)"
    else:
        lago = get_lago_client()
        try:
            req = urllib.request.Request(
                f"{lago._base}/api/v1/billable_metrics?per_page=1",
                headers=lago._headers,
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                lago_status = "ok" if resp.status == 200 else f"error: {resp.status}"
        except Exception as exc:
            lago_status = f"error: {exc}"

    # Total users tracked
    try:
        user_keys       = r.keys(f"cost:*:month:{month}:total")
        total_users     = len(user_keys)
    except Exception:
        total_users = 0

    result = {
        "redis":                   redis_status,
        "active_jobs":             active_jobs,
        "lago":                    lago_status,
        "total_users_tracked":     total_users,
        "month":                   month,
    }
    if last_age is not None:
        result["last_batch_event_age_sec"] = last_age
    return result


@router.get("/internal/billing/admin/users", dependencies=[Depends(require_internal_key)])
def admin_users():
    """List all users sorted by total spend this month."""
    svc   = get_cost_service()
    r     = svc._r
    month = _month_key()

    total_keys = r.keys(f"cost:*:month:{month}:total")
    users = []
    for key in total_keys:
        uid       = key.split(":")[1]
        total     = float(r.get(key) or 0)
        quota     = float(r.get(f"quota:{uid}:month:{month}:limit") or 0)
        pct       = round(total / quota * 100, 1) if quota else 0.0
        llm_h     = r.hgetall(f"cost:{uid}:month:{month}:llm")
        compute_h = r.hgetall(f"cost:{uid}:month:{month}:compute")
        storage_h = r.hgetall(f"cost:{uid}:month:{month}:storage")
        users.append({
            "user_id":     uid,
            "total_usd":   round(total, 4),
            "quota_usd":   round(quota, 2),
            "pct":         pct,
            "llm_usd":     round(float(llm_h.get("input_usd", 0)) + float(llm_h.get("output_usd", 0)), 4),
            "compute_usd": round(float(compute_h.get("vcpu_usd", 0)) + float(compute_h.get("gpu_usd", 0)) + float(compute_h.get("mem_usd", 0)), 4),
            "storage_usd": round(float(storage_h.get("storage_usd", 0)) + float(storage_h.get("request_usd", 0)), 4),
        })
    users.sort(key=lambda u: u["total_usd"], reverse=True)
    return {"month": month, "user_count": len(users), "users": users}


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
