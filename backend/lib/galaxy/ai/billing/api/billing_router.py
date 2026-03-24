"""
BioMate Billing API Router (FastAPI)

Public endpoints (require user JWT auth):
  GET  /api/billing/usage             — current month breakdown
  GET  /api/billing/usage/history     — past N months
  GET  /api/billing/usage/cohort      — user's relative cost position in the cohort
  GET  /api/billing/quota             — plan limits and current usage %
  GET  /api/billing/jobs/running      — in-flight jobs with live cost estimate

Internal endpoints (require X-Internal-Key header, not exposed to public):
  POST /internal/billing/job_started      — called by Batch Lambda on RUNNING
  POST /internal/billing/job_completed    — called by Batch Lambda on SUCCEEDED/FAILED
  POST /internal/billing/s3_put          — called by S3 Lambda on upload
  POST /internal/billing/s3_delete       — called by S3 Lambda on delete
  GET  /internal/billing/admin/cohort_cost — cohort cost dashboard (cost per active user/month)

Lago webhook endpoint:
  POST /webhooks/lago               — subscription events, invoice events
"""

import os
import hmac
import hashlib
import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Optional

import jwt as _jwt
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel

try:
    from slowapi import Limiter
    from slowapi.util import get_remote_address
    from slowapi.errors import RateLimitExceeded
    _RATE_LIMITING_AVAILABLE = True
except ImportError:
    _RATE_LIMITING_AVAILABLE = False
    Limiter = None
    get_remote_address = None
    RateLimitExceeded = None

from ..core.cost_calculator import CostCalculator
from ..core.lago_client import get_lago_client, LAGO_API_KEY as _LAGO_API_KEY
from ..core.realtime_cost_service import get_cost_service, _month_key
from ..core.quota_enforcer import ensure_quota_set
from ..java_billing_client import get_java_billing_client

log = logging.getLogger(__name__)

# Environment configuration
_ALLOW_INSECURE_DEV_MODE = os.environ.get("BILLING_DEV_MODE", "").lower() == "true"

# Guard: BILLING_DEV_MODE must never be enabled in production
if _ALLOW_INSECURE_DEV_MODE and os.environ.get("ENV", "development") == "production":
    raise RuntimeError(
        "BILLING_DEV_MODE=true is not allowed when ENV=production. "
        "Unset BILLING_DEV_MODE before deploying."
    )
if _ALLOW_INSECURE_DEV_MODE:
    log.warning(
        "BILLING_DEV_MODE is enabled — internal key auth and JWT validation are "
        "bypassed. This MUST NOT be used in production."
    )

# CRITICAL: These secrets MUST be set in production
# Set BILLING_DEV_MODE=true to allow local development without secrets
INTERNAL_API_KEY = os.environ.get("BILLING_INTERNAL_KEY") or os.environ.get("BILLING_API_KEY")
if not INTERNAL_API_KEY:
    if _ALLOW_INSECURE_DEV_MODE:
        INTERNAL_API_KEY = "dev-insecure-key"
        log.warning("BILLING_DEV_MODE enabled: using insecure default INTERNAL_API_KEY")
    else:
        raise RuntimeError(
            "BILLING_INTERNAL_KEY environment variable is required. "
            "Set it to a strong random key (e.g., openssl rand -base64 32). "
            "For local development only, set BILLING_DEV_MODE=true to bypass this check."
        )

LAGO_WEBHOOK_SECRET = os.environ.get("LAGO_WEBHOOK_SECRET")
if not LAGO_WEBHOOK_SECRET:
    if _ALLOW_INSECURE_DEV_MODE:
        LAGO_WEBHOOK_SECRET = "dev-insecure-webhook-secret"
        log.warning("BILLING_DEV_MODE enabled: using insecure default LAGO_WEBHOOK_SECRET")
    else:
        raise RuntimeError(
            "LAGO_WEBHOOK_SECRET environment variable is required for webhook signature verification. "
            "Get this from your Lago account settings. "
            "For local development only, set BILLING_DEV_MODE=true to bypass this check."
        )

_JWT_SECRET = os.environ.get("JWT_SECRET")
if not _JWT_SECRET:
    if _ALLOW_INSECURE_DEV_MODE:
        _JWT_SECRET = "dev-insecure-jwt-secret"
        log.warning("BILLING_DEV_MODE enabled: JWT validation disabled")
    else:
        raise RuntimeError(
            "JWT_SECRET environment variable is required for user authentication. "
            "This should match the secret used by your auth service. "
            "For local development only, set BILLING_DEV_MODE=true to bypass this check."
        )
