"""Unit tests for intent-aware evidence-source selection.

The core guarantee: a SAR / potency question about a target reaches the
bioactivity + structure sources (ChEMBL/BindingDB/PDB/Pharos), not just the
gene sources an entity-type router would pick. Pure logic, no network.
"""
from galaxy.ai.evidence_source_router import (
    detect_facets,
    is_target_ranking_question,
    select_sources,
)


def test_target_ranking_detection():
    for q in ("Which targets should we pursue for melanoma?",
              "Identify drug targets for triple-negative breast cancer",
              "Prioritize candidate targets for NAFLD"):
        assert is_target_ranking_question(q), q
    # NOT ranking questions — these want explanation/structure, not a ranked list
    for q in ("What drives ABL1 potency?",
              "What is the DFG-out conformation?",
              "Is T315I a resistance variant?"):
        assert not is_target_ranking_question(q), q


def test_sar_question_selects_bioactivity_sources():
    q = "Known SAR for imatinib-like phenylaminopyrimidines — what drives ABL1 potency?"
    assert "bioactivity" in detect_facets(q)
    srcs = select_sources(q, entities=["ABL1"])
    # The bioactivity/structure sources the entity-type ('gene') router would have skipped
    # are now reached — including bindingdb (measured affinities) + pharos (tractability),
    # which gained federation fetchers 2026-11-11:
    for needed in ("chembl", "bindingdb", "pharos", "pubchem", "chebi", "pdb"):
        assert needed in srcs, f"{needed} missing for a SAR/potency question: {srcs}"


def test_structure_question_selects_structure_sources():
    q = "What is the DFG-out conformation of the ABL1 kinase domain?"
    assert "structure" in detect_facets(q)
    srcs = select_sources(q, entities=["ABL1"])
    assert "pdb" in srcs and "alphafold" in srcs


def test_pathway_question_selects_pathway_sources():
    srcs = select_sources("Which signalling pathways does KRAS regulate?", entities=["KRAS"])
    assert "kegg" in srcs and "reactome" in srcs


def test_variant_question_selects_variant_sources():
    srcs = select_sources("Is the T315I mutation a resistance variant?")
    assert "clinvar" in srcs and "dbsnp" in srcs


def test_literature_always_present():
    srcs = select_sources("What is the function of BRCA1?", entities=["BRCA1"])
    assert "pubmed" in srcs  # corroboration channel is always selected


def test_plain_gene_question_has_identity_baseline():
    q = "What is the function of BRCA1?"
    assert detect_facets(q) == []  # no specific facet
    srcs = select_sources(q, entities=["BRCA1"])
    assert "uniprot" in srcs and "ncbi_gene" in srcs  # gene baseline via named entity


def test_deduped_and_capped():
    srcs = select_sources(
        "SAR, potency, binding affinity, structure, pathway, variant of ABL1",
        entities=["ABL1"], max_sources=14,
    )
    assert len(srcs) == len(set(srcs))  # no duplicates
    assert len(srcs) <= 14


def test_fold_cue_is_word_bounded_not_scaffold():
    # "fold" word-bounded: a genomics assembly question ("scaffold N50") must NOT trip the
    # structure facet (committee review round 2, 2026-11-11).
    assert "structure" not in detect_facets("What is the scaffold N50 of this genome assembly?")
    assert "structure" in detect_facets("What is the protein fold of this domain?")


def test_prioriti_cue_scoped_to_target_ranking():
    # bare "prioriti" used to fire the costly target_id orchestrator on generic text.
    assert not is_target_ranking_question("Prioritize the samples by read depth")
    assert not is_target_ranking_question("What's the priority here?")
    assert is_target_ranking_question("Prioritize targets for pancreatic cancer")


def test_registry_unavailable_passes_through_but_present_filters():
    # None (registry import failed) → pass through unfiltered; a present registry filters to
    # only serveable ids — a misconfigured/empty registry must NOT advertise everything
    # (committee review round 2, 2026-11-11).
    import galaxy.ai.evidence_source_router as esr
    _real = esr._registry
    try:
        esr._registry = None            # simulate registry unavailable
        srcs = esr.select_sources("SAR potency of ABL1", entities=["ABL1"])
        assert "chembl" in srcs         # not filtered away when registry is unavailable
    finally:
        esr._registry = _real
