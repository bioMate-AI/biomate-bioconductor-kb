"""
Regression test: the v3 workflow adapter must produce identical top-1
ordering as the v2 workflow_intent library on every test case from the
original test suite. This proves the core is feature-complete enough to
host the workflow logic without behavior drift.
"""
from __future__ import annotations

from typing import List

import pytest

from sandbox.intent_retrieval_v3.adapters.workflow import (
    prioritize_workflow_by_intent as v3_prioritize,
)
from sandbox.workflow_search_v2.library.workflow_intent import (
    prioritize_workflow_by_intent as v2_prioritize,
)


class _Cand:
    def __init__(self, name): self.name = name


# Same 12 cases as the v2 test suite plus a few more for inject coverage
_CASES = [
    # (query, candidates, inject, expected_top1)
    ("Run standard RNA-seq analysis on my paired-end FASTQ files",
     [_Cand("nf-core/cutandrun"), _Cand("scry"), _Cand("nf-core/rnaseq")],
     False, "nf-core/rnaseq"),
    ("Call germline SNPs and indels from whole genome sequencing",
     [_Cand("nf-core/rnavar"), _Cand("nf-core/sarek")],
     False, "nf-core/sarek"),
    ("I already have a count matrix from rnaseq, find differentially expressed genes",
     [_Cand("nf-core/rnaseq"), _Cand("nf-core/differentialabundance")],
     False, "nf-core/differentialabundance"),
    ("T cell receptor clonotype tracking from 10x single-cell immune profiling",
     [_Cand("nf-core/airrflow"), _Cand("nf-core/scrnaseq")],
     False, "nf-core/airrflow"),  # scrnaseq disqualified
    ("Single-cell ATAC and RNA joint profiling on the same cells",
     [_Cand("multiome_rna_atac"), _Cand("nf-core/atacseq")],
     False, "multiome_rna_atac"),
    ("Spatial transcriptomics with subcellular RNA molecule detection",
     [_Cand("merfish_spatial_analysis"), _Cand("nf-core/spatialvi")],
     False, "merfish_spatial_analysis"),
    ("Quantify HLA-presented peptides for neoantigen discovery in cancer",
     [_Cand("nf-core/mhcquant"), _Cand("nf-core/epitopeprediction")],
     False, "nf-core/mhcquant"),
    ("completely unrelated random text", [_Cand("foo"), _Cand("bar")],
     False, "foo"),
    # Inject mode happy path
    ("Run standard RNA-seq analysis on my paired-end FASTQ from mouse",
     [_Cand("nf-core/cutandrun"), _Cand("scry"), _Cand("ALDEx2")],
     True, "nf-core/rnaseq"),
    # Inject mode requires ≥ 2 triggers; single weak trigger doesn't inject
    ("stringtie", [_Cand("foo")], True, "foo"),
]


@pytest.mark.parametrize("query,cands,inject,expected", _CASES)
def test_v3_adapter_matches_expected(query, cands, inject, expected):
    """Each case: v3 adapter top-1 == expected."""
    out = v3_prioritize(query, cands, inject_canonical=inject)
    assert out[0].name == expected, (
        f"\n  query={query!r}\n  expected top-1={expected}\n  got={out[0].name}"
    )


@pytest.mark.parametrize("query,cands,inject,expected", _CASES)
def test_v3_matches_v2_behavior(query, cands, inject, expected):
    """v3 adapter must produce same order as v2 library for every case."""
    v3_out = v3_prioritize(query, cands, inject_canonical=inject)
    v2_out = v2_prioritize(query, cands, inject_canonical=inject)
    assert [c.name for c in v3_out] == [c.name for c in v2_out], (
        f"\n  query={query!r}\n  v3={[c.name for c in v3_out]}"
        f"\n  v2={[c.name for c in v2_out]}"
    )


def test_does_not_mutate_input():
    cands = [_Cand("nf-core/cutandrun"), _Cand("nf-core/rnaseq")]
    _ = v3_prioritize("rna-seq", cands)
    assert cands[0].name == "nf-core/cutandrun"


def test_dict_candidates_work():
    cands = [{"name": "nf-core/cutandrun"}, {"name": "nf-core/rnaseq"}]
    out = v3_prioritize("Run standard RNA-seq analysis", cands)
    assert out[0]["name"] == "nf-core/rnaseq"
