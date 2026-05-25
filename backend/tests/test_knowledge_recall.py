"""Tests for `recall_project_knowledge` — query-aware ProjectKnowledge retrieval.

ProjectKnowledge has no service class in agentic_memory.py — this helper
adds the query-aware recall surface that was missing. Tests use mocked
SQLAlchemy session to avoid DB setup.
"""
from __future__ import annotations

import os
import sys
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
sys.path.insert(0, str(ROOT))

from backend.lib.galaxy.ai.retrievers.knowledge_recall import (  # noqa: E402
    recall_project_knowledge,
)


def _make_row(id_: int, title: str, content: str = "", relevance: float = 1.0):
    """Build a duck-typed ProjectKnowledge row."""
    r = MagicMock()
    r.id = id_
    r.project_id = "proj1"
    r.knowledge_type = "fact"
    r.title = title
    r.content = content
    r.source = "test"
    r.relevance_score = relevance
    return r


@pytest.fixture
def mock_session_factory():
    """Returns a context-manager factory that yields a configurable session."""
    session = MagicMock()
    @contextmanager
    def _factory():
        yield session
    _factory.session = session  # expose for tests to configure
    return _factory


@pytest.fixture(autouse=True)
def _reset_env():
    prev = os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)
    yield
    if prev is not None:
        os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = prev
    else:
        os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)


# ─── Shape + edge cases ───────────────────────────────────────────

def test_no_project_id_returns_empty(mock_session_factory):
    out = recall_project_knowledge(None, "BRCA1", session_factory=mock_session_factory)
    assert out == {"entries": [], "extracted_entities": [], "fallback_used": False}


def test_empty_query_returns_empty(mock_session_factory):
    out = recall_project_knowledge("proj1", "", session_factory=mock_session_factory)
    assert out == {"entries": [], "extracted_entities": [], "fallback_used": False}


# ─── Baseline (flag-off) ───────────────────────────────────────────

def test_baseline_returns_substring_matched_rows(mock_session_factory):
    """Without flag, only substring-matched rows are returned."""
    rows = [
        _make_row(1, "BRCA1 variant analysis", "we found 3 variants", 0.9),
        _make_row(2, "Unrelated topic", "nothing about brca", 0.8),
        _make_row(3, "Generic note", "mentions BRCA1 in body text", 0.7),
    ]
    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.return_value = rows
    out = recall_project_knowledge(
        "proj1", "BRCA1",
        session_factory=mock_session_factory,
    )
    ids = {e["id"] for e in out["entries"]}
    assert 1 in ids   # title match
    assert 3 in ids   # content match
    assert 2 not in ids  # neither
    assert out["fallback_used"] is True
    assert out["extracted_entities"] == []


def test_baseline_respects_limit(mock_session_factory):
    rows = [_make_row(i, f"BRCA1 entry {i}", relevance=1.0 - i * 0.01)
            for i in range(20)]
    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.return_value = rows
    out = recall_project_knowledge(
        "proj1", "BRCA1", session_factory=mock_session_factory, limit=5
    )
    assert len(out["entries"]) <= 5


# ─── Flag-on entity widening ──────────────────────────────────────

def test_flag_on_extracts_entities(mock_session_factory):
    """With flag set, extracted_entities populates."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.return_value = []
    out = recall_project_knowledge(
        "proj1", "BRCA1 mutations in breast cancer",
        session_factory=mock_session_factory,
    )
    cids = {e["canonical_id"] for e in out["extracted_entities"]}
    assert "BRCA1" in cids
    assert "breast_cancer" in cids


def test_flag_on_widens_via_canonical_entity(mock_session_factory):
    """Entity-widened query surfaces rows that baseline substring missed."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    # Baseline finds nothing for the literal "BRCA-1" (with hyphen)
    baseline_match = _make_row(1, "Unrelated", "nothing matching", 0.9)
    # Entity-widened search for "BRCA1" finds row 100
    entity_match = _make_row(100, "BRCA1 known fact", "important", 0.95)

    call_count = [0]
    def all_side_effect():
        call_count[0] += 1
        # First call: baseline; subsequent calls: entity widening
        return [baseline_match, entity_match] if call_count[0] >= 2 else [baseline_match]

    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.side_effect = all_side_effect

    out = recall_project_knowledge(
        "proj1", "BRCA-1 in tumors",  # hyphen → baseline substring won't match
        session_factory=mock_session_factory,
    )
    ids = {e["id"] for e in out["entries"]}
    # Entity widening should find 100 (mentions BRCA1)
    assert 100 in ids


def test_flag_off_does_not_extract_entities(mock_session_factory):
    """Without env flag, no entity extraction happens."""
    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.return_value = []
    out = recall_project_knowledge(
        "proj1", "BRCA1 mutations",
        session_factory=mock_session_factory,
    )
    assert out["extracted_entities"] == []
    assert out["fallback_used"] is True


# ─── Graceful degradation ─────────────────────────────────────────

def test_session_factory_exception_returns_empty(mock_session_factory):
    """If the session factory raises, return empty without crashing."""
    @contextmanager
    def bad_factory():
        raise RuntimeError("simulated DB error")
        yield  # unreachable
    out = recall_project_knowledge("proj1", "BRCA1", session_factory=bad_factory)
    assert out["entries"] == []


def test_entity_extractor_failure_falls_back_to_baseline(mock_session_factory, monkeypatch):
    """If entity extractor crashes, baseline rows still returned."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    baseline = _make_row(7, "BRCA1 row", relevance=0.9)
    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.return_value = [baseline]

    import backend.lib.galaxy.ai.retrievers.knowledge_recall as kr
    real_import = __builtins__["__import__"] if isinstance(__builtins__, dict) else __builtins__.__import__

    def boom_import(name, *args, **kwargs):
        if "intent_retrieval_v3.adapters.entity" in name:
            raise RuntimeError("simulated extractor crash")
        return real_import(name, *args, **kwargs)
    monkeypatch.setattr("builtins.__import__", boom_import)

    out = recall_project_knowledge(
        "proj1", "BRCA1",
        session_factory=mock_session_factory,
    )
    assert any(e["id"] == 7 for e in out["entries"])


# ─── Response shape ────────────────────────────────────────────────

def test_response_shape_invariants(mock_session_factory):
    """Every response has all three keys."""
    mock_session_factory.session.query.return_value.filter.return_value.order_by.return_value.all.return_value = []
    for q in ("BRCA1", "", "random text"):
        for flag in (None, "1"):
            if flag:
                os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = flag
            else:
                os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)
            out = recall_project_knowledge(
                "proj1", q, session_factory=mock_session_factory,
            )
            assert {"entries", "extracted_entities", "fallback_used"} <= set(out.keys())
            assert isinstance(out["entries"], list)
            assert isinstance(out["extracted_entities"], list)
            assert isinstance(out["fallback_used"], bool)
