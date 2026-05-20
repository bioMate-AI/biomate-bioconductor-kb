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

# Wired wrappers (opt-in via env flags). Imported lazily because they pull in
# galaxy.* and sandbox.* modules that may not always be on path at import time.
def get_wired_recommender():
    """Lazy import — avoids hard dependency on galaxy.* at package import."""
    from .wired_recommender import WiredToolParameterRecommender
    return WiredToolParameterRecommender


def get_wired_workflow_search():
    """Lazy import — avoids hard dependency on galaxy.* at package import."""
    from .wired_workflow_search import WiredWorkflowSearch
    return WiredWorkflowSearch

