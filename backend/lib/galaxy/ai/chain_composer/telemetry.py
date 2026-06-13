"""Shadow telemetry for the chain composer.

Calls ``compose_chain`` on real routing turns, logs the structured result, and
never affects user-facing behaviour. Default off; enable via
``BIOMATE_COMPOSER_SHADOW=1``.

Design constraints:
- Never raises. Every exception is swallowed and logged at WARNING.
- Never blocks. A failed sample is silently dropped.
- Default off. Flag must be set explicitly to activate.
- Rate-limited. ``BIOMATE_COMPOSER_SHADOW_PCT`` (0-100, default 100) gates
  sampling; ``BIOMATE_COMPOSER_SHADOW_MAX_PER_SESSION`` caps per-session calls.
- Log-only. The caller does not see the result.

Log format: JSONL at ``BIOMATE_COMPOSER_SHADOW_LOG`` (default
``/tmp/biomate_composer_shadow.jsonl``). One record per routing turn.
"""

from __future__ import annotations

import json
import logging
import os
import random
import time
from collections import defaultdict
from threading import Lock
from typing import Any, Dict, Optional

log = logging.getLogger(__name__)

_SESSION_COUNTS: "defaultdict[str, int]" = defaultdict(int)
_SESSION_LOCK = Lock()


def _env_flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "")
    return raw.strip().lower() in {"1", "true", "yes", "on"} if raw else default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        return default


def is_enabled() -> bool:
    return _env_flag("BIOMATE_COMPOSER_SHADOW", default=False)


def _should_sample(session_id: str) -> bool:
    pct = max(0, min(100, _env_int("BIOMATE_COMPOSER_SHADOW_PCT", 100)))
    if pct == 0:
        return False
    if pct < 100 and random.randint(1, 100) > pct:
        return False
    cap = _env_int("BIOMATE_COMPOSER_SHADOW_MAX_PER_SESSION", 50)
    if cap <= 0:
        return True
    key = session_id or "_anon"
    with _SESSION_LOCK:
        if _SESSION_COUNTS[key] >= cap:
            return False
        _SESSION_COUNTS[key] += 1
    return True


def _log_path() -> str:
    return os.environ.get(
        "BIOMATE_COMPOSER_SHADOW_LOG",
        "/tmp/biomate_composer_shadow.jsonl",
    )


def _summarise_chain(chain: Any) -> Dict[str, Any]:
    """Reduce a ComposedChain to telemetry-safe fields. Best-effort, never raises."""
    out: Dict[str, Any] = {}
    try:
        out["source"] = getattr(chain, "source", None)
        # ComposedChain uses `surfacing_mode`; accept `mode` for test fixtures.
        out["mode"] = getattr(chain, "surfacing_mode", None) or getattr(chain, "mode", None)
        conf = getattr(chain, "confidence", None)
        out["confidence"] = float(conf) if conf is not None else None
        signals = getattr(chain, "confidence_signals", None) or getattr(chain, "signals", None)
        if isinstance(signals, dict):
            out["signals"] = {k: float(v) if isinstance(v, (int, float)) else v
                              for k, v in signals.items()}
        steps = getattr(chain, "steps", None) or []
        out["steps"] = [
            {
                "order": getattr(s, "order", None),
                "workflow_name": getattr(s, "workflow_name", None) or getattr(s, "name", None),
                "role": getattr(s, "role", None),
            }
            for s in steps
        ]
        out["step_count"] = len(out["steps"])
        verifier = getattr(chain, "verifier_report", None) or getattr(chain, "verifier", None)
        if verifier is not None:
            out["verifier_ok"] = bool(getattr(verifier, "ok", None) if not isinstance(verifier, dict)
                                       else verifier.get("ok"))
        # ComposedChain stores `patterns_used: List[str]`; older test fixtures use `pattern`.
        patterns_used = getattr(chain, "patterns_used", None)
        if patterns_used:
            out["patterns"] = list(patterns_used)
        else:
            pattern = getattr(chain, "pattern", None)
            if pattern is not None:
                out["patterns"] = [getattr(pattern, "name", None) if not isinstance(pattern, str) else pattern]
    except Exception as exc:  # pragma: no cover — defensive
        out["_summarise_error"] = repr(exc)
    return out


def shadow_log(query: str, context: Optional[Dict[str, Any]] = None) -> None:
    """Run the composer in shadow mode and log the result. Never raises."""
    if not is_enabled():
        return
    ctx = context or {}
    session_id = str(ctx.get("sessionId") or ctx.get("session_id") or "")
    user_id = str(ctx.get("userId") or ctx.get("user_id") or "")
    if not _should_sample(session_id):
        return

    started = time.monotonic()
    record: Dict[str, Any] = {
        "ts": time.time(),
        "user_id": user_id,
        "session_id": session_id,
        "query": (query or "")[:1000],
    }
    try:
        from .composer import compose_chain  # local import: composer pulls LLM client
        chain = compose_chain(query)
        record["composer"] = _summarise_chain(chain)
    except Exception as exc:
        record["error"] = repr(exc)[:500]
    record["latency_ms"] = int((time.monotonic() - started) * 1000)

    try:
        path = _log_path()
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, default=str) + "\n")
    except Exception as exc:  # pragma: no cover — disk full / perms
        log.warning("composer shadow log write failed: %r", exc)


def reset_session_counts() -> None:
    """Test hook — clear per-session caps."""
    with _SESSION_LOCK:
        _SESSION_COUNTS.clear()
