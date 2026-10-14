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
    RegulatoryRetriever,
    Retriever,
)

log = logging.getLogger(__name__)

# Extra query->guideline hints for guidelines not in ich_corpus._DOMAIN_KEYWORDS.
_EXTRA_GUIDELINE_HINTS = {
    "ICH M7": ["mutagenic impurity", "mutagenic impurities", "ttc",
               "dna reactive", "genotoxic impurity", "1.5 ug", "1.5 microgram"],
}


def _regulatory_search_fn():
    """Adapter over BioMate's siloed ICH/FDA/EMA corpus, or None if absent.

    Turns a free-text query into Tier-A guideline passages: detect candidate
    guideline(s) from the query (explicit citation + domain keywords), then pull
    the best-matching passage from each via the corpus's BM25.
    """
    try:
        from galaxy.ai.drug_discovery.ich_corpus import (
            get_ich_corpus, _GUIDELINE_FILES, _DOMAIN_KEYWORDS,
            _extract_citations_local,
        )
    except Exception as exc:  # pragma: no cover
        log.info("[grounded.live] ICH corpus unavailable: %s", exc)
        return None

    def _detect(query: str):
        q = query.lower()
        cands = []
        # explicit citation strings in the query
        for cit in _extract_citations_local(query):
            for key in _GUIDELINE_FILES:
                if cit.lower().replace(" ", "") in key.lower().replace(" ", ""):
                    cands.append(key)
        # domain-keyword match (corpus's own map + extra hints)
        for cit, kws in list(_DOMAIN_KEYWORDS.items()) + list(_EXTRA_GUIDELINE_HINTS.items()):
            if any(kw in q for kw in kws):
                cands.append(cit)
        # de-dup, keep order
        seen, out = set(), []
        for c in cands:
            if c not in seen:
                seen.add(c); out.append(c)
        return out

    def _fn(query: str, limit: int):
        corpus = get_ich_corpus()
        out = []
        for cit in _detect(query)[:limit]:
            try:
                r = corpus.verify_citation(cit, query)
                text = r.top_chunk or ""
                if not text:
                    chunks = corpus._load_guideline(cit)  # fallback to first passage
                    text = (chunks[0][:400] if chunks else "")
                if text:
                    out.append({
                        "citation": cit,
                        "text": text,
                        "score": getattr(r, "score", 0.0),
                        "locator": _GUIDELINE_FILES.get(cit),
                    })
            except Exception as exc:  # pragma: no cover
                log.debug("[grounded.live] verify %s failed: %s", cit, exc)
        return out

    return _fn


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

    # Tier A (live): BioMate's real ICH/FDA/EMA guideline corpus (if present).
    reg_fn = _regulatory_search_fn()
    if reg_fn is not None:
        retrievers.append(RegulatoryRetriever(reg_fn))

    # Tier A (curated): domain pack — covers guidelines not in the ICH corpus
    # (e.g. ICH Q3A) and acts as a fallback when the corpus PDFs aren't present.
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
