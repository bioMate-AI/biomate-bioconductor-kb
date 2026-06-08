"""
chain_composer — L2/L3 pattern-aware chain generation prototype.

Reads the canonical pattern library (`docs/20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md`),
retrieves relevant patterns + curated-chain exemplars for a query, composes a
candidate chain (LLM if available, deterministic stub otherwise), and scores
confidence to choose a surfacing mode.

This is a prototype — not wired into production routing. Designed so each
piece (loader / retrieval / confidence / composer) is independently testable.

Design context:
- docs/20260608_CHAIN_GENERATION_DESIGN.md — three-layer architecture
- docs/20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md — pattern definitions
- docs/20260608_CHAIN_DESIGN_FINDINGS_OPEN_QUESTIONS.md — parked decisions
"""

from .pattern_loader import Pattern, load_patterns
from .retrieval import retrieve_patterns, retrieve_curated_chains
from .confidence import ConfidenceSignals, score_confidence, choose_surfacing_mode
from .composer import compose_chain, ComposedChain

__all__ = [
    "Pattern",
    "load_patterns",
    "retrieve_patterns",
    "retrieve_curated_chains",
    "ConfidenceSignals",
    "score_confidence",
    "choose_surfacing_mode",
    "compose_chain",
    "ComposedChain",
]
