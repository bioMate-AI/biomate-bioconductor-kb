"""
Quota Enforcer — Pre-Job Middleware

Call check_and_reserve() BEFORE submitting any AWS Batch job.
It reads from Redis (<10ms) and raises QuotaExceededError if the user
is over their hard limit.

Soft-limit warnings (80%) are handled by RealtimeCostService automatically.

Usage in BioMate workflow submission:
    from lib.galaxy.ai.billing.core.quota_enforcer import check_and_reserve, QuotaExceededError

    try:
        check_and_reserve(user_id, estimated_cost_usd)
    except QuotaExceededError as e:
        return {"error": str(e), "quota_exceeded": True}, 402
"""

import logging
import os

from .realtime_cost_service import get_cost_service
from .cost_calculator import CostCalculator, EC2_INSTANCE_PRICING

log = logging.getLogger(__name__)

calculator = CostCalculator()

# Plan quotas in USD per month.  Override via env vars or from your user DB.
DEFAULT_PLAN_LIMITS: dict[str, float] = {
    "free":       5.00,
    "basic":     50.00,
    "pro":      500.00,
    "enterprise": float("inf"),  # custom limits set per customer in Lago
}


class QuotaExceededError(Exception):
    def __init__(self, user_id: str, used: float, limit: float):
        self.user_id = user_id
        self.used    = used
        self.limit   = limit
        super().__init__(
            f"Monthly quota exceeded for user {user_id}: "
            f"${used:.4f} used / ${limit:.4f} limit"
        )


def ensure_quota_set(user_id: str, plan: str) -> None:
    """
    Called at login / plan-change to set the quota in Redis.
    Should also be called when Lago sends a subscription_updated webhook.
    """
    limit = DEFAULT_PLAN_LIMITS.get(plan, DEFAULT_PLAN_LIMITS["free"])
    get_cost_service().set_quota(user_id, limit)


def check_and_reserve(user_id: str, estimated_cost_usd: float = 0.0) -> None:
    """
    Checks whether the user is within quota.
    Raises QuotaExceededError if not.

    estimated_cost_usd: the expected cost of the job about to be submitted.
    We add this to the current total to check if the job would push the user over.
    """
    svc   = get_cost_service()
    costs = svc.get_current_costs(user_id)
    total = costs["total_usd"] + estimated_cost_usd
    limit = costs.get("quota_usd")

    if limit is None:
        # No quota set → allow (no plan configured yet)
        log.debug("No quota configured for user %s — allowing", user_id)
        return

    if total >= limit:
        raise QuotaExceededError(user_id, total, limit)

    pct = total / limit * 100
    log.debug("Quota check user=%s: $%.4f / $%.4f (%.1f%%)", user_id, total, limit, pct)


def estimate_job_cost(
    instance_type: str,
    vcpus: float,
    memory_mb: int,
    gpu_count: int,
    expected_duration_minutes: float,
    is_spot: bool = False,
) -> float:
    """
    Quick cost estimate for a job before submission.
    Used by check_and_reserve() to decide if the job will push user over quota.
    """
    return calculator.estimate_running_job_cost(
        instance_type=instance_type,
        vcpus=vcpus,
        memory_mb=memory_mb,
        gpu_count=gpu_count,
        started_at_ms=0,
        now_ms=int(expected_duration_minutes * 60 * 1000),
        is_spot=is_spot,
    )
