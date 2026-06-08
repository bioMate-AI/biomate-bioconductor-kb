"""Thin LLM adapter usable as the `llm=` callable for compose_chain().

Wraps the existing `galaxy.ai.llm_client.LLMClient` so the composer doesn't
have to know about AIConfig / billing / fallback chains. Returns `None` from
`default_llm()` when no API key is configured — the caller treats that as
"use the deterministic stub", keeping the prototype runnable in CI without
credentials.

All imports are lazy. Importing this module is free; instantiation only
happens when `default_llm()` is actually called.
"""

from __future__ import annotations

import logging
import os
from typing import Callable, Optional

log = logging.getLogger(__name__)


def _has_any_api_key() -> bool:
    """Heuristic: do we have at least one provider key configured?"""
    return any(
        os.environ.get(k)
        for k in (
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "GOOGLE_API_KEY",
            "GEMINI_API_KEY",
            "DEEPSEEK_API_KEY",
            "ZHIPU_API_KEY",
        )
    )


def default_llm(
    *,
    provider: Optional[str] = None,
    model: Optional[str] = None,
    max_tokens: int = 2048,
) -> Optional[Callable[[str], str]]:
    """Return a callable `(prompt) -> str` backed by `LLMClient.generate`.

    Returns None if no provider is configured (caller uses stub).

    Args:
        provider: override the configured provider (anthropic/openai/gemini/...).
        model: override the configured model name.
        max_tokens: response cap passed through to generate().
    """
    if not _has_any_api_key() and provider not in ("ollama", "local"):
        log.info("chain_composer.llm_adapter: no API key configured — composer will use stub")
        return None

    try:
        from galaxy.ai.config import AIConfig  # type: ignore
        from galaxy.ai.llm_client import LLMClient  # type: ignore
    except Exception as exc:
        log.warning("chain_composer.llm_adapter: import failed (%s) — falling back to stub", exc)
        return None

    cfg_overrides = {}
    if provider:
        cfg_overrides["llm_provider"] = provider
    if model:
        cfg_overrides["llm_model"] = model

    try:
        cfg = AIConfig(cfg_overrides) if cfg_overrides else AIConfig()
        client = LLMClient(cfg)
    except Exception as exc:
        log.warning("chain_composer.llm_adapter: client init failed (%s) — using stub", exc)
        return None

    def _call(prompt: str) -> str:
        # Composer prompts are deliberately short (under 4K tokens). Use a
        # conservative temperature for chain composition — we want stable
        # plans across re-runs of the same query.
        return client.generate(prompt, max_tokens=max_tokens, temperature=0.2)

    return _call
