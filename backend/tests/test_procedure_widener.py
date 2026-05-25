"""Tests for `procedure_widener.widen_procedures_by_entities`.

The procedure widening lives in a standalone module so it doesn't collide
with parallel-session edits to `wired_agentic_memory.py`. Tests are also
in a standalone file for the same reason.
"""
from __future__ import annotations

import os
from unittest.mock import MagicMock

import pytest

from backend.lib.galaxy.ai.retrievers.procedure_widener import (
    widen_procedures_by_entities,
)


@pytest.fixture
def procs_service():
    """Mock ProceduralMemoryService."""
    return MagicMock()


@pytest.fixture(autouse=True)
def _reset_env():
    prev = os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)
    yield
    if prev is not None:
        os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = prev
    else:
        os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)


# ─── Flag-off behavior ──────────────────────────────────────────────

def test_flag_off_returns_baseline_only(procs_service):
    baseline = [{"id": 1, "trigger_pattern": "x"}]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "BRCA1 mutations",
        baseline_procedures=baseline,
    )
    assert out["applicable_procedures"] == baseline
    assert out["extracted_entities"] == []
    # Critical: find_matching_procedures was NOT called
    procs_service.find_matching_procedures.assert_not_called()


def test_flag_off_with_empty_baseline_returns_empty(procs_service):
    out = widen_procedures_by_entities(procs_service, "proj1", "BRCA1")
    assert out["applicable_procedures"] == []


# ─── Edge cases (return baseline) ──────────────────────────────────

def test_no_project_id_returns_baseline(procs_service):
    """Without a project_id, widening cannot apply — return baseline."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    baseline = [{"id": 1}]
    out = widen_procedures_by_entities(
        procs_service, None, "BRCA1 mutations",
        baseline_procedures=baseline,
    )
    assert out["applicable_procedures"] == baseline
    procs_service.find_matching_procedures.assert_not_called()


def test_empty_query_returns_baseline(procs_service):
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    baseline = [{"id": 1}]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "", baseline_procedures=baseline,
    )
    assert out["applicable_procedures"] == baseline
    procs_service.find_matching_procedures.assert_not_called()


# ─── Flag-on widening ──────────────────────────────────────────────

def test_flag_on_calls_find_matching_per_canonical_entity(procs_service):
    """find_matching_procedures called once per extracted canonical."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    procs_service.find_matching_procedures.side_effect = lambda **kw: {
        "BRCA1":         [{"id": 200, "trigger_pattern": "BRCA1 variant"}],
        "breast_cancer": [{"id": 201, "trigger_pattern": "breast cancer"}],
    }.get(kw.get("trigger"), [])

    baseline = [{"id": 100, "trigger_pattern": "default"}]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "BRCA1 mutations in breast cancer",
        baseline_procedures=baseline,
    )
    proc_ids = {p["id"] for p in out["applicable_procedures"]}
    assert 100 in proc_ids   # baseline preserved
    assert 200 in proc_ids   # BRCA1 widening
    assert 201 in proc_ids   # breast_cancer widening
    # Verify the service was called for both canonical entities
    triggers = {c.kwargs.get("trigger")
                for c in procs_service.find_matching_procedures.call_args_list}
    assert "BRCA1" in triggers
    assert "breast_cancer" in triggers


def test_flag_on_dedup_across_baseline_and_widening(procs_service):
    """Procedure appearing in baseline AND entity-search → returned once."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    same_proc = {"id": 42, "trigger_pattern": "shared"}
    procs_service.find_matching_procedures.return_value = [same_proc]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "BRCA1 study",
        baseline_procedures=[same_proc],
    )
    ids = [p["id"] for p in out["applicable_procedures"]]
    assert ids.count(42) == 1


def test_flag_on_no_entities_returns_baseline(procs_service):
    """Query with no recognizable canonical entities → return baseline + skip widening."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    baseline = [{"id": 7}]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "generic non-biological query text",
        baseline_procedures=baseline,
    )
    assert out["applicable_procedures"] == baseline
    assert out["extracted_entities"] == []


# ─── Graceful degradation ──────────────────────────────────────────

def test_service_exception_does_not_break_recall(procs_service):
    """If find_matching_procedures raises for one entity, others still work."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    procs_service.find_matching_procedures.side_effect = lambda **kw: (
        [{"id": 200}] if kw.get("trigger") == "BRCA1"
        else (_ for _ in ()).throw(RuntimeError("boom"))
    )
    baseline = [{"id": 7}]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "BRCA1 mutations in breast cancer",
        baseline_procedures=baseline,
    )
    proc_ids = {p["id"] for p in out["applicable_procedures"]}
    # Baseline + BRCA1 widening preserved; breast_cancer raise skipped silently
    assert 7 in proc_ids
    assert 200 in proc_ids


def test_limit_honored(procs_service):
    """Caller's limit is respected after widening."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    procs_service.find_matching_procedures.return_value = [
        {"id": i} for i in range(20)
    ]
    out = widen_procedures_by_entities(
        procs_service, "proj1", "BRCA1", baseline_procedures=[], limit=5,
    )
    assert len(out["applicable_procedures"]) <= 5


# ─── Response shape ────────────────────────────────────────────────

def test_response_shape(procs_service):
    """Every response has both keys, applicable_procedures and extracted_entities."""
    for q in ("", "BRCA1", "generic text"):
        for flag in (None, "1"):
            os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)
            if flag:
                os.environ[flag] = flag if flag != "1" else "1"
            os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = flag or ""
            procs_service.find_matching_procedures.return_value = []
            out = widen_procedures_by_entities(
                procs_service, "proj1", q, baseline_procedures=[{"id": 1}]
            )
            assert "applicable_procedures" in out
            assert "extracted_entities" in out
