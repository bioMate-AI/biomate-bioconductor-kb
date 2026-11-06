"""Hermetic tests for corpus_fs (no network, tmp SQLite, synthetic docs).

Runnable two ways:

    python backend/lib/galaxy/ai/corpus_fs/test_corpus_fs.py   # prints PASS/FAIL, N/N
    pytest backend/lib/galaxy/ai/corpus_fs/test_corpus_fs.py

Every assertion exercises the grounded-by-construction guarantee: a grep hit's
snippet must be a literal substring of an ingested block.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

# Support running as a loose script (python test_corpus_fs.py) as well as an
# installed package module (pytest / import).
try:
    from .index import (
        Fts5CorpusIndex,
        get_corpus_index,
        parse_path,
        reset_corpus_index,
        section_path,
    )
except ImportError:  # pragma: no cover - script execution path
    import sys

    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from corpus_fs.index import (  # type: ignore
        Fts5CorpusIndex,
        get_corpus_index,
        parse_path,
        reset_corpus_index,
        section_path,
    )


# -- synthetic corpus -------------------------------------------------------

SYNTHETIC_DOCS = [
    {
        "doc_id": "DOC001",
        "title": "A potent kinase inhibitor",
        "year": 2021,
        "source": "synthetic",
        "url": "https://example.org/DOC001",
        "licence": "CC-BY",
        "blocks": [
            {"section": "Abstract", "kind": "text",
             "text": "We report a kinase inhibitor with nanomolar potency."},
            {"section": "Methods", "kind": "text",
             "text": "Binding was measured by SPR at 25 degrees C."},
            {"section": "Results", "kind": "text",
             "text": "The compound showed an IC50 of 12 nM against the target kinase."},
        ],
    },
    {
        "doc_id": "DOC002",
        "title": "Antibody affinity maturation",
        "year": 2022,
        "source": "synthetic",
        "url": "https://example.org/DOC002",
        "licence": "CC-BY-NC",
        "blocks": [
            {"section": "Abstract", "kind": "text",
             "text": "An antibody panel was characterized for affinity."},
            {"section": "Results", "kind": "text",
             "text": "The lead antibody reached an IC50 of 3 nM in the neutralization assay."},
        ],
    },
    {
        "doc_id": "DOC003",
        "title": "A structural study with no potency data",
        "year": 2020,
        "source": "synthetic",
        "url": "https://example.org/DOC003",
        "licence": "CC0",
        "blocks": [
            {"section": "Abstract", "kind": "text",
             "text": "We solved the crystal structure at 1.8 Angstrom resolution."},
            {"section": "Results", "kind": "text",
             "text": "The fold is a classic Rossmann topology with a central beta sheet."},
        ],
    },
]


# -- test registry ----------------------------------------------------------

_RESULTS = []


def _check(name, ok, detail=""):
    _RESULTS.append((name, bool(ok), detail))
    if not ok:
        raise AssertionError("{}: {}".format(name, detail or "assertion failed"))


def _fresh_index(tmp_path):
    db = os.path.join(str(tmp_path), "corpus.db")
    idx = Fts5CorpusIndex(db)
    counts = idx.ingest(SYNTHETIC_DOCS)
    return idx, counts


# -- individual tests (pytest-discoverable) ---------------------------------

def test_ingest_counts(tmp_path):
    _, counts = _fresh_index(tmp_path)
    _check("ingest.documents", counts["documents"] == 3, str(counts))
    _check("ingest.blocks", counts["blocks"] == 7, str(counts))


def test_ingest_idempotent(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    again = idx.ingest(SYNTHETIC_DOCS)
    _check("ingest.idempotent.docs", again["documents"] == 0, str(again))
    _check("ingest.idempotent.dups", again["duplicate_documents"] == 3, str(again))
    _check("ingest.idempotent.noblocks", again["blocks"] == 0, str(again))


def test_ls_section_paths(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    paths = idx.ls("DOC001")
    expected = {
        section_path("DOC001", "Abstract"),
        section_path("DOC001", "Methods"),
        section_path("DOC001", "Results"),
    }
    _check("ls.paths", set(paths) == expected, "{} != {}".format(paths, expected))
    _check("ls.unknown", idx.ls("NOPE") == [], "unknown doc should list nothing")


def test_cat_exact_text(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    path = section_path("DOC001", "Results")
    expected = "The compound showed an IC50 of 12 nM against the target kinase."
    _check("cat.exact", idx.cat("DOC001", path) == expected, repr(idx.cat("DOC001", path)))


def test_grep_results_glob_provenance(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    glob = "/papers/*/sections/Results.lines"
    hits = idx.grep("IC50", glob)
    # Only Results sections of DOC001 + DOC002 contain IC50; DOC003 has none.
    doc_ids = sorted(hit["doc_id"] for hit in hits)
    _check("grep.docs", doc_ids == ["DOC001", "DOC002"], str(doc_ids))
    for hit in hits:
        _check("grep.section", hit["section"] == "Results", str(hit))
        _check("grep.path", hit["path"] == section_path(hit["doc_id"], "Results"), str(hit))
        _check("grep.lines",
               isinstance(hit["line_start"], int) and isinstance(hit["line_end"], int)
               and hit["line_start"] <= hit["line_end"], str(hit))
        _check("grep.snippet_has_term", "IC50" in hit["snippet"], str(hit))


def test_grep_grounded_by_construction(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    # Every snippet returned must be a literal substring of a stored block.
    stored = [b["text"] for d in SYNTHETIC_DOCS for b in d["blocks"]]
    for hit in idx.grep("IC50"):
        _check(
            "grep.grounded",
            any(hit["snippet"] in text for text in stored),
            "snippet not substring of any stored block: {!r}".format(hit["snippet"]),
        )


def test_grep_absent_term(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    _check("grep.absent", idx.grep("zzznonexistentzzz") == [], "absent term must return []")
    _check("grep.empty_pattern", idx.grep("") == [], "empty pattern must return []")


def test_grep_glob_scopes_section(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    # Abstract-only glob: IC50 appears only in Results, so this is empty.
    hits = idx.grep("IC50", "/papers/*/sections/Abstract.lines")
    _check("grep.glob_scope", hits == [], str(hits))
    # Specific doc glob narrows to one document.
    only001 = idx.grep("IC50", "/papers/DOC001/sections/Results.lines")
    _check("grep.glob_doc", [h["doc_id"] for h in only001] == ["DOC001"], str(only001))


def test_grep_phrase_like_path(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    # Multi-word pattern -> LIKE path. "target kinase" is literal in DOC001.
    hits = idx.grep("target kinase")
    _check("grep.phrase", [h["doc_id"] for h in hits] == ["DOC001"], str(hits))
    for hit in hits:
        _check("grep.phrase_grounded", "target kinase" in hit["snippet"], str(hit))


def test_find_predicates(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    _check("find.all", idx.find() == ["DOC001", "DOC002", "DOC003"], str(idx.find()))
    _check("find.year", idx.find(year=2022) == ["DOC002"], str(idx.find(year=2022)))
    _check("find.title", idx.find(title="antibody") == ["DOC002"], str(idx.find(title="antibody")))
    by_text = idx.find(text="IC50")
    _check("find.text", by_text == ["DOC001", "DOC002"], str(by_text))
    _check("find.licence", idx.find(licence="CC0") == ["DOC003"], str(idx.find(licence="CC0")))
    _check("find.text_absent", idx.find(text="zzznope") == [], "absent text predicate -> []")


def test_doc_meta(tmp_path):
    idx, _ = _fresh_index(tmp_path)
    meta = idx.doc_meta("DOC002")
    _check("doc_meta.id", meta.get("doc_id") == "DOC002", str(meta))
    _check("doc_meta.year", meta.get("year") == 2022, str(meta))
    _check("doc_meta.licence", meta.get("licence") == "CC-BY-NC", str(meta))
    _check("doc_meta.unknown", idx.doc_meta("NOPE") == {}, "unknown doc -> {}")


def test_path_translation(tmp_path):
    p = section_path("DOC001", "Results")
    _check("path.build", p == "/papers/DOC001/sections/Results.lines", p)
    parsed = parse_path(p)
    _check("path.parse", parsed == {"doc_id": "DOC001", "section": "Results"}, str(parsed))
    bad = False
    try:
        parse_path("/not/a/corpus/path")
    except ValueError:
        bad = True
    _check("path.parse_invalid", bad, "invalid path should raise ValueError")


def test_ingest_jsonl_file(tmp_path):
    import json
    jsonl = os.path.join(str(tmp_path), "docs.jsonl")
    with open(jsonl, "w", encoding="utf-8") as handle:
        for doc in SYNTHETIC_DOCS:
            handle.write(json.dumps(doc) + "\n")
    idx = Fts5CorpusIndex(os.path.join(str(tmp_path), "fromfile.db"))
    counts = idx.ingest(jsonl)
    _check("jsonl.docs", counts["documents"] == 3, str(counts))
    _check("jsonl.grep", [h["doc_id"] for h in idx.grep("Rossmann")] == ["DOC003"], "jsonl grep")


def test_factory_backend(tmp_path):
    reset_corpus_index()
    prev = os.environ.get("CORPUS_INDEX_BACKEND")
    try:
        os.environ.pop("CORPUS_INDEX_BACKEND", None)
        idx = get_corpus_index(os.path.join(str(tmp_path), "factory.db"))
        _check("factory.default_fts5", isinstance(idx, Fts5CorpusIndex), type(idx).__name__)

        os.environ["CORPUS_INDEX_BACKEND"] = "es"
        reset_corpus_index()
        raised = False
        try:
            get_corpus_index(os.path.join(str(tmp_path), "es.db"))
        except NotImplementedError as exc:
            raised = "ES backend not implemented" in str(exc)
        _check("factory.es_raises", raised, "es backend must raise NotImplementedError")
    finally:
        if prev is None:
            os.environ.pop("CORPUS_INDEX_BACKEND", None)
        else:
            os.environ["CORPUS_INDEX_BACKEND"] = prev
        reset_corpus_index()


# -- standalone runner ------------------------------------------------------

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
            except Exception as exc:  # noqa: BLE001 - report everything
                failed += 1
                print("FAIL  {}: {}".format(name, exc))
    total = passed + failed
    print("\n{}/{} tests passed".format(passed, total))
    return failed == 0


if __name__ == "__main__":
    import sys

    sys.exit(0 if _run_all() else 1)
