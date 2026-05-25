"""
Workflow adapter — reimplements `workflow_intent.prioritize_workflow_by_intent`
on top of the unified core, preserving the exact public API. Regression tests
in `tests/test_adapter_workflow.py` confirm bit-identical behavior.

The point isn't to replace workflow_intent.py — it's to prove the core is
expressive enough to host all of the workflow-level logic without losing
features.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, List, Optional

from sandbox.intent_retrieval_v3.core.yaml_loader import load_intent_map
from sandbox.intent_retrieval_v3.core.intent_matcher import (
    match_intents, resolve_single_intent,
)
from sandbox.intent_retrieval_v3.core.candidate_ops import (
    prioritize_candidates, default_synthesizer,
)

# Default path: re-use the existing workflow_search_v2 intent anchors so
# behavior matches across sandboxes. Adapters can override.
_DEFAULT_YAML = (
    Path(__file__).resolve().parents[2]
    / "workflow_search_v2" / "data" / "intent_anchors.yaml"
)


def _candidate_name(c: Any) -> str:
    if isinstance(c, dict):
        return str(c.get("name") or "")
    return str(getattr(c, "name", "") or "")


def prioritize_workflow_by_intent(query: str, candidates: List[Any],
                                    *,
                                    inject_canonical: bool = False,
                                    yaml_path: Optional[str] = None,
                                    ) -> List[Any]:
    """Same contract as sandbox/workflow_search_v2/library/workflow_intent.py.

    Reorders candidates so the canonical workflow for the matched intent is
    first; optionally injects when missing if intent fired with ≥ 2 triggers.
    """
    if not candidates or not query:
        return list(candidates)
    intents = load_intent_map(str(yaml_path or _DEFAULT_YAML))
    if not intents:
        return list(candidates)

    matches = match_intents(query, intents)
    chosen = resolve_single_intent(matches, ambiguity_factor=2.0)
    if chosen is None:
        return list(candidates)

    # Confidence gate for inject: require ≥ 2 trigger matches
    if inject_canonical:
        # Find the n_triggers for chosen
        n_triggers = next((n for entry, n in matches if entry is chosen), 0)
        if n_triggers < 2:
            inject_canonical = False  # downgrade to reorder-only

    return prioritize_candidates(
        candidates,
        canonical_id=chosen["canonical"],
        key_fn=_candidate_name,
        inject_if_missing=inject_canonical,
        inject_synthesizer=default_synthesizer,
    )
