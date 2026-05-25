"""
Generic intent matcher — same logic as workflow_intent._intent_matches but
parametrized so adapters can pass their own pipeline-verb list, ambiguity
tiebreaker, etc.

Three public functions:

  match_intents(query, intents) -> list[(intent_entry, n_triggers)]
      Returns all intents that fire for this query, sorted by trigger density.

  resolve_single_intent(matches, ambiguity_factor=2) -> intent_entry or None
      Tiebreaker: if one intent has ≥ ambiguity_factor× the triggers of the
      next, treat as confident. Else None (let downstream handle ambiguity).

  has_pipeline_intent(query) -> bool
      Returns True when the query contains pipeline-level verbs.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

# Verbs that signal "user wants a full pipeline/workflow" rather than a single tool.
# Used by intent entries with `pipeline_intent_required: true`. Adapters can
# override by passing their own verbs to has_pipeline_intent().
_DEFAULT_PIPELINE_VERBS = (
    "run ", "from fastq", "end-to-end", "end to end", "full pipeline",
    "pipeline", "workflow", "fastq to", "from raw", "process my",
    "analyze my", "from reads", "complete analysis",
)


def has_pipeline_intent(query: str,
                          verbs: Tuple[str, ...] = _DEFAULT_PIPELINE_VERBS) -> bool:
    q = (query or "").lower()
    return any(v in q for v in verbs)


def intent_matches(query_lc: str, entry: Dict[str, Any]) -> Tuple[bool, int]:
    """Single-intent match check. Returns (fired, n_trigger_hits).

    - If any `disqualified_if_present` term is in the query → does not fire.
    - If `pipeline_intent_required` and no pipeline verb in query → does not fire.
    - Otherwise fires iff at least one trigger_term is in the query.
    """
    for dq in entry.get("disqualified_if_present", []):
        if dq in query_lc:
            return False, 0
    if entry.get("pipeline_intent_required") and not has_pipeline_intent(query_lc):
        return False, 0
    n = sum(1 for t in entry.get("trigger_terms", []) if t in query_lc)
    return (n > 0), n


def match_intents(query: str, intents: List[Dict[str, Any]]
                    ) -> List[Tuple[Dict[str, Any], int]]:
    """Return all firing intents, sorted by trigger density (descending)."""
    if not query or not intents:
        return []
    query_lc = query.lower()
    matched: List[Tuple[Dict[str, Any], int]] = []
    for entry in intents:
        fired, n = intent_matches(query_lc, entry)
        if fired:
            matched.append((entry, n))
    matched.sort(key=lambda x: -x[1])
    return matched


def resolve_single_intent(matches: List[Tuple[Dict[str, Any], int]],
                            ambiguity_factor: float = 2.0,
                            ) -> Optional[Dict[str, Any]]:
    """Decide whether one intent is "confidently" the user's intent.

    Returns the winning intent entry, or None if ambiguous.

    Rules:
      0 matches      → None (no intent fires)
      1 match        → return it
      2+ matches     → return top only if top n_triggers ≥ ambiguity_factor × next
                       AND top n_triggers ≥ 2. Else None.
    """
    if not matches:
        return None
    if len(matches) == 1:
        return matches[0][0]
    top, second = matches[0], matches[1]
    if top[1] >= ambiguity_factor * second[1] and top[1] >= 2:
        return top[0]
    return None
