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

    try:
        # 1. File-based durable audit log (always works, no dependencies)
        _cost_log().record(
            user_id=user_id,
            session_id=session_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            duration_ms=duration_ms,
        )

        # 2. Redis-backed realtime cost service (powers /api/billing/usage dashboard)
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
                    svc.record_llm_cost(
                        user_id=user_id,
                        input_usd=cost.input_cost,
                        output_usd=cost.output_cost,
                        input_tokens=cost.input_tokens,
                        output_tokens=cost.output_tokens,
                    )
                else:
                    # Fallback: estimate cost inline using same price table as cost_log
                    from galaxy.ai.cost_log import compute_cost
                    total = compute_cost(model, input_tokens, output_tokens)
                    input_usd = round(total * (input_tokens / max(input_tokens + output_tokens, 1)), 8)
                    output_usd = round(total - input_usd, 8)
                    svc.record_llm_cost(
                        user_id=user_id,
                        input_usd=input_usd,
                        output_usd=output_usd,
                        input_tokens=input_tokens,
                        output_tokens=output_tokens,
                    )
            except Exception as redis_exc:
                log.debug("[BillingInternal] Redis write skipped (non-fatal): %s", redis_exc)

        # 3. Lago emission for usage-based billing (fire-and-forget)
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

        log.info(
            "[BillingInternal] Recorded LLM cost: user=%s model=%s in=%d out=%d",
            user_id, model, input_tokens, output_tokens,
        )
        return {
            "status": "recorded",
            "user_id": user_id,
            "session_id": session_id,
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }
    except Exception as exc:
        log.warning("[BillingInternal] Failed to record cost: %s", exc)
        return {"status": "error", "message": str(exc)}
