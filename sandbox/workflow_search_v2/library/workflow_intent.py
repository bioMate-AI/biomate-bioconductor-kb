"""
Workflow-intent priority booster.

Given a free-text query and a ranked list of WorkflowMatch-like candidates
(must have `.name` attribute or `name` key), promote the canonical workflow
to position 1 when the query unambiguously matches a known pipeline intent.

Designed to sit on top of `UnifiedWorkflowSearch.search()` results:

    candidates = unified_search.search(query, limit=10)
    candidates = prioritize_workflow_by_intent(query, candidates)

Pure function. No I/O beyond reading the YAML once (cached). Safe to call
unconditionally — passes through unchanged when no intent matches or when
multiple intents fire ambiguously (existing disambiguation UX handles that).

Decision rules:
  1. Lowercase the query.
  2. For each intent entry, count how many of its `trigger_terms` appear
     in the query. Disqualify the intent if any `disqualified_if_present`
     term is in the query.
  3. If exactly ONE intent fires (has ≥1 trigger match) AND its canonical
     workflow is present anywhere in `candidates`, move that candidate to
     position 0.
  4. If zero or multiple intents fire, pass through unchanged.
"""
from __future__ import annotations

import logging
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

_DEFAULT_YAML = Path(__file__).resolve().parents[1] / "data" / "intent_anchors.yaml"

# Verbs/phrases that hint "user wants a full pipeline" — used when an intent
# entry sets `pipeline_intent_required: true`.
_PIPELINE_VERBS = (
    "run ", "from fastq", "end-to-end", "end to end", "full pipeline",
    "pipeline", "workflow", "fastq to", "from raw", "process my",
    "analyze my", "from reads", "complete analysis",
)


@lru_cache(maxsize=4)
def load_intent_anchors(yaml_path: Optional[str] = None) -> List[Dict[str, Any]]:
    """Load intent anchor entries from YAML, sorted for deterministic iteration.

    Returns [] on missing file / pyyaml unavailable / parse error.
    """
    path = Path(yaml_path or os.environ.get("BIOMATE_INTENT_ANCHORS", str(_DEFAULT_YAML)))
    if not path.exists():
        logger.warning("intent_anchors yaml not found at %s", path)
        return []
    try:
        import yaml
    except ImportError:
        logger.warning("pyyaml not installed; intent prioritizer disabled")
        return []
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        logger.warning("failed to parse %s: %s", path, exc)
        return []
    out: List[Dict[str, Any]] = []
    for intent_id, entry in raw.items():
        if not entry or not entry.get("canonical"):
            continue
        out.append({
            "intent_id": intent_id,
            "canonical": entry["canonical"].strip(),
            "trigger_terms": [t.lower().strip() for t in (entry.get("trigger_terms") or []) if t],
            "pipeline_intent_required": bool(entry.get("pipeline_intent_required", False)),
            "disqualified_if_present": [t.lower().strip() for t in (entry.get("disqualified_if_present") or []) if t],
        })
    logger.info("loaded %d intent anchors", len(out))
    return out


def _has_pipeline_intent(query_lc: str) -> bool:
    return any(verb in query_lc for verb in _PIPELINE_VERBS)


def _intent_matches(query_lc: str, entry: Dict[str, Any]) -> Tuple[bool, int]:
    """Returns (matches, n_trigger_hits). Honors `disqualified_if_present`
    and `pipeline_intent_required`."""
    for dq in entry["disqualified_if_present"]:
        if dq in query_lc:
            return False, 0
    if entry["pipeline_intent_required"] and not _has_pipeline_intent(query_lc):
        return False, 0
    n = sum(1 for t in entry["trigger_terms"] if t in query_lc)
    return (n > 0), n


def _candidate_name(cand: Any) -> str:
    """Extract the workflow name from a candidate, supporting both
    dataclass-like objects (attribute access) and plain dicts."""
    if isinstance(cand, dict):
        return str(cand.get("name") or "")
    return str(getattr(cand, "name", "") or "")


def prioritize_workflow_by_intent(query: str, candidates: List[Any],
                                    anchors: Optional[List[Dict[str, Any]]] = None,
                                    ) -> List[Any]:
    """Promote the canonical workflow matching the query's intent to position 1.

    Returns a new list — does not mutate input. Pass-through if no intent or
    multiple intents fire.
    """
    if not candidates or not query:
        return list(candidates)
    if anchors is None:
        anchors = load_intent_anchors()
    if not anchors:
        return list(candidates)

    query_lc = query.lower()
    matched: List[Tuple[Dict[str, Any], int]] = []
    for entry in anchors:
        ok, n = _intent_matches(query_lc, entry)
        if ok:
            matched.append((entry, n))

    if len(matched) == 0:
        return list(candidates)
    if len(matched) > 1:
        # Multiple intents — defer to existing disambiguation, BUT keep the
        # entry with the strongest trigger-density (most distinct triggers
        # in the query) as a tiebreaker. If the strongest entry's score is
        # at least 2× the second-strongest's, treat as confident anyway.
        matched.sort(key=lambda x: -x[1])
        top, second = matched[0], matched[1]
        if top[1] >= 2 * second[1] and top[1] >= 2:
            matched = [top]
        else:
            return list(candidates)

    intent = matched[0][0]
    canonical = intent["canonical"]
    # Find canonical wrapper in candidates (case-insensitive name match)
    canonical_lc = canonical.lower()
    canonical_idx = None
    for i, c in enumerate(candidates):
        if _candidate_name(c).lower() == canonical_lc:
            canonical_idx = i
            break
    if canonical_idx is None or canonical_idx == 0:
        return list(candidates)

    out = list(candidates)
    chosen = out.pop(canonical_idx)
    out.insert(0, chosen)
    return out
