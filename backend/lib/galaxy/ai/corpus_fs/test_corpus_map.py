"""Hermetic tests for corpus_fs.map + the federated_query corpus_fs fetcher.

No network, no LLM: a tmp SQLite index is ingested with synthetic documents and
``corpus_map`` fans out over it in-process. Every assertion exercises the
grounded-by-construction guarantee -- a returned snippet is always a literal
substring of an ingested block, carrying provenance.

Runnable two ways:
    python backend/lib/galaxy/ai/corpus_fs/test_corpus_map.py   # PASS/FAIL, N/N
    pytest backend/lib/galaxy/ai/corpus_fs/test_corpus_map.py
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

try:
    from .index import Fts5CorpusIndex, reset_corpus_index
    from .map import corpus_map, default_reduce, key_terms, make_doc_worker
except ImportError:  # pragma: no cover - loose/script path
    import sys

    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from corpus_fs.index import Fts5CorpusIndex, reset_corpus_index  # type: ignore
    from corpus_fs.map import (  # type: ignore
        corpus_map,
        default_reduce,
        key_terms,
        make_doc_worker,
    )


SYNTHETIC_DOCS = [
    {
        "doc_id": "DOC001",
        "title": "A potent kinase inhibitor",
        "year": 2021,
        "source": "synthetic",
        "licence": "CC-BY",
        "blocks": [
            {"section": "Abstract", "kind": "text",
             "text": "We report a kinase inhibitor with nanomolar potency."},
            {"section": "Results", "kind": "text",
             "text": "The compound showed an IC50 of 12 nM against the target kinase."},
        ],
    },
    {
        "doc_id": "DOC002",
        "title": "Antibody affinity maturation",
        "year": 2022,
        "source": "synthetic",
        "licence": "CC-BY-NC",
        "blocks": [
            {"section": "Results", "kind": "text",
             "text": "The lead antibody reached an IC50 of 3 nM in the neutralization assay."},
        ],
    },
    {
        "doc_id": "DOC003",
        "title": "A structural study with no potency data",
        "year": 2020,
        "source": "synthetic",
        "licence": "CC0",
        "blocks": [
            {"section": "Results", "kind": "text",
             "text": "The fold is a classic Rossmann topology with a central beta sheet."},
        ],
    },
]

QUESTION = "What is the IC50 potency of the kinase inhibitor?"


def _fresh_index(tmp_path):
    db = os.path.join(str(tmp_path), "corpus.db")
    idx = Fts5CorpusIndex(db)
    idx.ingest(SYNTHETIC_DOCS)
    return idx, db


# --------------------------------------------------------------------------- #
# key_terms
# --------------------------------------------------------------------------- #
def test_key_terms_drops_stopwords(tmp_path):
    terms = key_terms(QUESTION)
    assert "ic50" in terms, terms
    assert "kinase" in terms, terms
    assert "inhibitor" in terms, terms
    # stop-words / short tokens dropped
    assert "is" not in terms and "the" not in terms and "of" not in terms, terms


def test_key_terms_empty(tmp_path):
    assert key_terms("") == []
    assert key_terms(None) == []  # type: ignore[arg-type]


# --------------------------------------------------------------------------- #
# corpus_map: grounded per-doc extracts + reduced result
# --------------------------------------------------------------------------- #
def test_corpus_map_grounded_per_doc(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    out = corpus_map(idx, QUESTION, ["DOC001", "DOC002", "DOC003"])

    # One per-doc result per input doc, in input order.
    assert [r["doc_id"] for r in out["results"]] == ["DOC001", "DOC002", "DOC003"]
    assert out["errors"] == []

    by_id = {r["doc_id"]: r for r in out["results"]}
    # DOC001 mentions the kinase inhibitor + IC50 -> hits.
    assert by_id["DOC001"]["n_hits"] >= 1, by_id["DOC001"]
    # DOC003 has none of the key terms -> no hits.
    assert by_id["DOC003"]["n_hits"] == 0, by_id["DOC003"]

    # Grounded by construction: each extract's snippet exists in the doc's block.
    doc001_text = " ".join(b["text"] for b in SYNTHETIC_DOCS[0]["blocks"])
    for ex in by_id["DOC001"]["extracts"]:
        assert ex["snippet"] in doc001_text, ex
        assert ex["term"].lower() in ex["snippet"].lower(), ex
        # provenance present
        assert ex["doc_id"] == "DOC001" and ex["path"] and ex["section"]


def test_corpus_map_reduced_structure(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    out = corpus_map(idx, QUESTION, ["DOC001", "DOC002", "DOC003"])
    red = out["reduced"]
    assert red is not None
    assert red["n_docs"] == 3
    assert red["n_docs_with_hits"] >= 1
    assert red["n_extracts"] == len(red["grounded_extracts"])
    assert red["n_extracts"] >= 1
    # Synthesis is the (unused in S2) injection point -- never populated here.
    assert red["synthesis"] is None
    # every grounded extract carries provenance
    for ex in red["grounded_extracts"]:
        assert ex["doc_id"] and ex["path"] and ex["section"] is not None
        assert ex["snippet"]


def test_corpus_map_custom_worker_and_reduce(tmp_path):
    idx, _ = _fresh_index(tmp_path)

    def worker(doc_id):
        return {"doc_id": doc_id, "n_hits": 1, "extracts": []}

    out = corpus_map(
        idx, QUESTION, ["DOC001", "DOC002"],
        worker_fn=worker,
        reduce_fn=lambda rs: {"total_docs": len(rs)},
    )
    assert out["reduced"] == {"total_docs": 2}, out["reduced"]
    assert [r["doc_id"] for r in out["results"]] == ["DOC001", "DOC002"]


def test_corpus_map_empty_doc_set(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    out = corpus_map(idx, QUESTION, [])
    assert out["results"] == []
    assert out["reduced"]["n_docs"] == 0
    assert out["reduced"]["grounded_extracts"] == []


def test_make_doc_worker_isolated_callable(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    worker = make_doc_worker(idx, QUESTION)
    res = worker("DOC002")
    assert res["doc_id"] == "DOC002"
    assert res["title"] == "Antibody affinity maturation"
    assert res["n_hits"] >= 1  # DOC002 mentions IC50


def test_default_reduce_direct(tmp_path):
    per_doc = [
        {"doc_id": "D1", "n_hits": 1, "extracts": [
            {"doc_id": "D1", "path": "/papers/D1/sections/Results.lines",
             "section": "Results", "line_start": 1, "line_end": 1,
             "snippet": "x", "term": "x"}]},
        {"doc_id": "D2", "n_hits": 0, "extracts": []},
    ]
    red = default_reduce(per_doc)
    assert red["n_docs"] == 2 and red["n_docs_with_hits"] == 1 and red["n_extracts"] == 1


# --------------------------------------------------------------------------- #
# federated_query corpus_fs fetcher: SAFE / opt-in
# --------------------------------------------------------------------------- #
def _load_fetcher():
    import sys

    # federated_query lives one level up (galaxy.ai). Import it directly.
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import federated_query  # type: ignore

    return federated_query


def test_fetcher_returns_empty_without_corpus(tmp_path):
    fq = _load_fetcher()
    prev_db = os.environ.pop("CORPUS_INDEX_DB", None)
    prev_backend = os.environ.pop("CORPUS_INDEX_BACKEND", None)
    try:
        res = fq._fetch_corpus_fs("kinase inhibitor IC50")
        assert res == {"source": "corpus_fs", "results": []}, res
    finally:
        if prev_db is not None:
            os.environ["CORPUS_INDEX_DB"] = prev_db
        if prev_backend is not None:
            os.environ["CORPUS_INDEX_BACKEND"] = prev_backend


def test_fetcher_returns_empty_for_missing_db_path(tmp_path):
    fq = _load_fetcher()
    prev_db = os.environ.get("CORPUS_INDEX_DB")
    os.environ["CORPUS_INDEX_DB"] = os.path.join(str(tmp_path), "does_not_exist.db")
    try:
        res = fq._fetch_corpus_fs("kinase")
        assert res == {"source": "corpus_fs", "results": []}, res
    finally:
        if prev_db is None:
            os.environ.pop("CORPUS_INDEX_DB", None)
        else:
            os.environ["CORPUS_INDEX_DB"] = prev_db


def test_fetcher_returns_grounded_when_corpus_present(tmp_path):
    fq = _load_fetcher()
    _, db = _fresh_index(tmp_path)
    reset_corpus_index()
    prev_db = os.environ.get("CORPUS_INDEX_DB")
    prev_backend = os.environ.get("CORPUS_INDEX_BACKEND")
    os.environ["CORPUS_INDEX_DB"] = db
    os.environ["CORPUS_INDEX_BACKEND"] = "fts5"
    try:
        res = fq._fetch_corpus_fs("kinase inhibitor IC50")
        assert res["source"] == "corpus_fs"
        assert len(res["results"]) >= 1, res
        for r in res["results"]:
            assert r["_grounded"] is True
            assert r["doc_id"] and r["snippet"] and r["path"]
    finally:
        reset_corpus_index()
        if prev_db is None:
            os.environ.pop("CORPUS_INDEX_DB", None)
        else:
            os.environ["CORPUS_INDEX_DB"] = prev_db
        if prev_backend is None:
            os.environ.pop("CORPUS_INDEX_BACKEND", None)
        else:
            os.environ["CORPUS_INDEX_BACKEND"] = prev_backend


# --------------------------------------------------------------------------- #
# standalone runner
# --------------------------------------------------------------------------- #
def _run_all():
    import inspect

    tests = sorted(
        (name, fn)
        for name, fn in globals().items()
        if name.startswith("test_") and inspect.isfunction(fn)
    )
    passed = 0
    failed = 0
    for name, fn in tests:
        with tempfile.TemporaryDirectory() as tmp:
            try:
                fn(Path(tmp))
                passed += 1
                print("PASS  {}".format(name))
            except Exception as exc:  # noqa: BLE001
                failed += 1
                print("FAIL  {}: {}: {}".format(name, type(exc).__name__, exc))
    total = passed + failed
    print("\n{}/{} tests passed".format(passed, total))
    return failed == 0


if __name__ == "__main__":
    import sys

    sys.exit(0 if _run_all() else 1)
