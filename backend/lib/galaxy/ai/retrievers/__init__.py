"""
BioMate retrieval utilities — pure library functions, no API call sites.

Each module here is intentionally side-effect-free and standalone. Callers
opt-in by importing and using; nothing in this package is auto-wired into
the AI assistant routes. See module-level docs for integration guidance.
"""
from .family_dedup import (
    load_alias_map,
    load_canonical_map,
    canonical_family_key,
    dedup_results_by_family,
    rerank_to_canonical,
    prioritize_query_family,
)

__all__ = [
    "load_alias_map",
    "load_canonical_map",
    "canonical_family_key",
    "dedup_results_by_family",
    "rerank_to_canonical",
    "prioritize_query_family",
]