_JWT_ALGORITHM = "HS256"

# Rate limiting setup
if _RATE_LIMITING_AVAILABLE:
    limiter = Limiter(key_func=get_remote_address)
    log.info("Rate limiting enabled for billing endpoints: 60 requests/minute per IP")
else:
    limiter = None
    log.warning(
        "slowapi not installed - rate limiting disabled. "
        "Install with: pip install slowapi"
    )

router = APIRouter()
calculator = CostCalculator()


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------

def require_internal_key(x_internal_key: Optional[str] = Header(default=None)):
    if not x_internal_key or x_internal_key != INTERNAL_API_KEY:
        raise HTTPException(status_code=403, detail="Forbidden")


def current_user_id(authorization: str = Header(...)) -> str:
    """
    Decodes the Bearer JWT produced by AuthService._create_jwt_token().
    Token payload: {'user_id': int, 'email': str, 'exp': ..., 'iat': ...}
    Returns user_id as a string so it matches the Redis key schema.

    In BILLING_DEV_MODE, accepts raw user_id strings without JWT validation.
    """
    token = authorization.removeprefix("Bearer ").strip()
    if _ALLOW_INSECURE_DEV_MODE:
        # Dev fallback: accept raw user_id strings when in dev mode
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
async def get_usage(
    request: Request,
    month: Optional[str] = None,
    user_id: str = Depends(current_user_id),
):
    """
    Returns real-time cost breakdown for the current (or requested) month.
    Reads from Redis → <5ms response.  If the Java billing service is enabled,
    the response is enriched with `java_current` (live Lago data) and
    `java_invoices` (invoice list) for richer frontend display.
    """
    svc  = get_cost_service()
    data = svc.get_current_costs(user_id, month)

    # Enrich with Java billing service data (non-blocking — failures are ignored)
    jbc = get_java_billing_client()
    if jbc:
        java_usage = jbc.get_current_usage(user_id)
        if java_usage:
            data["java_current"] = java_usage
        java_invoices = jbc.get_invoices(user_id, page=0, per_page=6)
        if java_invoices:
            data["java_invoices"] = java_invoices

    return data


@router.get("/api/billing/usage/history")
async def get_usage_history(
    request: Request,
    months: int = 3,
    user_id: str = Depends(current_user_id),
):
    """
    Past N months of cost data (from Redis, falls back to Lago).
    Rate limit: 60 requests/minute per IP address.
    """
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
async def get_quota(request: Request, user_id: str = Depends(current_user_id)):
    """
    Returns plan limit, current usage, and overage warning.
    Enriched with Java billing service quota data when available.
    """
    svc   = get_cost_service()
    costs = svc.get_current_costs(user_id)
    result = {
        "user_id":    user_id,
        "quota_usd":  costs.get("quota_usd"),
        "used_usd":   costs.get("total_usd"),
        "quota_pct":  costs.get("quota_pct"),
        "over_quota": (costs.get("quota_pct") or 0) >= 100,
    }

    jbc = get_java_billing_client()
    if jbc:
        java_quota = jbc.get_quota(user_id)
        if java_quota:
            result["java_quota"] = java_quota

    return result


@router.get("/api/billing/invoices")
async def get_invoices(
    request: Request,
    page: int = 0,
    per_page: int = 10,
    user_id: str = Depends(current_user_id),
):
    """Returns invoices from the Java billing service (backed by Lago)."""
    jbc = get_java_billing_client()
    if not jbc:
        return {"user_id": user_id, "invoices": [], "message": "billing service not configured"}
    data = jbc.get_invoices(user_id, page=page, per_page=per_page)
    return {"user_id": user_id, "invoices": data or []}


