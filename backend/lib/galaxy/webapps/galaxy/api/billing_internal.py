"""
billing_internal.py — Internal billing endpoints called by the BioMate frontend server.

These routes are NOT the /api/billing/* public endpoints.
They are called directly from the frontend Node.js server (not the browser) via
the Galaxy backend URL, authenticated by X-Internal-Key header.

Registered by Galaxy's include_all_package_routers scanner (module must have
a `router` attribute at top level).

Routes:
  POST /internal/billing/llm_cost   — record LLM cost from frontend chat handler
"""

import json
import logging
import os
from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request

log = logging.getLogger(__name__)

# No prefix — routes are at /internal/* directly
router = APIRouter(tags=["billing-internal"])


def _cost_log():
    """Lazy import to avoid triggering galaxy.ai package init at module load time."""
    import importlib
    return importlib.import_module("galaxy.ai.cost_log")


def _cost_service():
    """Lazy import of Redis-backed realtime cost service. Returns None on import failure."""
    try:
        import importlib
        billing_svc = importlib.import_module("galaxy.ai.billing.core.realtime_cost_service")
        return billing_svc.get_cost_service()
    except Exception as exc:
        log.debug("[BillingInternal] realtime_cost_service unavailable: %s", exc)
        return None


def _cost_calculator():
    """Lazy import of cost calculator. Returns None on import failure."""
    try:
        import importlib
        calc_mod = importlib.import_module("galaxy.ai.billing.core.cost_calculator")
        return calc_mod.CostCalculator()
    except Exception as exc:
        log.debug("[BillingInternal] cost_calculator unavailable: %s", exc)
        return None


def _lago_client():
    """Lazy import of Lago client. Returns None on import failure."""
    try:
        import importlib
        lago_mod = importlib.import_module("galaxy.ai.billing.core.lago_client")
        return lago_mod.get_lago_client()
    except Exception as exc:
        log.debug("[BillingInternal] lago_client unavailable: %s", exc)
        return None


def _get_user_plan_code(user_id: str) -> str:
    """Lazy import of user plan resolver."""
    try:
        import importlib
        qe = importlib.import_module("galaxy.ai.billing.core.quota_enforcer")
        return qe.get_user_plan_code(user_id)
    except Exception:
        return "base"


@router.post("/internal/billing/llm_cost", include_in_schema=False)
async def record_llm_cost(request: Request) -> Dict[str, Any]:
    """
    Record one LLM call's cost.
    Called by the frontend server after each /api/chat response.
    Validates X-Internal-Key, writes to file-based cost log, and forwards to Lago.
    """
    expected_key = os.environ.get("BILLING_INTERNAL_KEY", "")
    provided_key = request.headers.get("X-Internal-Key", "")
    if expected_key and provided_key != expected_key:
        raise HTTPException(status_code=401, detail="Invalid internal billing key")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    user_id = body.get("user_id") or "anonymous"
    session_id = body.get("session_id") or ""
    model = body.get("model") or "claude-sonnet-4-6"
    input_tokens = int(body.get("input_tokens") or 0)
    output_tokens = int(body.get("output_tokens") or 0)
    duration_ms = float(body.get("duration_ms") or 0.0)

    # 1. File-based durable audit log (append-only JSONL; never raises).
    #    This is the primary durable sink — it has no external dependencies.
    file_log_ok = False
    try:
        file_log_ok = bool(_cost_log().record(
            user_id=user_id,
            session_id=session_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            duration_ms=duration_ms,
        ))
    except Exception as exc:
        # Only reached if the cost_log module itself fails to import/resolve.
        log.error("[BillingInternal] durable file cost-log write failed: %s", exc)

    # 2. Redis-backed realtime cost service (powers /api/billing/usage dashboard
    #    and quota enforcement). record_llm_cost returns a durability status:
    #    "redis" (written), "deadletter" (Redis failed → durably queued), or
    #    "lost" (Redis AND dead-letter both failed).
    realtime_durability = "unavailable"  # svc could not be constructed at all
    svc = _cost_service()
    if svc is not None:
        try:
            calc = _cost_calculator()
            if calc is not None:
                cost = calc.llm_call_cost(
                    user_id=user_id,
                    session_id=session_id,
                    model=model,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                )
                realtime_durability = svc.record_llm_cost(
                    user_id=user_id,
                    input_usd=cost.input_cost,
                    output_usd=cost.output_cost,
                    input_tokens=cost.input_tokens,
                    output_tokens=cost.output_tokens,
                ) or "redis"
            else:
                # Fallback: estimate cost inline using same price table as cost_log
                from galaxy.ai.cost_log import compute_cost
                total = compute_cost(model, input_tokens, output_tokens)
                input_usd = round(total * (input_tokens / max(input_tokens + output_tokens, 1)), 8)
                output_usd = round(total - input_usd, 8)
                realtime_durability = svc.record_llm_cost(
                    user_id=user_id,
                    input_usd=input_usd,
                    output_usd=output_usd,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                ) or "redis"
        except Exception as compute_exc:
            # Cost computation (not the Redis write — that is handled inside
            # record_llm_cost and dead-lettered) failed. The file audit log
            # above is the durable backstop for this record.
            log.error("[BillingInternal] realtime cost compute failed: %s", compute_exc)
            realtime_durability = "error"

    # 3. Lago emission for usage-based billing (fire-and-forget; intentional
    #    no-op when Lago is disabled by default under flat-tier billing).
    try:
        lago = _lago_client()
        if lago is not None:
            plan_code = _get_user_plan_code(user_id)
            lago.emit_llm(
                user_id=user_id,
                session_id=session_id,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                model=model,
                plan_code=plan_code,
            )
    except Exception as lago_exc:
        log.warning("[BillingInternal] Lago emit skipped (non-fatal): %s", lago_exc)

    # 4. Durability decision. The event is durably recorded if EITHER the file
    #    audit log succeeded OR the realtime ledger landed in Redis / the
    #    dead-letter. Only when the event is nowhere durable do we return 5xx —
    #    we must never return HTTP 200 claiming success on a lost money event.
    durable = file_log_ok or realtime_durability in ("redis", "deadletter")
    if not durable:
        log.error(
            "[BillingInternal] LLM cost NOT durably recorded (file_log_ok=%s "
            "realtime=%s) user=%s model=%s in=%d out=%d",
            file_log_ok, realtime_durability, user_id, model, input_tokens, output_tokens,
        )
        raise HTTPException(
            status_code=503,
            detail={
                "status": "error",
                "message": "LLM cost event could not be durably recorded (Redis, "
                           "dead-letter, and file audit log all failed)",
                "file_log_ok": file_log_ok,
                "realtime_durability": realtime_durability,
            },
        )

    log.info(
        "[BillingInternal] Recorded LLM cost: user=%s model=%s in=%d out=%d "
        "(file_log=%s realtime=%s)",
        user_id, model, input_tokens, output_tokens, file_log_ok, realtime_durability,
    )
    resp: Dict[str, Any] = {
        "status": "recorded",
        "user_id": user_id,
        "session_id": session_id,
        "model": model,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "file_log_ok": file_log_ok,
        "realtime_durability": realtime_durability,
    }
    if realtime_durability == "deadletter":
        # Primary Redis write failed but the event is durably queued.
        resp["queued"] = True
        resp["durability"] = "deadletter"
    return resp
