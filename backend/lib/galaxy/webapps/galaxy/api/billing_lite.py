"""
billing_lite.py — Lightweight billing API auto-registered by Galaxy's router scanner.

Uses lazy imports to avoid triggering galaxy.ai.__init__ at module load time.
Reads from the file-based cost log (cost_log.py) — no Redis/Lago/Java required.
Also proxies Lago customer and event data when LAGO_API_URL / LAGO_API_KEY are set.

Endpoints:
  GET /api/billing/quota       — current usage + unlimited flag for initial users
  GET /api/billing/usage       — per-session cost breakdown
  GET /api/billing/cost_log    — raw JSONL entries for admin inspection
  GET /api/billing/lago/status — Lago connectivity check
  GET /api/billing/lago/events — recent Lago events for a subscription
"""

import json
import logging
import os
import urllib.request
from typing import Any, Dict, Optional

from fastapi import APIRouter, Query

log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/billing", tags=["billing"])


def _lago_request(path: str, method: str = "GET", body: Optional[Dict] = None) -> Any:
    """Make an authenticated request to the Lago API. Returns parsed JSON or raises."""
    lago_url = os.environ.get("LAGO_API_URL", "").rstrip("/")
    lago_key = os.environ.get("LAGO_API_KEY", "")
    if not lago_url or not lago_key:
        raise RuntimeError("LAGO_API_URL or LAGO_API_KEY not configured")
    url = f"{lago_url}{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(
        url, data=data,
        headers={"Authorization": f"Bearer {lago_key}", "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _cost_log():
    """Lazy import to avoid triggering galaxy.ai package init chain."""
    import importlib
    return importlib.import_module("galaxy.ai.cost_log")


@router.get("/quota")
async def get_quota(user_id: Optional[str] = Query(default=None)) -> Dict[str, Any]:
    """
    Return current usage and quota. Initial users have no quota limit —
    over_quota is always False. Usage is logged purely for cost visibility.
    """
    try:
        s = _cost_log().summary(user_id=user_id)
    except Exception as exc:
        log.warning("[billing_lite] cost_log unavailable: %s", exc)
        s = {"total_cost_usd": 0.0, "total_calls": 0, "total_tokens": 0,
             "total_input_tokens": 0, "total_output_tokens": 0}
    return {
        "user_id": user_id or "all",
        "over_quota": False,
        "quota_usd": None,
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
    """
    Return cost breakdown in the format expected by the BioMate billing UI.
    Aggregates the file-based cost log into per-month usage data.
    """
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    month_str = now.strftime("%Y-%m")
    # Filter to current month unless 'since' is specified
    month_since = since or f"{month_str}-01T00:00:00+00:00"

    try:
        records = _cost_log().query(user_id=user_id, since_ts=month_since)
    except Exception as exc:
        log.warning("[billing_lite] cost_log query failed: %s", exc)
        records = []

    # Aggregate LLM totals
    total_input = sum(r.get("input_tokens", 0) for r in records)
    total_output = sum(r.get("output_tokens", 0) for r in records)
    total_cost = round(sum(r.get("cost_usd", 0.0) for r in records), 6)
    call_count = len(records)

    # Rough split: input vs output cost (based on 3:15 pricing ratio for claude-sonnet)
    input_cost = round(total_cost * 0.167, 6)   # input ~ 16.7% at sonnet pricing
    output_cost = round(total_cost * 0.833, 6)  # output ~ 83.3%

    # Per-session breakdown (kept for admin/debug)
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
        "month": month_str,
        "committed_usd": total_cost,
        "running_estimate_usd": 0.0,
        "total_usd": total_cost,
        "quota_usd": None,           # No quota enforced for initial users
        "quota_pct": None,
        "breakdown": {
            "llm": {
                "total_usd": total_cost,
                "input_usd": input_cost,
                "output_usd": output_cost,
                "tokens_in": total_input,
                "tokens_out": total_output,
                "calls": call_count,
            },
            "compute": {
                "total_usd": 0.0,
                "vcpu_usd": 0.0,
                "gpu_usd": 0.0,
                "mem_usd": 0.0,
                "jobs": 0,
                "total_hours": 0.0,
            },
            "storage": {
                "total_usd": 0.0,
                "size_gb": 0.0,
                "put_count": 0,
            },
        },
        "running_jobs": [],
        "currency": "usd",
        # Extended: per-session breakdown for admin use
        "sessions": sorted(sessions.values(), key=lambda x: x["last_call"], reverse=True),
        "total_cost_usd": total_cost,  # backward compat alias
    }


@router.get("/cost_log")
async def get_cost_log(
    user_id: Optional[str] = Query(default=None),
    limit: int = Query(default=100, le=1000),
) -> Dict[str, Any]:
    """Return raw cost log entries, most recent first."""
    try:
        records = _cost_log().query(user_id=user_id)
        records = sorted(records, key=lambda r: r.get("ts", ""), reverse=True)[:limit]
    except Exception as exc:
        log.warning("[billing_lite] cost_log read failed: %s", exc)
        records = []
    return {"count": len(records), "records": records}


@router.get("/lago/status")
async def get_lago_status() -> Dict[str, Any]:
    """Check Lago connectivity and return basic account info."""
    lago_url = os.environ.get("LAGO_API_URL", "")
    if not lago_url:
        return {"connected": False, "reason": "LAGO_API_URL not set"}
    try:
        data = _lago_request("/api/v1/organizations")
        org = (data.get("organizations") or [{}])[0]
        return {
            "connected": True,
            "lago_url": lago_url,
            "organization": org.get("name"),
            "lago_version": org.get("lago_version"),
        }
    except Exception as exc:
        return {"connected": False, "reason": str(exc), "lago_url": lago_url}


@router.get("/lago/events")
async def get_lago_events(
    external_subscription_id: Optional[str] = Query(default=None),
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=20, le=100),
) -> Dict[str, Any]:
    """Return recent Lago events (LLM usage forwarded from cost_log)."""
    try:
        params = f"?page={page}&per_page={per_page}"
        if external_subscription_id:
            params += f"&external_subscription_id={external_subscription_id}"
        data = _lago_request(f"/api/v1/events{params}")
        return {
            "connected": True,
            "events": data.get("events", []),
            "meta": data.get("meta", {}),
        }
    except Exception as exc:
        log.warning("[billing_lite] Lago events query failed: %s", exc)
        return {"connected": False, "reason": str(exc), "events": []}
