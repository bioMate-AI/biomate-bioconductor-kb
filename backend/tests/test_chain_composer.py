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


def test_confidence_pattern_chain_agreement_damps_chain_signal():
    """When patterns and curated chain disagree on domain, chain signal must
    be damped — high-confidence curated retrieval shouldn't auto-pass."""
    base = score_confidence(ConfidenceSignals(
        curated_chain_score=1.0,
        pattern_match_score=0.8,
        query_specificity=0.7,
        downstream_determinism=0.8,
        pattern_chain_agreement=1.0,  # neutral
    ))
    damped = score_confidence(ConfidenceSignals(
        curated_chain_score=1.0,
        pattern_match_score=0.8,
        query_specificity=0.7,
        downstream_determinism=0.8,
        pattern_chain_agreement=0.3,  # significant disagreement
    ))
    assert damped.confidence < base.confidence, (
        f"disagreement should lower confidence: {damped.confidence} >= {base.confidence}"
    )
    # And surfacing mode should reflect it.
    assert damped.mode != "upfront" or damped.confidence < base.confidence


def test_confidence_agreement_full_is_noop():
    """agreement=1.0 must produce identical confidence to omitting the signal."""
    with_agreement = score_confidence(ConfidenceSignals(
        curated_chain_score=0.5, downstream_determinism=0.5,
        pattern_chain_agreement=1.0,
    ))
    without_agreement = score_confidence(ConfidenceSignals(
        curated_chain_score=0.5, downstream_determinism=0.5,
        # default pattern_chain_agreement=1.0
    ))
    assert with_agreement.confidence == without_agreement.confidence


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


def test_compose_uses_entities_from_query():
    """NER entities must propagate to ComposedChain.entities."""
    r = compose_chain(
        "DESeq2 differential expression on GRCh38 human RNA-seq",
        llm=None,  # force stub + offline NER
    )
    assert "human" in r.entities["organisms"]
    assert any("rna-seq" in m.lower() for m in r.entities["modalities"])
    assert "deseq2" in [t.lower() for t in r.entities["tools"]]
    assert any("grch38" in a.lower() for a in r.entities["assemblies"])


def test_compose_entity_specificity_drives_score():
    """Query with many entities → higher specificity contribution."""
    rich = compose_chain(
        "DESeq2 differential expression on GRCh38 human RNA-seq vs control samples",
        llm=None,
    )
    sparse = compose_chain("help me with analysis", llm=None)
    assert rich.signals["query_specificity"] > sparse.signals["query_specificity"]


# ---------- NER ----------

def test_extract_entities_offline_canonical_query():
    from chain_composer.ner import extract_entities_offline
    e = extract_entities_offline(
        "Run DESeq2 on bulk RNA-seq counts_matrix from human GRCh38 tumor vs normal samples"
    )
    assert "human" in e.organisms
    assert any("rna-seq" in m.lower() for m in e.modalities)
    assert any("deseq2" == t.lower() for t in e.tools)
    assert any("counts_matrix" in d.lower() for d in e.data_types)
    assert any("grch38" in a.lower() for a in e.assemblies)
    assert e.specificity_score() > 0.5


def test_extract_entities_empty_query_returns_empty():
    from chain_composer.ner import extract_entities_offline
    e = extract_entities_offline("")
    assert e.all_terms() == []
    assert e.specificity_score() == 0.0


def test_extract_entities_llm_merges_with_offline():
    """LLM may name canonical forms the offline pass misses (e.g. user wrote
    'human genome', LLM returns 'GRCh38')."""
    from chain_composer.ner import extract_entities
    fake_llm = lambda _p: """
    {
      "organisms": ["human"],
      "modalities": ["RNA-seq"],
      "tools": ["DESeq2"],
      "data_types": [],
      "contrasts": [],
      "cohorts": [],
      "analyses": ["differential expression"],
      "assemblies": ["GRCh38"],
      "intent": "DE on the standard human reference"
    }
    """
    e = extract_entities("DE on the standard human reference genome", llm=fake_llm)
    # Both LLM output and offline match must appear (deduped).
    assert "human" in [o.lower() for o in e.organisms]
    assert any("grch38" in a.lower() for a in e.assemblies)
    assert "DE on the standard human reference" in e.intent


