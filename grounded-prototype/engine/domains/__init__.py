"""
Domain packs for the Grounded Standards Assistant.

A "domain" is a tiered corpus for one regulated area. The engine is corpus-
pluggable: the trust lattice, retrieval, classification, boundary logic, and
isolation are domain-agnostic; only the corpus changes. This is what lets the
same engine serve the R&D/CMC edge BioMate already owns (`cmc`) and the GMP
manufacturing example (`gmp_steam`), and — in production — a tenant-scoped
corpus backed by BioMate's live retrieval + literature + the firm's records.

Registry maps a domain name to a loader returning List[Source].
"""

from __future__ import annotations

from typing import Callable, Dict, List, Optional

from ..models import Source
from ..corpus import load_corpus as _load_gmp_steam
from .cmc import load_corpus as _load_cmc

# name -> loader. Add new domain packs here; nothing else changes.
DOMAIN_LOADERS: Dict[str, Callable[[], List[Source]]] = {
    "gmp_steam": _load_gmp_steam,
    "cmc": _load_cmc,
}

DEFAULT_DOMAIN = "cmc"


def list_domains() -> List[str]:
    return sorted(DOMAIN_LOADERS)


def get_corpus(domain: Optional[str] = None) -> List[Source]:
    """Return the corpus for `domain`.

    None -> every domain combined (retrieval ranks by relevance across all).
    A name -> just that pack. Unknown name -> ValueError (fail loud, not silent).
    """
    if domain is None:
        out: List[Source] = []
        for loader in DOMAIN_LOADERS.values():
            out.extend(loader())
        return out
    if domain not in DOMAIN_LOADERS:
        raise ValueError(
            f"unknown domain {domain!r}; known: {', '.join(list_domains())}"
        )
    return DOMAIN_LOADERS[domain]()
