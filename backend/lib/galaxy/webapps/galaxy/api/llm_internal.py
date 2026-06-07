"""
llm_internal.py — Internal LLM endpoint called by the BioMate frontend.

Routes all frontend LLM calls through the YAML-defined fallback chain in
`backend/config/llm_providers.yml` (primary: gemini-3.1-pro-preview;
fallbacks: gemini-3.5-flash-preview → claude-sonnet-4-5 → gpt-4o →
qwen3:32b) via the existing `LLMClient` + `FallbackChainManager`.

Authentication mirrors billing_internal.py (X-Internal-Key shared with
BILLING_INTERNAL_KEY). The endpoint is NOT exposed in /api/* — it lives
at /internal/llm/generate, callable only by the Node frontend server.

Why this exists:
  9 frontend call sites in `frontend/server/` were instantiating the
  Anthropic SDK directly with hardcoded `claude-sonnet-4-5` or
  `claude-sonnet-4-6`, completely bypassing the YAML fallback chain
  and violating the "use Gemini primary, others as backup" policy.
  This endpoint is the single chokepoint that re-routes them through
  the canonical chain. See
  docs/20260607_LLM_ROUTING_CONSOLIDATION_PLAN.md.

Registered by Galaxy's include_all_package_routers scanner — module
must have a `router` attribute at top level.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request

log = logging.getLogger(__name__)

router = APIRouter(tags=["llm-internal"])


def _llm_client():
    """Lazy import to avoid triggering galaxy.ai package init at module load."""
    import importlib
    llm_mod = importlib.import_module("galaxy.ai.llm_client")
    config_mod = importlib.import_module("galaxy.ai.config")
    return llm_mod.LLMClient(config_mod.AIConfig())


@router.post("/internal/llm/generate", include_in_schema=False)
async def generate(request: Request) -> Dict[str, Any]:
    """Generate text via the YAML-defined fallback chain.

    Auth: X-Internal-Key header must match BILLING_INTERNAL_KEY (same key
    as billing internal endpoints to avoid juggling multiple secrets).

    Request:
      {
        "prompt": str,           # required; the user content
        "system": str,           # optional system prompt
        "max_tokens": int,       # optional, default 4096
        "temperature": float,    # optional, default 0.7
        "json_mode": bool        # optional; only honored if provider supports it
      }

    Response:
      {
        "text": str,
        "model_used": str,       # which provider+model actually answered
        "fallback_depth": int    # 0 = primary, 1 = first fallback, ...
      }
    """
    expected_key = os.environ.get("BILLING_INTERNAL_KEY", "")
    provided_key = request.headers.get("X-Internal-Key", "")
    if expected_key and provided_key != expected_key:
        raise HTTPException(status_code=401, detail="Invalid internal key")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    prompt: Optional[str] = body.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise HTTPException(
            status_code=400, detail="`prompt` (non-empty string) is required"
        )

    # Forward kwargs that LLMClient.generate accepts. Default max_tokens
    # is high enough to avoid truncation for the typical methods-report
    # / findings-analysis workloads (verified: ~3K tokens output for
    # verbose pharma prompts).
    kwargs: Dict[str, Any] = {
        "max_tokens": int(body.get("max_tokens") or 4096),
        "temperature": float(body.get("temperature", 0.7)),
    }
    system: Optional[str] = body.get("system")
    if system:
        kwargs["system"] = system
    if body.get("json_mode"):
        kwargs["json_mode"] = True

    client = _llm_client()
    try:
        text = client.generate(prompt, **kwargs)
    except Exception as exc:
        log.exception("[LLMInternal] generate failed")
        raise HTTPException(status_code=502, detail=f"LLM generation failed: {exc}")

    # Best-effort: expose which provider answered for observability.
    # LLMClient tracks this on the fallback_manager when available.
    model_used = "unknown"
    fallback_depth = 0
    try:
        fb = getattr(client, "fallback_manager", None)
        if fb is not None:
            last = getattr(fb, "last_succeeded", None)
            if last is not None:
                model_used = getattr(last, "model", "unknown")
                fallback_depth = int(getattr(last, "depth", 0))
    except Exception:
        pass

    return {
        "text": text,
        "model_used": model_used,
        "fallback_depth": fallback_depth,
    }