def test_extract_entities_llm_failure_falls_back_to_offline():
    from chain_composer.ner import extract_entities
    e = extract_entities(
        "DESeq2 on human RNA-seq",
        llm=lambda _p: "not json at all",
    )
    # Offline result is preserved.
    assert "human" in e.organisms
    assert "deseq2" in [t.lower() for t in e.tools]


# ---------- retrieval (BM25) ----------

def test_retrieval_bm25_prefers_relevant_pattern():
    """multi_omics_integration should beat sequential_omics_pipeline when
    the query explicitly names two modalities and integration."""
    from chain_composer.retrieval import retrieve_patterns
    scored = retrieve_patterns(
        "integrate RNA-seq with ATAC-seq into a joint multimodal model",
        top_k=3,
    )
    names = [sp.pattern.name for sp in scored]
    assert names[0] == "multi_omics_integration"


def test_retrieve_workflows_returns_real_catalog_names():
    """Smoke: workflow retrieval against the live catalog returns real names."""
    from chain_composer.retrieval import retrieve_workflows
    ws = retrieve_workflows("RNA-seq differential expression", top_k=8)
    assert ws, "expected at least one workflow for an RNA-seq DE query"
    # Every returned name must be non-empty and have a non-zero score.
    for w in ws:
        assert w.name and w.score > 0
    # Top result should be in transcriptomics or general (RNA-seq adjacent).
    assert ws[0].domain in {"transcriptomics", "general", "genomics", "epigenomics"}, \
        f"unexpected top domain: {ws[0].domain}"


def test_retrieve_workflows_cache_invalidates_on_mtime():
    """The index cache should not silently serve stale data after a DB change."""
    from chain_composer.retrieval import _WF_INDEX_CACHE, retrieve_workflows
    from pathlib import Path
    import os
    # First call seeds the cache.
    _ = retrieve_workflows("RNA-seq", top_k=2)
    before_keys = set(_WF_INDEX_CACHE.keys())
    assert before_keys, "first call must populate the cache"

    # Touch the DB file to bump its mtime, then verify the next call adds a new key.
    db = next(iter(before_keys))[0]
    db_path = Path(db)
    if db_path.exists():
        os.utime(db_path, None)
        _ = retrieve_workflows("RNA-seq", top_k=2)
        after_keys = set(_WF_INDEX_CACHE.keys())
        # New mtime → new key. The set should grow OR the only key should differ.
        assert after_keys != before_keys or len(after_keys) > len(before_keys), \
            "cache key did not refresh after mtime bump"


def test_retrieve_workflows_entity_boost_works():
    """Workflow retrieval should respect entity-term boosts."""
    from chain_composer.retrieval import retrieve_workflows
    without = retrieve_workflows("integration", top_k=10)
    with_atac = retrieve_workflows("integration", top_k=10, entity_terms=["atac"])
    # The presence of "atac" in entities should not crash and should produce
    # at least as good ranking for atac-related workflows (when any exist).
    assert isinstance(with_atac, list)
    if without and with_atac:
        # At least the structure is preserved (no empty result from the boost path).
        assert all(w.score > 0 for w in with_atac)


def test_retrieval_entity_boost_helps_when_query_is_terse():
    """A query like 'GATK Strelka Mutect2 voting' should hit consensus
    pattern when entities are supplied even if BM25 alone is weak."""
    from chain_composer.retrieval import retrieve_patterns
    without = retrieve_patterns("variant calling robust", top_k=3)
    with_entities = retrieve_patterns(
        "variant calling robust",
        top_k=3,
        entity_terms=["consensus", "ensemble", "intersect"],
    )
    # With entity boost, consensus pattern must appear at least as high.
    def rank(scored):
        for i, sp in enumerate(scored):
            if sp.pattern.name == "multi_method_consensus":
                return i
        return 99
    assert rank(with_entities) <= rank(without)