@router.get("/api/billing/jobs/running")
async def get_running_jobs(request: Request, user_id: str = Depends(current_user_id)):
    """
    Returns in-flight AWS Batch jobs with live cost estimates.
    Rate limit: 60 requests/minute per IP address.
    """
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

    # Emit to Java billing service (dual-write — fire-and-forget)
    jbc = get_java_billing_client()
    if jbc and payload.instance_type:
        # region is not in the payload yet — use env default until Lambda is updated
        region = os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        jbc.emit_ec2(
            user_id=payload.user_id,
            instance_type=payload.instance_type,
            region=region,
            duration_seconds=payload.duration_seconds,
            transaction_id=f"ec2-{payload.job_id}",
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

    # Emit to Java billing service as EBS-equivalent storage (dual-write — fire-and-forget)
    jbc = get_java_billing_client()
    if jbc:
        size_gb = payload.size_bytes / (1024 ** 3)
        jbc.emit_ebs(
            user_id=payload.user_id,
            volume_type="gp3",
            size_gb=max(size_gb, 1.0),  # Java service requires >= 1 GB
            duration_seconds=30 * 24 * 3600,  # 30-day retention projection
            transaction_id=f"s3-{uuid.uuid4().hex[:12]}",
        )
    return {"ok": True, "total_cost_usd": cost.total_cost}


# ---------------------------------------------------------------------------
# Internal API: LLM cost recording
# ---------------------------------------------------------------------------

class LLMCostPayload(BaseModel):
    user_id: str
    session_id: str
    model: str
    input_tokens: int
    output_tokens: int
    duration_ms: float = 0.0


@router.post("/internal/billing/llm_cost", dependencies=[Depends(require_internal_key)])
def internal_llm_cost(payload: LLMCostPayload):
    """Record LLM API call cost from any service (AI assistant, etc.)."""
    cost = calculator.llm_call_cost(
        user_id=payload.user_id,
        session_id=payload.session_id,
        model=payload.model,
        input_tokens=payload.input_tokens,
        output_tokens=payload.output_tokens,
    )
    svc = get_cost_service()
    svc.record_llm_cost(
        user_id=payload.user_id,
        input_usd=cost.input_cost,
        output_usd=cost.output_cost,
        input_tokens=cost.input_tokens,
        output_tokens=cost.output_tokens,
    )

    # Emit to Lago for usage-based billing
    lago = get_lago_client()
    lago.emit_llm(
        user_id=payload.user_id,
        session_id=payload.session_id,
        input_tokens=payload.input_tokens,
        output_tokens=payload.output_tokens,
        model=payload.model,
    )

    # Emit to Java billing service (dual-write — fire-and-forget)
    jbc = get_java_billing_client()
    if jbc:
        jbc.emit_llm(
            user_id=payload.user_id,
            model=payload.model,
            input_tokens=payload.input_tokens,
            output_tokens=payload.output_tokens,
            transaction_id=f"llm-{payload.session_id}-{uuid.uuid4().hex[:8]}",
        )

    log.info(
        "llm_cost user=%s model=%s in=%d out=%d cost=$%.8f",
        payload.user_id, payload.model,
        payload.input_tokens, payload.output_tokens, cost.total_cost,
    )
    return {"ok": True, "total_cost_usd": cost.total_cost}


# ---------------------------------------------------------------------------
# Internal API: Quota management
# ---------------------------------------------------------------------------

class SetQuotaPayload(BaseModel):
    user_id: str
    quota_usd: float
    month: Optional[str] = None   # defaults to current month if omitted


@router.post("/internal/billing/set_quota", dependencies=[Depends(require_internal_key)])
def internal_set_quota(payload: SetQuotaPayload):
    """Directly set the monthly quota cap for a user (admin/test use)."""
    if payload.quota_usd < 0:
        raise HTTPException(status_code=400, detail="quota_usd must be >= 0")
    svc = get_cost_service()
    svc.set_quota(user_id=payload.user_id, quota_usd=payload.quota_usd, month=payload.month)
    log.info("set_quota user=%s quota=$%.2f", payload.user_id, payload.quota_usd)
    return {"ok": True, "user_id": payload.user_id, "quota_usd": payload.quota_usd}


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

    # 4. Register in Java billing service (dual-write — fire-and-forget)
    jbc = get_java_billing_client()
    if jbc:
        jbc.register_customer(payload.user_id, payload.name, payload.email)

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

    # Redis connectivity and connection pool health
    try:
        r.ping()
        redis_status = "ok"

        # Connection pool monitoring (redis-py stores these as sets or ints depending on version)
        pool = r.connection_pool
        def _pool_count(attr):
            val = getattr(pool, attr, None)
            if val is None:
                return None
            return val if isinstance(val, int) else len(val)

        pool_stats = {
            "max_connections":    pool.max_connections,
            "created_connections":  _pool_count('_created_connections'),
            "available_connections": _pool_count('_available_connections'),
            "in_use_connections":   _pool_count('_in_use_connections'),
        }

        # Calculate pool utilization
        if pool_stats["in_use_connections"] is not None and pool_stats["max_connections"]:
            utilization_pct = (pool_stats["in_use_connections"] / pool_stats["max_connections"]) * 100
            pool_stats["utilization_percent"] = round(utilization_pct, 1)

            # Warn if pool utilization is high
            if utilization_pct > 80:
                log.warning(
                    "Redis connection pool utilization high: %.1f%% (%d/%d connections)",
                    utilization_pct,
                    pool_stats["in_use_connections"],
                    pool_stats["max_connections"]
                )
        else:
            pool_stats["utilization_percent"] = None

    except Exception as exc:
        redis_status = f"error: {exc}"
        pool_stats = None

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
    if pool_stats is not None:
        result["redis_connection_pool"] = pool_stats
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


@router.get("/internal/billing/admin/cohort_cost", dependencies=[Depends(require_internal_key)])
def admin_cohort_cost(months: int = 1):
    """
    Cohort cost dashboard: cost per active user per month.

    Returns aggregated spend across all users, broken down by month,
    with p50/p75/p90/p99 spend distribution across individual users.

    Query params:
      months  — number of past months to include (1–12, default 1)

    An "active" user is any user with spend > 0 in that month.
    Safe to call when Redis is empty — returns zeros without raising.
    """
    months = max(1, min(months, 12))
    svc = get_cost_service()
    try:
        report = svc.get_cohort_cost_report(months=months)
        return report
    except Exception as e:
        log.error("Cohort cost report failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/billing/usage/cohort")
async def get_cohort_position(
    request: Request,
    user_id: str = Depends(current_user_id),
):
    """
    Returns the requesting user's cost position relative to the cohort.

    Privacy-preserving: only aggregate statistics are returned; no other
    individual user's data is disclosed.

    Response fields:
      your_spend_usd          — caller's committed spend this month
      cohort_avg_usd          — mean spend across active users this month
      cohort_p75_usd          — 75th-percentile spend
      cohort_p90_usd          — 90th-percentile spend
      your_tier               — "low" | "medium" | "high" | "very_high"
      active_users_this_month — number of users with any spend this month
    """
    svc = get_cost_service()
    try:
        report     = svc.get_cohort_cost_report(months=1)
        user_costs = svc.get_current_costs(user_id)
        user_total = user_costs.get("total_usd", 0.0)

        avg = report["cost_per_active_user_usd"]
        p75 = report["percentiles"]["p75_usd"]
        p90 = report["percentiles"]["p90_usd"]

        if user_total <= avg:
            tier = "low"
        elif user_total <= p75:
            tier = "medium"
        elif user_total <= p90:
            tier = "high"
        else:
            tier = "very_high"

        return {
            "your_spend_usd":          round(user_total, 4),
            "cohort_avg_usd":          avg,
            "cohort_p75_usd":          p75,
            "cohort_p90_usd":          p90,
            "your_tier":               tier,
            "active_users_this_month": report["total_active_users"],
        }
    except Exception as e:
        log.error("Cohort position failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Lago Webhook
# ---------------------------------------------------------------------------

def _verify_lago_signature(body: bytes, signature: str, timestamp: Optional[str] = None) -> bool:
    """
    Verify Lago webhook signature and timestamp.

    Security measures:
    1. HMAC signature verification (prevents tampering)
    2. Timestamp validation (prevents replay attacks)

    Args:
        body: Raw webhook payload
        signature: X-Lago-Signature header value
        timestamp: Webhook timestamp (Unix epoch or ISO format)

    Returns:
        True if signature valid and timestamp recent (< 5 minutes old)
    """
    if not LAGO_WEBHOOK_SECRET:
        return True  # skip verification in dev mode

    # Verify HMAC signature
    expected = hmac.new(
        LAGO_WEBHOOK_SECRET.encode(), body, hashlib.sha256
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        return False

    # Verify timestamp (prevent replay attacks)
    if timestamp:
        try:
            # Parse timestamp (try Unix epoch first, then ISO format)
            try:
                event_time = float(timestamp)
            except ValueError:
                # Try parsing as ISO 8601 datetime
                from datetime import datetime
                dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                event_time = dt.timestamp()

            # Reject events older than 5 minutes
            age_seconds = abs(time.time() - event_time)
            if age_seconds > 300:  # 5 minutes
                log.warning(
                    "Lago webhook rejected: timestamp too old (%.1f seconds ago)",
                    age_seconds
                )
                return False
        except (ValueError, TypeError) as exc:
            log.warning("Lago webhook: invalid timestamp format: %s (%s)", timestamp, exc)
            # Don't fail on timestamp parsing errors (graceful degradation)
            # Signature is already validated, so accept the webhook

    return True


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
    timestamp = request.headers.get("X-Lago-Timestamp", "")

    if not _verify_lago_signature(body, signature, timestamp):
        raise HTTPException(status_code=401, detail="Invalid signature or timestamp")

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
