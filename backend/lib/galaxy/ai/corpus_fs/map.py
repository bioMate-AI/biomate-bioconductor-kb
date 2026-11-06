"""corpus_fs.map -- map-reduce fan-out over a grounded corpus (Option B, slice 2).

``corpus_map(index, question, doc_ids, ...)`` dispatches a lightweight per-document
sub-agent (the default greps the document's blocks for the question's key terms
and returns grounded snippets *with provenance*), fans them out via the shared
:func:`galaxy.ai.map_reduce.map_reduce`, and reduces the per-document extracts
into a single structured result.

Grounded-by-construction is preserved end to end: the default worker only ever
returns text that :meth:`CorpusIndex.grep` found physically in the store, and the
default reducer only concatenates those grounded extracts. The synthesis step
(PaperQA2 / ``ResearchAgent``) is left as a clearly marked injection point -- this
slice performs **no** network / LLM call.

Python 3.9-safe; additive / inert (wired into no live path).
"""

from __future__ import annotations

import re
from typing import Any, Callable, Dict, List, Optional

# Shared fan-out layer. Robust to both package import and loose/script execution
# (the corpus_fs test can run with the `ai` dir on sys.path).
try:
    from ..map_reduce import map_reduce
except (ImportError, ValueError):  # pragma: no cover - loose/script path
    from map_reduce import map_reduce  # type: ignore

try:
    from .index import section_path
except ImportError:  # pragma: no cover - loose/script path
    from corpus_fs.index import section_path  # type: ignore


# A compact English stoplist so key-term extraction keeps the content words a
# grounded grep should actually look for. Deliberately small (no NLTK dep).
_STOPWORDS = frozenset(
    """
    a an and are as at be been being but by can could did do does for from had has
    have how in into is it its of on or over so than that the their then there these
    this those to was were what when where which who why will with within would you your
    about across after against all also any because before between both during each
    few more most no not only other same some such their through under until up using
    very we our they them he she his her i me my
    """.split()
)

_TOKEN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9\-]*")
_MIN_TERM_LEN = 3
_MAX_TERMS = 12


def key_terms(question: str, max_terms: int = _MAX_TERMS) -> List[str]:
    """Extract de-duplicated content terms from a free-text question.

    Lower-cased, stop-words and very short tokens dropped, order preserved.
    Returns ``[]`` for empty / non-string input.
    """
    if not isinstance(question, str) or not question.strip():
        return []
    out: List[str] = []
    seen = set()
    for match in _TOKEN_RE.finditer(question.lower()):
        tok = match.group(0)
        if len(tok) < _MIN_TERM_LEN or tok in _STOPWORDS or tok in seen:
            continue
        seen.add(tok)
        out.append(tok)
        if len(out) >= max_terms:
            break
    return out


def make_doc_worker(
    index: Any,
    question: str,
    per_term_limit: int = 20,
) -> Callable[[str], Dict[str, Any]]:
    """Build the default per-document worker.

    The worker greps the document's blocks for each key term of ``question`` and
    returns the grounded extracts (each carrying full provenance: doc_id, path,
    section, line range, snippet). A single document that errors is isolated by
    ``map_reduce`` -- the worker itself does not swallow exceptions.
    """
    terms = key_terms(question)

    def worker(doc_id: str) -> Dict[str, Any]:
        glob = section_path(doc_id, "*")
        extracts: List[Dict[str, Any]] = []
        seen = set()
        for term in terms:
            for hit in index.grep(term, path_glob=glob, limit=per_term_limit):
                dedup = (hit.get("path"), hit.get("line_start"), hit.get("snippet"))
                if dedup in seen:
                    continue
                seen.add(dedup)
                enriched = dict(hit)
                enriched["term"] = term
                extracts.append(enriched)
        meta = {}
        try:
            meta = index.doc_meta(doc_id)
        except Exception:  # metadata is best-effort; never fail the unit over it
            meta = {}
        return {
            "doc_id": doc_id,
            "title": meta.get("title") if isinstance(meta, dict) else None,
            "n_hits": len(extracts),
            "extracts": extracts,
            "meta": meta,
        }

    return worker


def default_reduce(per_doc_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Concatenate grounded per-document extracts into one structured result.

    Returns a flat ``grounded_extracts`` list (provenance preserved) plus simple
    coverage counts. ``synthesis`` is intentionally ``None``: it is the injection
    point for the existing PaperQA2 / ``ResearchAgent`` grounded synthesis, which
    this slice does NOT call (no network / LLM here).
    """
    grounded: List[Dict[str, Any]] = []
    docs_with_hits = 0
    for res in per_doc_results:
        if not isinstance(res, dict):
            continue
        if res.get("n_hits"):
            docs_with_hits += 1
        for ex in res.get("extracts") or []:
            grounded.append(
                {
                    "doc_id": ex.get("doc_id"),
                    "path": ex.get("path"),
                    "section": ex.get("section"),
                    "line_start": ex.get("line_start"),
                    "line_end": ex.get("line_end"),
                    "snippet": ex.get("snippet"),
                    "term": ex.get("term"),
                }
            )
    return {
        "n_docs": len(per_doc_results),
        "n_docs_with_hits": docs_with_hits,
        "n_extracts": len(grounded),
        "grounded_extracts": grounded,
        # TODO(S3): inject PaperQA2 / ResearchAgent synthesis over
        # `grounded_extracts` here. Grounded-by-construction must be preserved:
        # the synthesizer may only cite text present in grounded_extracts. No
        # network / LLM call belongs in this (S2) slice.
        "synthesis": None,
    }


def corpus_map(
    index: Any,
    question: str,
    doc_ids: List[str],
    worker_fn: Optional[Callable[[str], Any]] = None,
    reduce_fn: Optional[Callable[[List[Any]], Any]] = None,
    max_concurrent: int = 8,
) -> Dict[str, Any]:
    """Fan a per-document grounded sub-agent out over ``doc_ids``, then reduce.

    Args:
        index: a :class:`~corpus_fs.index.CorpusIndex` (anything with
            ``grep``/``doc_meta``).
        question: the free-text query; its key terms drive the default worker.
        doc_ids: documents to fan out over (one sub-agent per id).
        worker_fn: override the default per-doc worker. Called as
            ``worker_fn(doc_id)``.
        reduce_fn: override the default reducer. Called with the list of
            successful per-doc results.
        max_concurrent: fan-out concurrency cap.

    Returns the :func:`map_reduce` result dict: ``{"results", "errors",
    "reduced"}`` where ``results`` are the per-document extracts (in input order)
    and ``reduced`` is the concatenated grounded result.
    """
    worker = worker_fn if worker_fn is not None else make_doc_worker(index, question)
    reducer = reduce_fn if reduce_fn is not None else default_reduce
    return map_reduce(
        list(doc_ids or []),
        worker,
        reduce_fn=reducer,
        max_concurrent=max_concurrent,
    )


__all__ = ["corpus_map", "key_terms", "make_doc_worker", "default_reduce"]