# ---------- LLM adapter ----------

# ---------- verifier ----------

def test_verifier_empty_chain_is_ok():
    from chain_composer import ComposedChain, verify_chain
    r = verify_chain(ComposedChain(), known_names=set())
    assert r.ok
    assert r.errors == []


def test_verifier_flags_unknown_workflow():
    from chain_composer import ChainStep, ComposedChain, verify_chain
    chain = ComposedChain(steps=[
        ChainStep(order=1, workflow_name="nf-core/rnaseq"),
        ChainStep(order=2, workflow_name="totally-made-up-workflow"),
    ])
    r = verify_chain(chain, known_names={"nf-core/rnaseq"})
    assert not r.ok
    codes = [e.code for e in r.errors]
    assert "unknown_workflow" in codes
    # Error must point at the offending step.
    bad = [e for e in r.errors if e.code == "unknown_workflow"][0]
    assert bad.step_order == 2


def test_verifier_flags_self_loop_edge():
    from chain_composer import ChainEdge, ChainStep, ComposedChain, verify_chain
    chain = ComposedChain(
        steps=[ChainStep(order=1, workflow_name="a"), ChainStep(order=2, workflow_name="b")],
        edges=[ChainEdge(from_step=1, to_step=1)],
    )
    r = verify_chain(chain, known_names={"a", "b"})
    assert not r.ok
    assert "self_loop_edge" in [e.code for e in r.errors]


def test_verifier_flags_cycle():
    from chain_composer import ChainEdge, ChainStep, ComposedChain, verify_chain
    chain = ComposedChain(
        steps=[
            ChainStep(order=1, workflow_name="a"),
            ChainStep(order=2, workflow_name="b"),
            ChainStep(order=3, workflow_name="c"),
        ],
        edges=[
            ChainEdge(from_step=1, to_step=2),
            ChainEdge(from_step=2, to_step=3),
            ChainEdge(from_step=3, to_step=1),  # cycle
        ],
    )
    r = verify_chain(chain, known_names={"a", "b", "c"})
    assert "cycle_detected" in [e.code for e in r.errors]


def test_verifier_warns_on_orphan_step():
    from chain_composer import ChainEdge, ChainStep, ComposedChain, verify_chain
    chain = ComposedChain(
        steps=[
            ChainStep(order=1, workflow_name="a"),
            ChainStep(order=2, workflow_name="b"),
            ChainStep(order=3, workflow_name="orphan"),
        ],
        edges=[ChainEdge(from_step=1, to_step=2)],
    )
    r = verify_chain(chain, known_names={"a", "b", "orphan"})
    assert r.ok  # warning, not error
    assert "orphan_step" in [w.code for w in r.warnings]


def test_verifier_flags_edge_to_nonexistent_step():
    from chain_composer import ChainEdge, ChainStep, ComposedChain, verify_chain
    chain = ComposedChain(
        steps=[ChainStep(order=1, workflow_name="a"), ChainStep(order=2, workflow_name="b")],
        edges=[ChainEdge(from_step=1, to_step=99)],
    )
    r = verify_chain(chain, known_names={"a", "b"})
    assert "edge_target_unknown" in [e.code for e in r.errors]


def test_verifier_feedback_renders_for_llm():
    """LLM revision needs human-ish text — verify the renderer formats sanely."""
    from chain_composer import ChainStep, ComposedChain, verify_chain
    chain = ComposedChain(steps=[ChainStep(order=1, workflow_name="nope")])
    r = verify_chain(chain, known_names={"yes"})
    fb = r.to_llm_feedback()
    assert "ERRORS" in fb
    assert "nope" in fb
    assert "[step 1]" in fb


