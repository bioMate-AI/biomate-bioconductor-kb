"""corpus_fs -- grounded corpus-as-filesystem index (Option B, slice 1).

Pluggable ``CorpusIndex`` (Protocol) with an embedded SQLite FTS5 backend that
exposes ``ls`` / ``cat`` / ``grep`` / ``find`` virtual-FS primitives over a
document corpus, grounded by construction (only ever returns stored text).

Inert / additive: not wired into any live path. See
``docs/20261008_CORPUS_FS_OPTION_B_DESIGN.md``.
"""

from __future__ import annotations

from .index import (
    CorpusIndex,
    Fts5CorpusIndex,
    get_corpus_index,
    parse_path,
    reset_corpus_index,
    section_path,
)
from .map import (
    corpus_map,
    default_reduce,
    key_terms,
    make_doc_worker,
)

__all__ = [
    "CorpusIndex",
    "Fts5CorpusIndex",
    "get_corpus_index",
    "reset_corpus_index",
    "section_path",
    "parse_path",
    "corpus_map",
    "key_terms",
    "make_doc_worker",
    "default_reduce",
]
