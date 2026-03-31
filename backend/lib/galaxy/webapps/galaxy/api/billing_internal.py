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
        _cost_log().record(
            user_id=user_id,
            session_id=session_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            duration_ms=duration_ms,
        )
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