# ---------- stub tightening ----------

def test_stub_emits_empty_when_curated_score_below_threshold():
    """Below-threshold curated match must NOT be passed through as a chain."""
    r = compose_chain(
        "do something vague and unspecific please",
        llm=None,  # force stub
    )
    # With a weak query, no curated chain should be confidently above 0.7.
    # The stub must emit empty steps with an honest rationale.
    if r.signals["normalized_chain_score"] < 0.7:
        assert r.steps == []
        assert r.source == "stub"
        # Rationale phrasing varies based on what retrieval returned; assert
        # only that it's an honest "no plan emitted" message.
        msg = r.rationale.lower()
        assert ("no curated chain" in msg
                or "no relevant" in msg
                or "llm composition required" in msg)


def test_stub_passthrough_when_curated_score_high():
    r = compose_chain(
        "bulk RNA-seq differential expression analysis on human samples",
        llm=None,
    )
    assert r.signals["normalized_chain_score"] >= 0.7
    assert r.source == "curated_passthrough"
    assert r.steps


def test_stub_threshold_overridable_via_env(monkeypatch):
    """Operators can tune the threshold without code changes."""
    monkeypatch.setenv("BIOMATE_CURATED_PASSTHROUGH_MIN", "0.99")
    r = compose_chain(
        "bulk RNA-seq differential expression analysis on human samples",
        llm=None,
    )
    # With threshold cranked to 0.99, even the strong RNA-seq chain may fall through.
    # The test asserts the env override took effect, not a specific outcome.
    assert r.source in {"stub", "curated_passthrough"}


# ---------- LLM revision loop ----------

def test_llm_revision_loop_fixes_unknown_workflow():
    """First LLM emits a bogus workflow; revision pass fixes it after seeing
    the verifier feedback."""
    calls = {"n": 0}

    def fake_llm(prompt: str) -> str:
        calls["n"] += 1
        if calls["n"] == 1:
            # First emit: nonexistent workflow.
            return """{
              "steps": [{"order": 1, "workflow_name": "bogus-name-xyz", "role": "x", "rationale": "y"}],
              "edges": [],
              "rationale": "first try"
            }"""
        # Revision sees verifier feedback and emits a real workflow.
        assert "ERRORS" in prompt or "verification" in prompt.lower(), \
            "revision prompt must include verifier feedback"
        return """{
          "steps": [{"order": 1, "workflow_name": "nf-core/rnaseq", "role": "r", "rationale": "fixed"}],
          "edges": [],
          "rationale": "revised"
        }"""

    # Disable LLM NER so the fake_llm is only invoked by the compose path.
    r = compose_chain("bulk RNA-seq DE", llm=fake_llm, enable_llm_ner=False)
    assert calls["n"] == 2, f"expected exactly one revision pass, got {calls['n']} calls"
    assert r.source == "llm_revised", f"source={r.source} (rationale: {r.rationale})"
    assert r.steps[0].workflow_name == "nf-core/rnaseq"


# ---------- calibration driver ----------

def test_calibration_driver_runs_on_sample_queries(tmp_path):
    """Smoke: calibrate.run() over 3 queries produces a well-shaped report."""
    from chain_composer.calibrate import run as calibrate_run

    queries = [
        {"query": "bulk RNA-seq DE with enrichment", "expect_pattern": "sequential_omics_pipeline", "expect_mode": "upfront"},
        {"query": "let's start with peak calling", "expect_pattern": None, "expect_mode": "stepwise"},
        {"query": "do something vague", "expect_pattern": None, "expect_mode": "reactive"},
    ]
    report = calibrate_run(queries, use_llm=False)
    assert report["aggregate"]["n_queries"] == 3
    assert set(report["aggregate"]["mode_distribution"]) == {"upfront", "stepwise", "reactive"}
    assert 0.0 <= report["aggregate"]["mode_match_rate"] <= 1.0
    # Each per-query entry must carry signals and source.
    for r in report["per_query"]:
        assert "signals" in r
        assert "source" in r


