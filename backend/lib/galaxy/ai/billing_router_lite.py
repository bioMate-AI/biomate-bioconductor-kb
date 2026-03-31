"""
billing_router_lite.py — Lightweight billing API for dev/staging deployments.

Reads directly from the file-based cost log (cost_log.py).
No Redis, no Lago, no Java billing service required.

Registered in galaxy.webapps.galaxy.api.ai_assistant alongside the main router.

Endpoints:
  GET /api/billing/quota       — current usage summary + unlimited flag
  GET /api/billing/usage       — per-session cost breakdown
  GET /api/billing/cost_log    — raw JSONL entries for admin inspection
"""

import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter, Query

from galaxy.ai import cost_log as _cost_log

log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/billing", tags=["billing"])


@router.get("/quota")
async def get_quota(user_id: Optional[str] = Query(default=None)) -> Dict[str, Any]:
    """
    Return current usage and quota for a user.
    Initial users have no quota limit — over_quota is always False.
    """
    s = _cost_log.summary(user_id=user_id)
    return {
        "user_id": user_id or "all",
        "over_quota": False,          # No quota enforced for initial users
        "quota_usd": None,            # Unlimited
        "used_usd": s["total_cost_usd"],
        "total_calls": s["total_calls"],
        "total_tokens": s["total_tokens"],
        "input_tokens": s["total_input_tokens"],
        "output_tokens": s["total_output_tokens"],
        "message": "No quota enforced — usage is logged for cost visibility only.",
    }


@router.get("/usage")
async def get_usage(
    user_id: Optional[str] = Query(default=None),
    since: Optional[str] = Query(default=None, description="ISO8601 datetime filter"),
) -> Dict[str, Any]:
    """Return per-session cost breakdown from the file-based cost log."""
    records = _cost_log.query(user_id=user_id, since_ts=since)

    # Aggregate by session
    sessions: Dict[str, Dict[str, Any]] = {}
    for r in records:
        sid = r.get("session_id") or "unknown"
        if sid not in sessions:
            sessions[sid] = {
                "session_id": sid,
                "user_id": r.get("user_id"),
                "first_call": r.get("ts"),
                "last_call": r.get("ts"),
                "calls": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cost_usd": 0.0,
            }
        s = sessions[sid]
        s["calls"] += 1
        s["input_tokens"] += r.get("input_tokens", 0)
        s["output_tokens"] += r.get("output_tokens", 0)
        s["cost_usd"] = round(s["cost_usd"] + r.get("cost_usd", 0.0), 6)
        if r.get("ts", "") > s["last_call"]:
            s["last_call"] = r["ts"]

    return {
        "user_id": user_id or "all",
        "total_cost_usd": round(sum(s["cost_usd"] for s in sessions.values()), 6),
        "sessions": sorted(sessions.values(), key=lambda x: x["last_call"], reverse=True),
    }


@router.get("/cost_log")
async def get_cost_log(
    user_id: Optional[str] = Query(default=None),
    limit: int = Query(default=100, le=1000),
) -> Dict[str, Any]:
    """Return raw cost log entries (most recent first). Admin inspection endpoint."""
    records = _cost_log.query(user_id=user_id)
    records = sorted(records, key=lambda r: r.get("ts", ""), reverse=True)[:limit]
    return {
        "count": len(records),
        "records": records,
    }
