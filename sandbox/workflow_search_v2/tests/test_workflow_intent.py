"""
Unit tests for sandbox/workflow_search_v2/library/workflow_intent.py.

Covers: YAML load, intent matching, disqualifier logic, promotion behavior,
non-mutation, and the safety property (never flips a correct top-1 to wrong
on the curated 4 regression cases from the A/B run).
"""
from __future__ import annotations

import pytest

from sandbox.workflow_search_v2.library.workflow_intent import (
    load_intent_anchors,
    prioritize_workflow_by_intent,
)


class _Cand:
    def __init__(self, name):
        self.name = name
    def __repr__(self):
        return f"Cand({self.name})"


# ─── YAML load ───────────────────────────────────────────────────────────

def test_anchors_load():
    anchors = load_intent_anchors()
    assert len(anchors) >= 20
    canonicals = {a["canonical"] for a in anchors}
    # spot-check key anchors
    for c in ("nf-core/rnaseq", "nf-core/sarek", "nf-core/scrnaseq",
              "nf-core/raredisease", "nf-core/airrflow"):
        assert c in canonicals


# ─── happy path ──────────────────────────────────────────────────────────

def test_rnaseq_query_promotes_canonical():
    cands = [_Cand("nf-core/cutandrun"), _Cand("scry"),
             _Cand("nf-core/rnaseq"), _Cand("ALDEx2")]
    out = prioritize_workflow_by_intent(
        "Run standard RNA-seq analysis on my paired-end FASTQ files", cands
    )
    assert out[0].name == "nf-core/rnaseq"


def test_variant_calling_promotes_sarek():
    cands = [_Cand("nf-core/rnavar"), _Cand("nf-core/sarek")]
    out = prioritize_workflow_by_intent(
        "Call germline SNPs and indels from whole genome sequencing", cands
    )
    assert out[0].name == "nf-core/sarek"


def test_differentialabundance_when_count_matrix():
    cands = [_Cand("nf-core/rnaseq"),
             _Cand("nf-core/differentialabundance"), _Cand("CleanUpRNAseq")]
    out = prioritize_workflow_by_intent(
        "I already have a count matrix from rnaseq, find differentially expressed genes", cands
    )
    assert out[0].name == "nf-core/differentialabundance"


# ─── disqualifiers ───────────────────────────────────────────────────────

def test_tcr_query_does_not_promote_scrnaseq():
    """Regression: imm_002 — '10x single-cell TCR' shouldn't fire scrnaseq."""
    cands = [_Cand("nf-core/airrflow"), _Cand("nf-core/scrnaseq")]
    out = prioritize_workflow_by_intent(
        "T cell receptor clonotype tracking from 10x single-cell immune profiling", cands
    )
    # scrnaseq should NOT be at top — disqualified by 'tcr' / 't cell receptor'
    assert out[0].name != "nf-core/scrnaseq"


def test_multiome_query_does_not_promote_atacseq():
    """Regression: sc_020 — joint scATAC+RNA should not become atacseq."""
    cands = [_Cand("multiome_rna_atac"), _Cand("nf-core/atacseq")]
    out = prioritize_workflow_by_intent(
        "Single-cell ATAC and RNA joint profiling on the same cells", cands
    )
    assert out[0].name != "nf-core/atacseq"


def test_merfish_query_does_not_promote_spatialvi():
    """Regression: sc_022 — subcellular RNA detection ≠ Visium."""
    cands = [_Cand("merfish_spatial_analysis"), _Cand("nf-core/spatialvi")]
    out = prioritize_workflow_by_intent(
        "Spatial transcriptomics with subcellular RNA molecule detection", cands
    )
    assert out[0].name != "nf-core/spatialvi"


def test_hla_quantification_query_does_not_promote_epitopeprediction():
    """Regression: prot_009 — 'quantify HLA-presented peptides' is mhcquant."""
    cands = [_Cand("nf-core/mhcquant"), _Cand("nf-core/epitopeprediction")]
    out = prioritize_workflow_by_intent(
        "Quantify HLA-presented peptides for neoantigen discovery in cancer", cands
    )
    # mhcquant must stay at top — epitopeprediction is disqualified by 'quantify'
    assert out[0].name == "nf-core/mhcquant"


# ─── ambiguity → pass-through ────────────────────────────────────────────

def test_no_intent_match_pass_through():
    cands = [_Cand("foo"), _Cand("bar")]
    out = prioritize_workflow_by_intent("completely unrelated random text", cands)
    assert [c.name for c in out] == ["foo", "bar"]


def test_canonical_not_in_candidates_no_op():
    """If the intent's canonical isn't in the candidate list, leave order alone."""
    cands = [_Cand("nf-core/sarek"), _Cand("nf-core/cutandrun")]
    out = prioritize_workflow_by_intent(
        "Run standard RNA-seq analysis on FASTQ files", cands
    )
    # nf-core/rnaseq isn't in the list; sarek remains at top
    assert out[0].name == "nf-core/sarek"


def test_already_at_top_no_op():
    cands = [_Cand("nf-core/sarek"), _Cand("nf-core/rnavar")]
    out = prioritize_workflow_by_intent(
        "Call germline variants from WGS", cands
    )
    assert out[0].name == "nf-core/sarek"


def test_empty_query_returns_input_unchanged():
    cands = [_Cand("foo")]
    assert [c.name for c in prioritize_workflow_by_intent("", cands)] == ["foo"]


def test_empty_candidates_returns_empty():
    assert prioritize_workflow_by_intent("rna-seq", []) == []


def test_does_not_mutate_input():
    cands = [_Cand("nf-core/cutandrun"), _Cand("nf-core/rnaseq")]
    _ = prioritize_workflow_by_intent("rna-seq analysis", cands)
    assert cands[0].name == "nf-core/cutandrun"  # original unchanged


def test_dict_style_candidates_work():
    """Library accepts plain dicts as well as dataclass-like objects."""
    cands = [{"name": "nf-core/cutandrun"}, {"name": "nf-core/rnaseq"}]
    out = prioritize_workflow_by_intent(
        "Run standard RNA-seq analysis", cands
    )
    assert out[0]["name"] == "nf-core/rnaseq"
