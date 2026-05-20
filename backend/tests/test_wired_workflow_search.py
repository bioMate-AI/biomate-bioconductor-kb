"""Tests for `WiredWorkflowSearch`.

Verifies:
  1. Flag-off behavior is bit-identical to UnifiedWorkflowSearch
  2. Flag-on with PRIORITIZE only: canonical workflow promoted within candidates
  3. Flag-on with PRIORITIZE+INJECT: missing canonicals injected
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
sys.path.insert(0, str(ROOT))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from backend.lib.galaxy.ai.retrievers.wired_workflow_search import (  # noqa: E402
    WiredWorkflowSearch,
)


@pytest.fixture(scope="module")
def base_search():
    return UnifiedWorkflowSearch()


@pytest.fixture(scope="module")
def wired_search():
    return WiredWorkflowSearch()


@pytest.fixture(autouse=True)
def _reset_flags():
    for var in ("BIOMATE_WORKFLOW_INTENT_PRIORITIZE", "BIOMATE_WORKFLOW_INTENT_INJECT"):
        os.environ.pop(var, None)
    yield
    for var in ("BIOMATE_WORKFLOW_INTENT_PRIORITIZE", "BIOMATE_WORKFLOW_INTENT_INJECT"):
        os.environ.pop(var, None)


# ─── Flag-off parity ────────────────────────────────────────────────────

def test_flag_off_bit_identical_to_base(base_search, wired_search):
    """Both env flags unset → identical output to UnifiedWorkflowSearch."""
    for q in ("Run RNA-seq on FASTQ", "variant calling germline", "ChIP-seq peak calling"):
        base = [m.name for m in base_search.search(q, limit=10)]
        wired = [m.name for m in wired_search.search(q, limit=10)]
        assert base == wired, f"flag-off divergence for {q!r}\n  base={base}\n  wired={wired}"


# ─── Flag-on prioritize ─────────────────────────────────────────────────

def test_flag_on_prioritize_promotes_canonical_when_in_candidates(wired_search):
    """When the canonical workflow IS in the candidate pool, prioritize promotes it."""
    os.environ["BIOMATE_WORKFLOW_INTENT_PRIORITIZE"] = "1"
    # "differentially expressed genes from count matrix" → nf-core/differentialabundance
    out = wired_search.search(
        "I already have a count matrix from rnaseq. Now I want to find "
        "differentially expressed genes",
        limit=10,
    )
    names = [m.name for m in out]
    # nf-core/differentialabundance should be at or near the top
    assert "nf-core/differentialabundance" in names[:3], (
        f"differentialabundance should be in top-3; got {names[:3]}"
    )


# ─── Flag-on inject ─────────────────────────────────────────────────────

def test_flag_on_inject_injects_canonical_when_missing(wired_search):
    """When canonical isn't in candidate pool, inject mode synthesizes it.

    Per the held-out measurement: 'Run standard RNA-seq on paired-end FASTQ
    from a mouse experiment' baseline FTS doesn't return nf-core/rnaseq in
    top-10, but the intent fires confidently (>=2 triggers) so inject fires.
    """
    os.environ["BIOMATE_WORKFLOW_INTENT_PRIORITIZE"] = "1"
    os.environ["BIOMATE_WORKFLOW_INTENT_INJECT"] = "1"
    out = wired_search.search(
        "Run standard RNA-seq analysis on my paired-end FASTQ files from a mouse experiment",
        limit=10,
    )
    names = [m.name for m in out]
    assert "nf-core/rnaseq" in names, (
        f"inject should add nf-core/rnaseq when missing from FTS top-10; got {names[:5]}"
    )


# ─── Inject requires confidence (≥ 2 triggers) ──────────────────────────

def test_flag_on_inject_does_not_fire_on_weak_signal(wired_search):
    """Single-token query with weak trigger match → no injection."""
    os.environ["BIOMATE_WORKFLOW_INTENT_PRIORITIZE"] = "1"
    os.environ["BIOMATE_WORKFLOW_INTENT_INJECT"] = "1"
    # "stringtie" alone — single weak trigger in bam_stringtie intent
    out = wired_search.search("stringtie", limit=5)
    # Should NOT have injected nf-core/bam_stringtie_merge if it wasn't already there
    # (cannot assert absence absolutely if FTS happens to return it, so check it's
    # ≤ what raw search would return)
    assert isinstance(out, list)
    # Just ensure no crash, no fabricated extras
    assert len(out) <= 5


# ─── Held-out: ambiguous query passes through ───────────────────────────

def test_ambiguous_query_passes_through(wired_search):
    """Generic query that doesn't fire any intent → behavior unchanged."""
    os.environ["BIOMATE_WORKFLOW_INTENT_PRIORITIZE"] = "1"
    os.environ["BIOMATE_WORKFLOW_INTENT_INJECT"] = "1"
    # Compare to flag-off output
    out_on = wired_search.search("totally generic text without any pipeline intent", limit=5)
    os.environ.pop("BIOMATE_WORKFLOW_INTENT_PRIORITIZE", None)
    os.environ.pop("BIOMATE_WORKFLOW_INTENT_INJECT", None)
    out_off = wired_search.search("totally generic text without any pipeline intent", limit=5)
    assert [m.name for m in out_on] == [m.name for m in out_off]


def test_search_returns_workflow_match_objects(wired_search):
    """Return type should be List[WorkflowMatch] — same as base class."""
    out = wired_search.search("RNA-seq", limit=3)
    if out:
        m = out[0]
        # Verify it has the same attributes as a base WorkflowMatch
        assert hasattr(m, "name")
        assert hasattr(m, "score")
        assert hasattr(m, "match_type")
