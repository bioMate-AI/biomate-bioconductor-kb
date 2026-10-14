"""
Live retriever wiring — points the Grounded engine at BioMate's REAL data.

This is the only module that imports BioMate internals; the engine itself stays
pure. It composes:
  * Tier A (normative)  -> the curated domain pack (standards/pharmacopoeia).
                           Kept curated until a licensed standards corpus is
                           ingested; BioMate has no live normative-standards
                           source today (the "regulatory packs" are narrative
                           style rules, not a standards corpus).
  * Tier B (literature) -> galaxy.ai.federated_query.iterative_literature_search
                           (PubMed + EuropePMC + Semantic Scholar + OpenAlex).
  * Tier C (firm records) -> OPTIONAL, via an injected tenant-scoped query
                           function (e.g. wrapping galaxy.ai.private_db.run_query
                           with user_id=tenant). Left as a hook because it needs a
                           per-deployment connection + schema decision; not
                           fabricated here.

Every import is guarded: a missing/broken backend degrades to fewer tiers, never
a crash. The engine re-applies the tenant-isolation gate over whatever is
returned, so isolation holds regardless of source.
"""

from __future__ import annotations

import logging
from typing import Any, Callable, List, Optional

from .retrievers import (
    CompositeRetriever,
    CorpusRetriever,
    FirmRecordRetriever,
    LiteratureRetriever,
    Retriever,
)

log = logging.getLogger(__name__)


def _literature_search_fn() -> Optional[Callable[[str, int], Any]]:
    """Adapter over BioMate's federated literature search, or None if absent."""
    try:
        from galaxy.ai.federated_query import iterative_literature_search
    except Exception as exc:  # pragma: no cover
        log.info("[grounded.live] literature search unavailable: %s", exc)
        return None

    def _fn(query: str, limit: int) -> Any:
        # max_depth=1 keeps an interactive answer fast/cheap; min_results=limit.
        return iterative_literature_search(query, max_depth=1, min_results=limit)

    return _fn


def build_live_retriever(
    domain: str = "cmc",
    firm_query_fn: Optional[Callable[[str, str], Any]] = None,
    literature_limit: int = 6,
) -> Retriever:
    """Compose a retriever over BioMate's live sources + the curated normative pack.

    `firm_query_fn(query, user)` is an optional, caller-supplied, TENANT-SCOPED
    record query (returns row dicts); wire it to private_db for a given
    deployment's connection. Omitted -> literature + curated normative only.
    """
    retrievers: List[Retriever] = []

    # Tier A: curated normative/standards pack for the domain.
    try:
        from .domains import get_corpus
        retrievers.append(CorpusRetriever(get_corpus(domain)))
    except Exception as exc:  # pragma: no cover
        log.warning("[grounded.live] domain pack %r unavailable: %s", domain, exc)

    # Tier B: live literature.
    lit_fn = _literature_search_fn()
    if lit_fn is not None:
        retrievers.append(LiteratureRetriever(lit_fn, limit=literature_limit))

    # Tier C: firm records (optional, tenant-scoped).
    if firm_query_fn is not None:
        retrievers.append(FirmRecordRetriever(firm_query_fn))

    return CompositeRetriever(retrievers)
