"""Regression tests for rule_classify_kinds mislabels found in the 2026-11-13 branch audit.

1. A bare 'rna-seq'/'chip-seq'/'atac-seq' domain word in a DOWNSTREAM matrix-input tool's
   tags/description must NOT yield a {fastq} label — that false positive triggered the step-8a -25
   penalty and demoted count-matrix tools (linnorm, degseq, rcsl) for {counts_matrix} users.
2. An IVIVE / intrinsic-clearance PK calculator consumes a measured-parameter TABLE, not molecules
   (id 12825 'Ivive Hepatic Clearance' was mislabelled {molecules}).
3. Genuine raw-read pipelines MUST still be labelled {fastq} (no over-correction).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.chain_composer.input_kinds_classifier import rule_classify_kinds  # noqa: E402


def _k(name="", description="", annotation="", input_types="[]", tags=""):
    return rule_classify_kinds({"name": name, "description": description, "annotation": annotation,
                                "input_types": input_types, "tags": tags}) or []


# --- 1. downstream matrix tools must NOT be fastq (exact rows from the real catalog) ------------

def test_linnorm_not_fastq():
    k = _k(name="linnorm", tags="rna-seq transcriptomics",
           description="Normalize, transform, and optionally impute raw count or expression data "
                       "for downstream parametric analysis or export.")
    assert "fastq" not in k


def test_degseq_not_fastq():
    k = _k(name="degseq", tags="rna-seq",
           description="Identify differentially expressed genes from pre-calculated gene expression "
                       "matrices using MA-plot-based methods (MARS or MATR).")
    assert "fastq" not in k


def test_rcsl_not_fastq():
    k = _k(name="rcsl", tags="single-cell scrna-seq",
           description="Perform single-cell clustering and trajectory analysis on scRNA-seq expression data.")
    assert "fastq" not in k


# --- 2. IVIVE hepatic clearance is a measured-parameter table, not molecules --------------------

def test_ivive_hepatic_clearance_is_tabular_not_molecules():
    k = _k(name="Ivive Hepatic Clearance",
           description="In vitro to in vivo extrapolation (IVIVE) of hepatic clearance. "
                       "Scales microsomal or hepatocyte CLint to in-vivo clearance.")
    assert "tabular" in k
    assert "molecules" not in k and "structure" not in k


# --- 3. genuine raw-read pipelines must still be fastq (no over-correction) ---------------------

def test_rnaseq_raw_reads_pipeline_still_fastq():
    k = _k(name="nf-core rnaseq", tags="rna-seq",
           description="RNA-seq analysis from raw FASTQ reads: adapter trimming, alignment, to a gene count matrix.")
    assert "fastq" in k


def test_chipseq_raw_reads_still_fastq():
    k = _k(name="chipseq", tags="chip-seq",
           description="ChIP-seq peak calling from raw sequencing reads.")
    assert "fastq" in k


def test_bare_rnaseq_domain_word_alone_is_not_fastq():
    # domain word without any raw-read evidence → prefer NULL over a false fastq positive
    k = _k(name="some rna-seq tool", tags="rna-seq", description="A transcriptomics analysis helper.")
    assert "fastq" not in k
