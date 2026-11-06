"""
Source router — maps (use-case intent + entities) to a RANKED SET of sources
across all kinds (publications + knowledge bases + regulatory + clinical +
patent + web), not "one entity type -> one fixed list".

Rule-first (deterministic, testable, zero-cost) with an injectable LLM fallback
for novel intents — the hybrid BioMate already uses for extraction. Only keyless
sources are selected by default (honour the "no credential application" rule);
non-keyless sources are included only when explicitly allowed.
"""

from __future__ import annotations

from typing import Callable, List, Optional, Tuple

from . import registry
from .registry import (
    CLINICAL, KNOWLEDGE_BASE, PATENT, PUBLICATION, REGULATORY, STRUCTURE, WEB,
)

# Use-case intents -> ordered list of source KINDS that matter for that intent.
# The router expands kinds to concrete keyless sources, entity-filtered.
_INTENT_KINDS = {
    "admet":        [KNOWLEDGE_BASE, REGULATORY, PUBLICATION, PATENT],
    "regulatory":   [REGULATORY, PUBLICATION],
    "clinical":     [CLINICAL, PUBLICATION, REGULATORY],
    "variant":      [KNOWLEDGE_BASE, PUBLICATION, CLINICAL],
    "structure":    [STRUCTURE, KNOWLEDGE_BASE, PUBLICATION],
    "mechanism":    [PUBLICATION, KNOWLEDGE_BASE],
    "recency":      [PUBLICATION, WEB],        # preprints + web for newest
    "general":      [PUBLICATION, KNOWLEDGE_BASE],
}

# Lightweight keyword -> intent cues (rule layer). LLM fallback refines.
_INTENT_CUES = {
    "admet":      ["admet", "herg", "cyp", "bioavailability", "toxicity", "ames",
                   "solubility", "clearance", "impurity", "mutagenic"],
    "regulatory": ["ich", "fda", "ema", "guideline", "guidance", "cfr", "gmp",
                   "pharmacopoeia", "regulatory", "specification", "threshold"],
    "clinical":   ["trial", "phase i", "phase ii", "phase iii", "adverse event",
                   "faers", "clinicaltrials", "endpoint", "patient"],
    "variant":    ["variant", "mutation", "snp", "rs", "pathogenic", "clinvar"],
    "structure":  ["structure", "pdb", "crystal", "fold", "alphafold", "domain"],
    "recency":    ["latest", "recent", "newest", "2026", "2025", "preprint", "news"],
}


def detect_intent(question: str) -> str:
    q = question.lower()
    best, best_hits = "general", 0
    for intent, cues in _INTENT_CUES.items():
        hits = sum(1 for c in cues if c in q)
        if hits > best_hits:
            best, best_hits = intent, hits
    return best


def route(
    question: str,
    *,
    entities: Optional[List[str]] = None,
    allow_nonkeyless: bool = False,
    intent_fn: Optional[Callable[[str], str]] = None,
    max_sources: int = 6,
    kinds_override: Optional[dict] = None,
) -> Tuple[List[registry.SourceSpec], str]:
    """Return (ranked source set, detected intent) for this question.

    `intent_fn` is the injectable LLM fallback; defaults to the rule detector.
    `kinds_override` ({intent: [kinds]}) lets a harness config change which source
    KINDS an intent pulls — the knob the Harness2-style improver edits.
    Sources are ordered by intent-kind priority, then authority (A>B>C), and
    filtered to keyless unless `allow_nonkeyless`.
    """
    intent = (intent_fn or detect_intent)(question)
    table = {**_INTENT_KINDS, **(kinds_override or {})}
    kinds = table.get(intent, table["general"])
    kind_rank = {k: i for i, k in enumerate(kinds)}

    picked: List[registry.SourceSpec] = []
    for s in registry.all_sources():
        if s.kind not in kind_rank:
            continue
        if not s.keyless and not allow_nonkeyless:
            continue
        if entities and s.entity_types and not (set(entities) & set(s.entity_types)):
            # entity filter only when the source declares entity types
            continue
        picked.append(s)

    picked.sort(key=lambda s: (kind_rank[s.kind], s.authority.value))
    return picked[:max_sources], intent