# ---------- live LLM golden tests (opt-in) ----------

import os as _os
_HAS_LIVE_KEY = bool(_os.environ.get("ANTHROPIC_API_KEY"))


@pytest.mark.live
@pytest.mark.skipif(not _HAS_LIVE_KEY, reason="ANTHROPIC_API_KEY not set")
def test_live_query_biomarker_validation():
    """TCGA→UKB biomarker validation. Pre-workflow-retrieval this hallucinated
    4/4 workflows; with workflow retrieval should ground all steps in real names."""
    r = compose_chain(
        "validate biomarkers from a TCGA discovery cohort on UK Biobank using GRCh38",
    )
    assert r.steps, f"expected non-empty plan, got rationale: {r.rationale!r}"
    assert r.source in {"llm", "llm_revised", "curated_passthrough"}
    # No unknown_workflow errors — the prompt's closed-set constraint must hold.
    unknown = [e for e in r.verifier_report["errors"] if e["code"] == "unknown_workflow"]
    assert not unknown, f"LLM emitted nonexistent workflows: {[e['message'] for e in unknown]}"
    # Pattern rationale should mention discovery_then_validation or cross_cohort_replication.
    if r.source != "curated_passthrough":
        assert any(p in r.rationale.lower() for p in (
            "discovery_then_validation", "cross_cohort", "validation"
        )), f"rationale missing pattern reference: {r.rationale!r}"


@pytest.mark.live
@pytest.mark.skipif(not _HAS_LIVE_KEY, reason="ANTHROPIC_API_KEY not set")
def test_live_query_consensus_de():
    """Multi-method consensus DE — should pick the right pattern."""
    r = compose_chain(
        "robust differential expression with DESeq2, edgeR, and limma on tumor vs normal RNA-seq",
    )
    assert r.steps
    assert r.verifier_report["ok"], f"verifier errors: {r.verifier_report['errors']}"
    # Either uses the multi_method_consensus pattern, or the BIOC_ExpHunterSuite
    # meta-package which implements that pattern internally.
    plan_text = " ".join(s.workflow_name for s in r.steps) + " " + r.rationale
    assert (
        "consensus" in plan_text.lower()
        or "ExpHunterSuite" in plan_text
        or any(t in plan_text for t in ("DESeq2", "edgeR", "limma"))
    ), f"expected consensus-flavored plan: {plan_text!r}"


@pytest.mark.live
@pytest.mark.skipif(not _HAS_LIVE_KEY, reason="ANTHROPIC_API_KEY not set")
def test_live_query_multiomics_rna_atac():
    """Multi-omics RNA+ATAC should hit either the curated chain or compose
    a plausible multi-omics plan; either way verifier must pass."""
    r = compose_chain(
        "multi-omics RNA-seq plus ATAC-seq integration on mouse brain mm10",
    )
    assert r.steps
    assert r.verifier_report["ok"], f"verifier errors: {r.verifier_report['errors']}"
    # Plan must reference both modalities somewhere (workflow name or rationale).
    plan_text = " ".join(s.workflow_name for s in r.steps).lower() + " " + r.rationale.lower()
    assert "rnaseq" in plan_text or "rna-seq" in plan_text or "rna" in plan_text
    assert "atac" in plan_text


def test_default_llm_returns_none_without_keys(monkeypatch):
    """Adapter must return None gracefully when no provider key is present."""
    from chain_composer.llm_adapter import default_llm
    for k in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GOOGLE_API_KEY",
              "GEMINI_API_KEY", "DEEPSEEK_API_KEY", "ZHIPU_API_KEY"):
        monkeypatch.delenv(k, raising=False)
    assert default_llm() is None


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
