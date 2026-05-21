"""Tests for `WiredAgenticMemoryService`.

Verifies the query-aware recall enrichment works as designed:
  - Flag-off → behavior is identical to the base AgenticMemoryService
  - Flag-on → adds canonical-entity extraction; enriched_episodes widens
    coverage beyond pure substring match

Uses mock services (no real DB write) — tests the integration logic, not the
underlying SQL.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
sys.path.insert(0, str(ROOT))

# Patch DB session before importing the module (the module sets up SQLAlchemy
# at import time; we don't need a real DB for these tests)
from backend.lib.galaxy.ai.retrievers.wired_agentic_memory import (  # noqa: E402
    WiredAgenticMemoryService,
)


@pytest.fixture
def service():
    """Return a WiredAgenticMemoryService with all underlying services mocked."""
    svc = WiredAgenticMemoryService()
    svc.users = MagicMock()
    svc.episodes = MagicMock()
    svc.procedures = MagicMock()
    return svc


@pytest.fixture(autouse=True)
def _reset_flag():
    prev = os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)
    yield
    if prev is not None:
        os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = prev
    else:
        os.environ.pop("BIOMATE_MEMORY_QUERY_ENRICH", None)


# ─── Basic shape ──────────────────────────────────────────────────────

def test_recall_for_query_returns_expected_shape(service):
    service.users.load_user_context.return_value = {"name": "test"}
    service.episodes.get_similar_episodes.return_value = []
    service.procedures.get_reliable_procedures.return_value = []
    out = service.recall_for_query("user1", "proj1", "any query")
    assert {"user_context", "extracted_entities", "extracted_tool_families",
            "relevant_episodes", "applicable_procedures", "fallback_used"} <= set(out.keys())


def test_no_project_id_returns_user_context_only(service):
    service.users.load_user_context.return_value = {"name": "test"}
    out = service.recall_for_query("user1", None, "any query")
    assert out["user_context"] == {"name": "test"}
    assert out["relevant_episodes"] == []
    assert out["applicable_procedures"] == []


# ─── Flag-off path ────────────────────────────────────────────────────

def test_flag_off_returns_baseline_episodes_only(service):
    """With flag unset, behavior matches the baseline get_similar_episodes."""
    service.users.load_user_context.return_value = {}
    baseline_eps = [{"id": 1, "user_query": "test"}]
    service.episodes.get_similar_episodes.return_value = baseline_eps
    service.procedures.get_reliable_procedures.return_value = []

    out = service.recall_for_query("user1", "proj1", "samtools sort BAM")
    assert out["fallback_used"] is True
    assert out["relevant_episodes"] == baseline_eps
    # Entity extraction did NOT fire
    assert out["extracted_entities"] == []
    # Only one call to get_similar_episodes (the baseline)
    assert service.episodes.get_similar_episodes.call_count == 1


# ─── Flag-on enrichment ───────────────────────────────────────────────

def test_flag_on_extracts_entities_from_query(service):
    """With flag set, entity extraction surfaces canonical IDs."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    # Baseline returns nothing
    service.episodes.get_similar_episodes.return_value = []
    service.procedures.get_reliable_procedures.return_value = []

    out = service.recall_for_query(
        "user1", "proj1", "BRCA1 mutations in breast cancer"
    )
    # Expect BRCA1 + breast_cancer in extracted_entities
    cids = {e["canonical_id"] for e in out["extracted_entities"]}
    assert "BRCA1" in cids
    assert "breast_cancer" in cids
    assert out["fallback_used"] is False


def test_flag_on_widens_episode_search_via_canonical_entities(service):
    """When entities are extracted, recall does ADDITIONAL searches per entity."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    # Baseline returns episode 1
    # Entity search for BRCA1 returns episode 2 (different episode!)
    service.episodes.get_similar_episodes.side_effect = lambda **kw: {
        "brca1 mutations": [{"id": 1, "user_query": "previous query"}],
        "brca1":           [{"id": 2, "user_query": "old BRCA1 work"}],
        "breast_cancer":   [{"id": 3, "user_query": "breast cancer cohort"}],
    }.get(kw.get("intent", "").lower(), [])
    service.procedures.get_reliable_procedures.return_value = []

    out = service.recall_for_query(
        "user1", "proj1", "BRCA1 mutations"
    )
    # Should have BOTH the baseline result (episode 1) AND the entity-widened
    # result (episode 2). Episode 3 is from breast_cancer which isn't in the
    # query, so it shouldn't be in extracted_entities or relevant_episodes.
    relevant_ids = {ep["id"] for ep in out["relevant_episodes"]}
    assert 1 in relevant_ids  # from baseline substring match
    assert 2 in relevant_ids  # from BRCA1 canonical match
    assert 3 not in relevant_ids  # breast_cancer NOT in query → not extracted


def test_flag_on_dedupes_episodes_across_baseline_and_entity_searches(service):
    """Same episode appearing in baseline AND entity search → returned once."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    ep = {"id": 42, "user_query": "test"}
    # Both baseline and entity search return the same episode
    service.episodes.get_similar_episodes.return_value = [ep]
    service.procedures.get_reliable_procedures.return_value = []

    out = service.recall_for_query("user1", "proj1", "BRCA1 study")
    ids = [e["id"] for e in out["relevant_episodes"]]
    assert ids.count(42) == 1  # deduped


