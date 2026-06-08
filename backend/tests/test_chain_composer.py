"""Unit + golden-query tests for galaxy.ai.chain_composer.

Tests run against the canonical pattern library doc and the live
backend/database/galaxy_ai_tools.db (via symlink in the worktree). Golden
queries pin retrieval + surfacing mode behavior so prompt/library tweaks
that regress these cases are caught immediately.
"""

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "lib" / "galaxy" / "ai"))

from chain_composer import (  # noqa: E402
    ConfidenceSignals,
    Pattern,
    choose_surfacing_mode,
    compose_chain,
    load_patterns,
    retrieve_patterns,
    score_confidence,
)


# ---------- pattern_loader ----------

def test_pattern_loader_returns_canonical_set():
    """v1 library has 12 entries; deprecated comparative_benchmarking excluded by default."""
    ps = load_patterns()
    assert len(ps) == 11, f"expected 11 active patterns, got {len(ps)}"
    names = {p.name for p in ps}
    assert "sequential_omics_pipeline" in names
    assert "multi_omics_integration" in names
    assert "comparative_benchmarking" not in names, "deprecated entry must be excluded"


def test_pattern_loader_include_deprecated_flag():
    all_ps = load_patterns(include_deprecated=True)
    active = load_patterns(include_deprecated=False)
    assert len(all_ps) == len(active) + 1


def test_pattern_fields_populated():
    ps = load_patterns()
    p = next(p for p in ps if p.name == "multi_omics_integration")
    assert "modalit" in p.when.lower()  # "modalities"
    assert "MOFA" in p.shape or "integration" in p.shape.lower()
    assert "Argelaguet" in p.reference


# ---------- retrieval ----------

def test_retrieval_picks_multi_omics_for_multi_modal_query():
    scored = retrieve_patterns(
        "I want to combine RNA-seq and ATAC-seq data into a joint model",
        top_k=3,
    )
    names = [sp.pattern.name for sp in scored]
    assert "multi_omics_integration" in names, f"expected multi_omics_integration in {names}"


def test_retrieval_picks_consensus_for_robustness_query():
    scored = retrieve_patterns(
        "differential expression with DESeq2 edgeR and limma to be defensible",
        top_k=3,
    )
    names = [sp.pattern.name for sp in scored]
    assert "multi_method_consensus" in names, f"expected multi_method_consensus in {names}"


def test_retrieval_picks_filter_cascade_for_variant_priority():
    scored = retrieve_patterns(
        "variant prioritization by frequency then damaging prediction then panel",
        top_k=3,
    )
    names = [sp.pattern.name for sp in scored]
    assert "filter_cascade" in names, f"expected filter_cascade in {names}"


def test_retrieval_empty_query_returns_empty():
    assert retrieve_patterns("") == []


# ---------- confidence ----------

def test_confidence_zero_signals_returns_reactive():
    """Default signals (no curated, no pattern, no specificity) → reactive.
    Note: downstream_determinism defaults to 0.5 (neutral) — so the
    confidence is the baseline contribution from that signal alone."""
    r = score_confidence(ConfidenceSignals())
    assert r.confidence < 0.45, f"baseline confidence must be sub-stepwise, got {r.confidence}"
    assert r.mode == "reactive"


def test_confidence_zeroed_determinism_yields_zero():
    """Explicit zero across all signals → zero confidence."""
    r = score_confidence(ConfidenceSignals(downstream_determinism=0.0))
    assert r.confidence == 0.0
    assert r.mode == "reactive"


def test_confidence_all_max_signals_returns_upfront():
    r = score_confidence(ConfidenceSignals(
        curated_chain_score=1.0,
        pattern_match_score=1.0,
        query_specificity=1.0,
        downstream_determinism=1.0,
    ))
    assert r.confidence == 1.0
    assert r.mode == "upfront"


def test_confidence_user_split_step_signal_drops_mode():
    """A 'let's start with X' query should NOT surface a full chain upfront."""
    high_base = score_confidence(ConfidenceSignals(
        curated_chain_score=0.9,
        pattern_match_score=0.8,
        query_specificity=0.7,
        downstream_determinism=0.8,
    ))
    assert high_base.mode == "upfront"

    with_split_signal = score_confidence(ConfidenceSignals(
        curated_chain_score=0.9,
        pattern_match_score=0.8,
        query_specificity=0.7,
        downstream_determinism=0.8,
        user_signal=-0.3,  # "let's start with…"
    ))
    # Same chain quality, but user asked for stepwise — surfacing must reflect.
    assert with_split_signal.confidence < high_base.confidence
    assert with_split_signal.mode in {"stepwise", "reactive"}


def test_confidence_signals_clamped_to_valid_range():
    """Wild inputs must not blow up the score."""
    r = score_confidence(ConfidenceSignals(
        curated_chain_score=99.0,
        pattern_match_score=-50.0,
        user_signal=99.0,
    ))
    assert 0.0 <= r.confidence <= 1.0


def test_choose_surfacing_mode_thresholds():
    assert choose_surfacing_mode(0.9) == "upfront"
    assert choose_surfacing_mode(0.5) == "stepwise"
    assert choose_surfacing_mode(0.2) == "reactive"


# ---------- composer end-to-end ----------

def test_compose_canonical_rnaseq_query_hits_curated_upfront():
    """Bulk RNA-seq DE+enrichment is the most curated query we have.
    Must surface upfront from the curated catalog."""
    r = compose_chain(
        "bulk RNA-seq differential expression analysis on human samples with enrichment"
    )
    assert r.surfacing_mode == "upfront"
    assert r.source == "curated_passthrough"
    assert any("rnaseq" in n for n in r.exemplars_used)
    assert r.steps, "expected non-empty steps from curated chain"


def test_compose_let_us_start_query_drops_to_reactive_or_stepwise():
    """User signal 'let's start with X' must demote surfacing."""
    r = compose_chain("let's start with peak calling on this CUT&Tag data")
    assert r.surfacing_mode in {"reactive", "stepwise"}
    assert r.signals["user_signal"] < 0


def test_compose_full_analysis_query_increases_confidence():
    """User signal 'do the whole analysis' must boost surfacing."""
    r = compose_chain(
        "do the whole rare disease workup including WGS and RNA-seq for trio analysis"
    )
    assert r.surfacing_mode == "upfront"
    assert r.signals["user_signal"] > 0


def test_compose_low_specificity_query_does_not_explode():
    """Vague queries get reactive mode, not crash."""
    r = compose_chain("help me with analysis")
    assert 0.0 <= r.confidence <= 1.0
    assert r.surfacing_mode in {"reactive", "stepwise", "upfront"}


def test_compose_llm_stub_path_records_source():
    """When LLM returns valid JSON, the composed chain must report source='llm'."""
    fake_llm_json = """
    {
      "steps": [
        {"order": 1, "workflow_name": "nf-core/rnaseq", "role": "qc", "rationale": "ingest fastq"},
        {"order": 2, "workflow_name": "nf-core/differentialabundance", "role": "de", "rationale": "deseq2"}
      ],
      "edges": [{"from_step": 1, "to_step": 2, "via": "counts_matrix"}],
      "rationale": "sequential_omics_pipeline + ensemble_annotation"
    }
    """
    r = compose_chain(
        "bulk RNA-seq DE",
        llm=lambda prompt: fake_llm_json,
    )
    assert r.source == "llm"
    assert len(r.steps) == 2
    assert r.edges[0].via == "counts_matrix"
    # Patterns and exemplars still populated from retrieval.
    assert r.patterns_used
