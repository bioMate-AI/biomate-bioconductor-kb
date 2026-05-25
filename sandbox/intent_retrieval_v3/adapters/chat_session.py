"""
Chat session resume decision adapter — Opportunity 2 from session-review.

Use case: when the BioMate frontend remounts (page reload, SSE stream
failure, app restart), there's a stored "last session" blob with
invocationId, terminal state, and age. The frontend currently always
restores it via localStorage, which is wrong when the user just wants
to start fresh.

This adapter returns a DECISION (not a ranked list), demonstrating the
framework primitives work for binary classification too:

  should_resume_chat_session(query, last_session_meta) -> {
      decision: "resume" | "new" | "uncertain",
      reason: str,
      confidence: float,
  }

Decision logic:
  1. NEW intents always win (user explicitly asked for fresh)
  2. RESUME intents fire if no NEW intent active
  3. If neither fires and last_session is recent + terminal, default to resume
  4. Otherwise uncertain (let UX prompt the user)

This is different in SHAPE from workflow/memory adapters (which rerank
candidates) and from entity adapter (which extracts entities). It returns
a single decision. Demonstrates the YAML loader + intent matcher core
primitives work for any classification problem.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Optional

from sandbox.intent_retrieval_v3.core.yaml_loader import load_intent_map
from sandbox.intent_retrieval_v3.core.intent_matcher import match_intents

_DEFAULT_YAML = (
    Path(__file__).resolve().parents[1] / "data" / "chat_session_intents.yaml"
)

# Intent IDs that signal "user wants a NEW session" (override resume)
_NEW_INTENT_IDS = {"new_project", "topic_pivot"}
# Intent IDs that signal "user wants to resume"
_RESUME_INTENT_IDS = {"continue_previous", "reference_prior_artifact"}


def should_resume_chat_session(query: str,
                                  last_session_meta: Optional[Dict[str, Any]] = None,
                                  *,
                                  yaml_path: Optional[str] = None,
                                  recent_minutes: int = 30,
                                  ) -> Dict[str, Any]:
    """Decide whether to restore the previous session.

    Args:
      query: user's first message of the new browser load.
      last_session_meta: dict with keys {id, age_minutes, status}.
        - status: 'running' | 'completed' | 'failed' | None
        - age_minutes: int — minutes since last activity
        None or empty dict → no previous session candidate.
      recent_minutes: threshold for "recent enough to auto-resume" default.

    Returns dict with:
      decision: "resume" | "new" | "uncertain"
      reason: short human-readable rationale
      confidence: float ∈ [0, 1]
      session_id: str | None (passed through from last_session_meta)
    """
    session_id = (last_session_meta or {}).get("id") if last_session_meta else None
    meta = last_session_meta or {}

    intents = load_intent_map(str(yaml_path or _DEFAULT_YAML))
    if not intents:
        # Library degrades to "uncertain" if YAML unavailable
        return {"decision": "uncertain", "reason": "no intent YAML loaded",
                "confidence": 0.0, "session_id": session_id}

    if not query:
        # No query to read intent from — fall back to metadata-only decision
        if meta.get("status") in ("completed", "failed") and \
           meta.get("age_minutes", 999) <= recent_minutes:
            return {"decision": "resume", "reason": "metadata-only: recent terminal session",
                    "confidence": 0.6, "session_id": session_id}
        return {"decision": "uncertain", "reason": "no query, no recent terminal session",
                "confidence": 0.0, "session_id": session_id}

    matches = match_intents(query, intents)
    fired_ids = {m[0]["intent_id"] for m in matches}
    new_fired = bool(fired_ids & _NEW_INTENT_IDS)
    resume_fired = bool(fired_ids & _RESUME_INTENT_IDS)

    # Rule 1: NEW intent always wins
    if new_fired:
        return {"decision": "new",
                "reason": f"new-intent fired: {fired_ids & _NEW_INTENT_IDS}",
                "confidence": 0.9, "session_id": None}

    # Rule 2: RESUME intent fires (and no NEW intent)
    if resume_fired:
        # Only honor resume if there IS a session to resume to
        if session_id:
            return {"decision": "resume",
                    "reason": f"resume-intent fired: {fired_ids & _RESUME_INTENT_IDS}",
                    "confidence": 0.85, "session_id": session_id}
        else:
            return {"decision": "uncertain",
                    "reason": "resume-intent fired but no last_session available",
                    "confidence": 0.3, "session_id": None}

    # Rule 3: Default to resume when last session is recent + terminal
    if session_id and meta.get("status") in ("completed", "failed") and \
       meta.get("age_minutes", 999) <= recent_minutes:
        return {"decision": "resume",
                "reason": f"recent terminal session (status={meta.get('status')}, "
                          f"age={meta.get('age_minutes')}min)",
                "confidence": 0.5, "session_id": session_id}

    # Rule 4: Uncertain — let UX prompt the user
    return {"decision": "uncertain",
            "reason": "no intent fired and no recent terminal session",
            "confidence": 0.0, "session_id": session_id}
