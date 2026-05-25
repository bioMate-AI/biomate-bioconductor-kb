"""
Tests for the memory adapter — verifies that the framework generalizes
cleanly to a new domain with no special-case code.
"""
from __future__ import annotations

import pytest

from sandbox.intent_retrieval_v3.adapters.memory import (
    prioritize_memory_by_intent,
)


# ─── Happy path: confident intent promotes/injects canonical memory file ─

def test_bixbench_query_promotes_bixbench_memory():
    cands = ["random_other_memory.md", "old_session.md"]
    out = prioritize_memory_by_intent(
        "What's the bixbench status and bixbench results from v21?", cands,
    )
    # Two triggers fire: "bixbench status" + "bixbench results" + "bixbench v21"
    assert out[0] == "project_bixbench_v21.md"


def test_workflow_pricing_query():
    cands = ["foo.md"]
    out = prioritize_memory_by_intent(
        "Show me the workflow pricing table and gpu pricing infrastructure", cands,
    )
    assert out[0] == "project_workflow_pricing_table.md"


def test_regulatory_query_injects_memory():
    """Even when no memory files are in the candidate list, injects the
    canonical when confidence is high (≥2 triggers)."""
    out = prioritize_memory_by_intent(
        "What's the status of the regulatory llm v6 sft dpo checker work?", [],
    )
    assert len(out) >= 1
    assert out[0] == "project_regulatory_llm_v6.md"


def test_does_not_mutate():
    cands = ["a.md", "b.md"]
    _ = prioritize_memory_by_intent("bixbench status results", cands)
    assert cands == ["a.md", "b.md"]


# ─── Disambiguation: family_dedup vs workflow_intent results ───────────

def test_family_vs_workflow_results_disambiguated():
    """Query 'dedup lift numbers' (family) must NOT pull the workflow doc."""
    cands = ["nothing.md"]
    out = prioritize_memory_by_intent(
        "show me the family dedup results, wrapper canonical results", cands,
    )
    # Should fire family_dedup_results, not workflow_intent_lift_results
    # (workflow is disqualified_if_present for family_dedup_results)
    assert out[0] == "20260518_PHASE1_AB_RESULTS_AND_DECISION.md"


def test_ambiguous_query_passes_through():
    """When multiple intents fire ambiguously, leave order alone."""
    cands = ["x.md", "y.md"]
    out = prioritize_memory_by_intent(
        "tell me about results", cands,  # too generic to fire any single intent confidently
    )
    assert [c for c in out] == ["x.md", "y.md"]


# ─── Dict-style candidates work too ─────────────────────────────────────

def test_dict_candidates_supported():
    cands = [{"file": "foo.md", "score": 0.5}, {"file": "bar.md", "score": 0.3}]
    # Query has THREE trigger matches: "bixbench status", "bixbench results", "bixbench v21"
    out = prioritize_memory_by_intent(
        "tell me the bixbench status, bixbench results, and bixbench v21 score", cands,
    )
    assert out[0]["file"] == "project_bixbench_v21.md"


# ─── Inject mode confidence gate (single weak trigger doesn't inject) ──

def test_single_trigger_does_not_inject():
    """Confidence gate: ≥ 2 trigger matches required to inject. A single
    weak word match should not pull a memory file in unsolicited."""
    cands = ["x.md"]
    out = prioritize_memory_by_intent("show me memory", cands)
    # No intent has "memory" alone as a single trigger that fires reliably,
    # so should pass through.
    assert out == ["x.md"]