def test_flag_on_no_entities_falls_back_to_baseline(service):
    """If extraction returns no entities, only baseline episodes appear."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    baseline = [{"id": 7, "user_query": "generic"}]
    service.episodes.get_similar_episodes.return_value = baseline
    service.procedures.get_reliable_procedures.return_value = []

    out = service.recall_for_query("user1", "proj1", "generic non-biological query text")
    assert out["extracted_entities"] == []
    assert out["relevant_episodes"] == baseline


# ─── Graceful degradation ─────────────────────────────────────────────

def test_entity_extraction_failure_does_not_break_recall(service):
    """If the entity adapter raises, recall must still return baseline."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    baseline = [{"id": 5}]
    service.episodes.get_similar_episodes.return_value = baseline
    service.procedures.get_reliable_procedures.return_value = []

    with patch(
        "sandbox.intent_retrieval_v3.adapters.entity.extract_canonical_entities",
        side_effect=RuntimeError("simulated extractor crash"),
    ):
        out = service.recall_for_query("user1", "proj1", "BRCA1 study")
    # Should still return the baseline episode without raising
    assert out["relevant_episodes"] == baseline


def test_limit_honored(service):
    """Caller's limit is respected after enrichment."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    many_eps = [{"id": i, "user_query": "x"} for i in range(20)]
    service.episodes.get_similar_episodes.return_value = many_eps
    service.procedures.get_reliable_procedures.return_value = []

    out = service.recall_for_query("user1", "proj1", "BRCA1", limit=5)
    assert len(out["relevant_episodes"]) <= 5


# ─── Procedure widening via canonical entities ──────────────────────

def test_flag_on_widens_procedure_recall_via_canonical_entities(service):
    """find_matching_procedures called once per extracted canonical entity."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    service.episodes.get_similar_episodes.return_value = []
    # Baseline reliable procedures
    service.procedures.get_reliable_procedures.return_value = [
        {"id": 100, "trigger_pattern": "default high-success"},
    ]
    # Per-entity find_matching_procedures
    service.procedures.find_matching_procedures.side_effect = lambda **kw: {
        "BRCA1":         [{"id": 200, "trigger_pattern": "BRCA1 variant calling"}],
        "breast_cancer": [{"id": 201, "trigger_pattern": "breast cancer biomarker"}],
    }.get(kw.get("trigger", ""), [])

    out = service.recall_for_query(
        "user1", "proj1", "BRCA1 mutations in breast cancer"
    )
    proc_ids = {p["id"] for p in out["applicable_procedures"]}
    # Baseline procedure (100) + per-entity procedures (200, 201)
    assert 100 in proc_ids
    assert 200 in proc_ids
    assert 201 in proc_ids
    # find_matching_procedures called once per canonical entity
    called_triggers = {
        c.kwargs.get("trigger")
        for c in service.procedures.find_matching_procedures.call_args_list
    }
    assert "BRCA1" in called_triggers
    assert "breast_cancer" in called_triggers


def test_procedure_dedup_across_baseline_and_entity_searches(service):
    """Procedure appearing in baseline AND entity search → returned once."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    service.episodes.get_similar_episodes.return_value = []
    same_proc = {"id": 42, "trigger_pattern": "x"}
    service.procedures.get_reliable_procedures.return_value = [same_proc]
    service.procedures.find_matching_procedures.return_value = [same_proc]

    out = service.recall_for_query("user1", "proj1", "BRCA1 query")
    proc_ids = [p["id"] for p in out["applicable_procedures"]]
    assert proc_ids.count(42) == 1  # deduped


def test_flag_off_uses_only_baseline_procedures(service):
    """Without flag, find_matching_procedures is NEVER called."""
    service.users.load_user_context.return_value = {}
    service.episodes.get_similar_episodes.return_value = []
    service.procedures.get_reliable_procedures.return_value = [{"id": 1}]

    service.recall_for_query("user1", "proj1", "BRCA1 query")
    service.procedures.find_matching_procedures.assert_not_called()


def test_procedure_search_failure_does_not_break_recall(service):
    """If find_matching_procedures raises, baseline procs still surface."""
    os.environ["BIOMATE_MEMORY_QUERY_ENRICH"] = "1"
    service.users.load_user_context.return_value = {}
    service.episodes.get_similar_episodes.return_value = []
    baseline = [{"id": 7}]
    service.procedures.get_reliable_procedures.return_value = baseline
    service.procedures.find_matching_procedures.side_effect = RuntimeError("boom")

    out = service.recall_for_query("user1", "proj1", "BRCA1 query")
    assert out["applicable_procedures"] == baseline
