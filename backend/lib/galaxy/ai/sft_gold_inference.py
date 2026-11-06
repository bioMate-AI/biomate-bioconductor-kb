"""Task-scoped routing to the on-prem SFT-from-gold 9B adapter (served via vLLM).

This is a *per-task* opt-in that sits NEXT TO the normal cloud fallback chain —
it never replaces it. It exists because BioMate has no per-task LLM router: every
component builds its own ``LLMClient`` and hits the same global fallback chain, and
the only task-agnostic override is the global ``BIOMATE_LOCAL_ONLY`` switch (which
sends *everything* local). To route ONLY the tasks the gold adapter wins
(findings synthesis, task decomposition) we gate at the backend ``/internal/llm/generate``
chokepoint on an explicit ``task`` tag.

Design rules (all enforced here):
  * OFF by default. ``BIOMATE_SFT_GOLD_ENABLED`` must be ``1`` to do anything.
    When unset/0 every entry point is a no-op and callers fall back to the chain.
  * Task allowlist. Only tasks in ``BIOMATE_SFT_GOLD_TASKS`` route here. Param
    prefill and workflow routing are deliberately NOT in the default allowlist
    (param_prefill regressed must_not_fill 34->49; routing is carried by the
    dense retriever and is model-invariant). See
    docs/20260912_onprem_llm/20261006_SFT_GOLD_SERVING.md.
  * Origin pinning. The configured URL's origin must equal the operator-approved
    ``BIOMATE_SFT_GOLD_ORIGIN`` (scheme://host:port). Network isolation (security
    group locked to the dev backend) remains the deployment gate.
  * No silent cloud bleed. A transport/format failure raises; the CALLER decides
    to fall back. This module never itself chains to a cloud provider.

Python 3.9 compatible (runs inside the Galaxy gunicorn): no PEP-604 unions, no match.
"""
from __future__ import annotations

import json
import logging
import os
import re
from typing import List, Optional
from urllib.parse import urlsplit

import httpx

log = logging.getLogger(__name__)

_DEFAULT_TASKS = "findings,decomposition"
_DEFAULT_MODEL = "sft_gold"
_DEFAULT_TIMEOUT_MS = "120000"


def enabled() -> bool:
    """True only when the operator has flipped the master flag on."""
    return os.environ.get("BIOMATE_SFT_GOLD_ENABLED") == "1"


def _allowed_tasks() -> List[str]:
    raw = os.environ.get("BIOMATE_SFT_GOLD_TASKS", _DEFAULT_TASKS)
    return [t.strip() for t in raw.split(",") if t.strip()]


def enabled_for(task: Optional[str]) -> bool:
    """True when the flag is on AND ``task`` is in the allowlist.

    A falsy/None task is never routed here (prevents accidental global capture).
    """
    if not enabled():
        return False
    if not task:
        return False
    return task in _allowed_tasks()


def _config():
    """Resolve and validate the endpoint config, or raise ValueError.

    Mirrors local_inference.local_config: scheme must be http/https, no creds/
    query/fragment in the URL, and the origin must match the approved origin.
    """
    raw = os.environ.get("BIOMATE_SFT_GOLD_URL", "")
    model = os.environ.get("BIOMATE_SFT_GOLD_MODEL", _DEFAULT_MODEL)
    url = urlsplit(raw)
    if (
        not model
        or url.scheme not in ("http", "https")
        or not url.hostname
        or url.username
        or url.password
        or url.query
        or url.fragment
    ):
        raise ValueError("Invalid or missing SFT-gold inference configuration")
    approved = os.environ.get("BIOMATE_SFT_GOLD_ORIGIN")
    if "{0}://{1}".format(url.scheme, url.netloc) != approved:
        raise ValueError("SFT-gold inference origin is not approved")
    timeout = float(os.environ.get("BIOMATE_SFT_GOLD_TIMEOUT_MS", _DEFAULT_TIMEOUT_MS)) / 1000
    if not 0 < timeout <= 600:
        raise ValueError("Invalid SFT-gold inference timeout")
    return raw.rstrip("/"), model, timeout


async def agenerate(
    prompt: str,
    system: Optional[str] = None,
    max_tokens: int = 4096,
    temperature: float = 0.0,
    json_mode: bool = False,
) -> str:
    """Call the sft_gold vLLM OpenAI-compatible endpoint. Returns assistant text.

    Raises on any transport/format error so the caller can fall back cleanly.
    Determinism (temperature 0, thinking disabled) matches the eval shim so served
    behavior tracks the evaluated behavior.
    """
    url, model, timeout = _config()
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    body = {
        "model": model,
        "messages": messages,
        "stream": False,
        "max_tokens": max_tokens,
        "temperature": temperature,
        # Served base is a thinking model; disable thinking for parity with the
        # greedy, no-think eval shim (harness_shim.py enable_thinking=False).
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    headers = {}
    key = os.environ.get("BIOMATE_SFT_GOLD_KEY")
    if key:
        headers["Authorization"] = "Bearer " + key
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False) as client:
        response = await client.post(url + "/chat/completions", json=body, headers=headers)
        response.raise_for_status()
        result = response.json()
    choice = result["choices"][0]
    if choice.get("finish_reason") not in ("stop", "length") or not isinstance(
        choice.get("message", {}).get("content"), str
    ):
        raise ValueError("SFT-gold inference did not produce a complete text answer")
    content = choice["message"]["content"]
    if json_mode:
        text = content.strip()
        fenced = re.fullmatch(r"```(?:json)?\s*\n([\s\S]*?)\n```", text, re.IGNORECASE)
        object_text = (fenced.group(1) if fenced else text).strip()
        value = json.loads(object_text)
        if not isinstance(value, dict):
            raise ValueError("SFT-gold JSON output must be an object")
        content = object_text
    return content
