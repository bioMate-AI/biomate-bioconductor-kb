"""The protein-structure fast path must not answer a DESIGN request that carries a sequence.

It fires on any run of >=15 amino-acid letters. On dev (2026-11-04), after the real nf-core
pipelines were restored and nf-core/proteinfold became resolvable, two cold-start design prompts
whose demo context includes the target sequence ([33] "Design cyclic peptides against this
binding site", [60] "Improve serum stability without losing affinity. (peptide design)") were
answered with proteinfold. Structure-prediction requests with a sequence must keep the fast path.

Run: cd backend && PYTHONPATH=lib pytest tests/test_protein_structure_fast_path_generative.py -v
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from galaxy.ai.ai_assistant import AIAssistant

SEQ = "MSQSNRELVVDFLSYKLSQKGYSWSQF"  # a BCL-XL fragment: >=15 aa letters, as in the demo context


def _assistant():
    a = AIAssistant.__new__(AIAssistant)
    top = SimpleNamespace(id=12759, score=1.0, filename="nfcore/proteinfold/main.nf")
    a.workflow_search = SimpleNamespace(get_workflow_by_filename_pattern=lambda pat: top)
    a._return_nextflow_match = lambda **kw: {"workflow_ga": {"name": "nf-core/proteinfold"}, "params": []}
    return a


@pytest.mark.parametrize("intent", [
    f"Design cyclic peptides against this binding site.\n\nPrepared demo context: target {SEQ}",
    f"Improve serum stability without losing affinity. (peptide design)\n\nSequence: {SEQ}",
    f"Generate binders for this epitope: {SEQ}",
    f"Design macrocycles that bind {SEQ}",
])
def test_design_requests_skip_structure_prediction(intent):
    assert _assistant()._try_fast_path_protein_structure(intent) is None


@pytest.mark.parametrize("intent", [
    f"Predict the structure of this protein: {SEQ}",
    f"Fold this sequence with AlphaFold2: {SEQ}",
    SEQ,
])
def test_structure_requests_keep_the_fast_path(intent):
    out = _assistant()._try_fast_path_protein_structure(intent)
    assert out is not None and out["workflow_ga"]["name"] == "nf-core/proteinfold"


@pytest.mark.parametrize("intent", [
    # inline 10x scRNA count table: the barcodes are nucleotide strings (cold-start replay of an external user's request)
    "Cluster these single-cell RNA-seq counts and generate a UMAP: barcode,CD3D,CD4,CD8A "
    "AAACCTGAGAAGGCCT,45,32,0 AAACCTGAGACAGACC,0,0,38 AAACCTGAGCGTTGCC,1,0,0",
    "Align this read to hg38: ACGTACGTTAGCCTAGGATCCAGT",
    "siRNA target AUGGCUACGUAGCUAGCUAG",
])
def test_nucleotide_only_strings_are_not_proteins(intent):
    assert _assistant()._try_fast_path_protein_structure(intent) is None


@pytest.mark.parametrize('intent', [
    'Calculate the physicochemical properties, molecular weight and isoelectric point '
    'of peptide sequence ACDEFGHIKLMNPQRSTVWY.',
    f'Calculate the molecular weight and pI of {SEQ}',
    f'Annotate motifs in this protein: {SEQ}',
    f'Align these peptide sequences: {SEQ}',
    f'Estimate immunogenicity for this peptide: {SEQ}',
    f'Calculate fold change for expression of peptide {SEQ}',
    f'计算肽序列的分子量和等电点：{SEQ}',
    f'Calculate peptide properties.\n\nPrevious context: structure prediction {SEQ}',
])
def test_nonstructural_sequence_tasks_do_not_query_folding_catalogue(intent):
    a = _assistant()
    def wrong_lookup(_pattern):
        raise AssertionError('Nonstructural task must not query the folding catalogue')
    a.workflow_search.get_workflow_by_filename_pattern = wrong_lookup
    assert a._try_fast_path_protein_structure(intent) is None


@pytest.mark.parametrize('intent', [
    f'Protein structure prediction for {SEQ}',
    f'Use ESMFold on this sequence: {SEQ}',
    f'预测这个蛋白质的三维结构：{SEQ}',
])
def test_explicit_structure_aliases_keep_the_fast_path(intent):
    assert _assistant()._try_fast_path_protein_structure(intent) is not None
