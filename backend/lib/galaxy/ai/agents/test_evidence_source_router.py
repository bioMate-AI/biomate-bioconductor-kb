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
    # The federation-serveable bioactivity/structure sources the entity-type ('gene')
    # router would have skipped are now reached:
    for needed in ("chembl", "pubchem", "chebi", "pdb"):
        assert needed in srcs, f"{needed} missing for a SAR/potency question: {srcs}"
    # bindingdb/pharos ARE listed in the bioactivity facet map, but have no federation
    # fetcher yet, so `_federation_serveable_ids` drops them rather than advertise coverage
    # that `federated_query` would silently discard (honest-coverage gate, committee review
    # 2026-11-11). Adding fetchers for them is a tracked future gap, not a regression.
    for not_yet_serveable in ("bindingdb", "pharos"):
        assert not_yet_serveable not in srcs, (
            f"{not_yet_serveable} has no federation fetcher; must be filtered: {srcs}")


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
