"""
Pluggable retrieval sources.

The engine answers over a list of candidate `Source`s; where those come from is
a seam. A `Retriever` produces candidates; the engine then applies the SAME
scoring + tenant-isolation gate (`retrieve()`), so isolation is enforced once,
centrally, regardless of which backend produced a source (defence in depth —
even a mis-scoped live source is re-gated here).

Retrievers here take INJECTED callables, not Galaxy imports, so the mechanism is
unit-testable without a backend or a network. The production wiring
(`galaxy.ai.grounded.live`) passes BioMate's real functions in:
  * literature  -> galaxy.ai.federated_query.iterative_literature_search  (Tier B)
  * firm records -> galaxy.ai.private_db.run_query(..., user_id=tenant)    (Tier C)
  * normative   -> the curated domain pack (Tier A) until a licensed
                   standards/pharmacopoeia corpus is ingested.
"""

from __future__ import annotations

import re
from typing import Any, Callable, Dict, List, Optional

from .models import Source, SourceTier

_WORD = re.compile(r"[a-z0-9.]+")


def _keywords_from_text(*texts: str, limit: int = 12) -> List[str]:
    """Cheap keyword seeding from free text (title/abstract) for scoring.

    The scorer also matches on body text, so this only needs to be a mild boost,
    not an exhaustive index.
    """
    seen: List[str] = []
    for t in texts:
        for tok in _WORD.findall((t or "").lower()):
            if len(tok) > 3 and tok not in seen:
                seen.append(tok)
            if len(seen) >= limit:
                return seen
    return seen


class Retriever:
    """Produces candidate Sources for a query (tenant-aware if relevant)."""

    def fetch(self, query: str, user: str) -> List[Source]:  # pragma: no cover
        raise NotImplementedError


class CorpusRetriever(Retriever):
    """Wraps a static corpus (the seed packs / any pre-built list)."""

    def __init__(self, corpus: List[Source]):
        self._corpus = list(corpus)

    def fetch(self, query: str, user: str) -> List[Source]:
        return list(self._corpus)


def literature_item_to_source(item: Dict[str, Any]) -> Optional[Source]:
    """Map one literature-search result dict to a Tier-B Source.

    Tolerant of the field variations across PubMed / EuropePMC / Semantic Scholar
    / OpenAlex (title, authors, year, journal, abstract, url/pmid/doi).
    """
    title = (item.get("title") or "").strip()
    if not title:
        return None
    pmid = item.get("pmid") or item.get("paper_id")
    authors = item.get("authors")
    if isinstance(authors, list):
        authors = ", ".join(a for a in authors if a)
    year = item.get("year")
    journal = item.get("journal") or ""
    abstract = item.get("abstract") or ""
    url = (
        item.get("full_text_url")
        or item.get("pdf_url")
        or item.get("url")
        or (f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/" if pmid else None)
    )
    doi = item.get("doi")
    citation_bits = [b for b in [authors, f"({year})" if year else None, journal] if b]
    citation = " ".join(citation_bits) or title[:80]
    if doi:
        citation += f" doi:{doi}"
    src_id = f"lit:{pmid or (doi or title[:40])}"
    return Source(
        id=src_id,
        tier=SourceTier.PEER_REVIEWED,
        title=title,
        citation=citation,
        text=abstract or title,
        owner=None,                 # literature is shared/global
        verified=True,              # a real, locatable publication
        locator=url,
        keywords=_keywords_from_text(title, abstract),
    )


class LiteratureRetriever(Retriever):
    """Tier-B peer-reviewed literature via an injected search function.

    `search_fn(query, limit) -> {"results": [ {title, authors, ...}, ... ]}`
    (the shape of galaxy.ai.federated_query.iterative_literature_search), or a
    bare list of such dicts. Failures degrade to no sources, never an exception —
    a dead literature backend must not take down the answer.
    """

    def __init__(self, search_fn: Callable[..., Any], limit: int = 6):
        self._search_fn = search_fn
        self._limit = limit

    def fetch(self, query: str, user: str) -> List[Source]:
        try:
            raw = self._search_fn(query, self._limit)
        except Exception:
            return []
        items = raw.get("results") if isinstance(raw, dict) else raw
        out: List[Source] = []
        for item in (items or [])[: self._limit]:
            if isinstance(item, dict):
                s = literature_item_to_source(item)
                if s is not None:
                    out.append(s)
        return out


class FirmRecordRetriever(Retriever):
    """Tier-C firm records via an injected, TENANT-SCOPED query function.

    `query_fn(query, user) -> [ {title, text, citation, locator?, verified?}, ... ]`.
    The caller is responsible for scoping the query to `user` (e.g. private_db
    keyed on user_id); every returned Source is additionally stamped
    `owner=user`, so the engine's isolation gate re-confirms the scoping.
    """

    def __init__(self, query_fn: Callable[[str, str], Any]):
        self._query_fn = query_fn

    def fetch(self, query: str, user: str) -> List[Source]:
        try:
            rows = self._query_fn(query, user)
        except Exception:
            return []
        out: List[Source] = []
        for i, row in enumerate(rows or []):
            if not isinstance(row, dict):
                continue
            text = row.get("text") or row.get("summary") or ""
            title = row.get("title") or f"firm record {i + 1}"
            out.append(Source(
                id=row.get("id") or f"firm:{user}:{i}",
                tier=SourceTier.ORG_VALIDATED if row.get("verified", True)
                else SourceTier.UNVERIFIED_PERSONAL,
                title=title,
                citation=row.get("citation") or "internal record",
                text=text or title,
                owner=user,                       # tenant-scoped, always
                verified=bool(row.get("verified", True)),
                locator=row.get("locator"),
                keywords=_keywords_from_text(title, text),
            ))
        return out


class CompositeRetriever(Retriever):
    """Union of several retrievers, de-duplicated by source id (first wins)."""

    def __init__(self, retrievers: List[Retriever]):
        self._retrievers = list(retrievers)

    def fetch(self, query: str, user: str) -> List[Source]:
        seen: Dict[str, Source] = {}
        for r in self._retrievers:
            for s in r.fetch(query, user):
                if s.id not in seen:
                    seen[s.id] = s
        return list(seen.values())
