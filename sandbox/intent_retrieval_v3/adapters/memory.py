"""
Memory recall adapter — Opportunity 1 from the session-review doc.

Today, auto-memory loads MEMORY.md (1084 lines, ~114KB) into every
conversation and lets the LLM scan it linearly. When the user asks an
unambiguous question that maps to a known memory topic (e.g. "what's
the BixBench status?"), there's no signal-boost for the relevant
memory file.

This adapter:
  - Reads sandbox/intent_retrieval_v3/data/memory_intents.yaml
  - When the user query unambiguously maps to a known memory topic,
    promotes/injects that memory file's basename into the candidate list.
  - Falls through to existing fuzzy-search behavior when the query is
    ambiguous (multiple intents fire or no intent fires).

API is intentionally identical in shape to the workflow adapter so the
shared framework is consistent across domains.
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

_DEFAULT_YAML = Path(__file__).resolve().parents[1] / "data" / "memory_intents.yaml"


def _memory_key(c: Any) -> str:
    """Memory candidates are file basenames (strings) or dicts with 'file'."""
    if isinstance(c, str):
        return c
    if isinstance(c, dict):
        return str(c.get("file") or c.get("name") or "")
    return str(getattr(c, "file", None) or getattr(c, "name", "") or "")


def _memory_synth(template: Any, canonical_file: str) -> Any:
    """Synthesize a memory candidate matching the template's type."""
    if isinstance(template, str):
        return canonical_file
    if isinstance(template, dict):
        return {**template, "file": canonical_file, "source": "intent_anchor"}
    return default_synthesizer(template, canonical_file)


def prioritize_memory_by_intent(query: str, candidate_files: List[Any],
                                  *,
                                  inject_canonical: bool = True,
                                  yaml_path: Optional[str] = None,
                                  ) -> List[Any]:
    """Promote/inject the canonical memory file when query has unambiguous
    intent. Defaults to inject_canonical=True because memory recall benefits
    most from injection (the candidate often isn't in fuzzy search results).

    Args:
      query: user's natural-language question.
      candidate_files: ranked list of memory-file candidates (basenames or
        dicts with 'file' key). Order preserved when no intent fires.

    Returns new list; never mutates input.
    """
    if not query:
        return list(candidate_files)
    intents = load_intent_map(str(yaml_path or _DEFAULT_YAML))
    if not intents:
        return list(candidate_files)
    matches = match_intents(query, intents)
    chosen = resolve_single_intent(matches, ambiguity_factor=2.0)
    if chosen is None:
        return list(candidate_files)

    # Confidence gate for inject: require ≥ 2 trigger matches
    if inject_canonical:
        n = next((nn for entry, nn in matches if entry is chosen), 0)
        if n < 2:
            inject_canonical = False

    return prioritize_candidates(
        candidate_files or [""],   # tolerate empty list when injecting
        canonical_id=chosen["canonical"],
        key_fn=_memory_key,
        inject_if_missing=inject_canonical,
        inject_synthesizer=_memory_synth,
    )
