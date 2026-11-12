"""_merge_results must respect the facet router's intent-selected source order so a broad
SAR query surfaces its bioactivity sources (chembl/bindingdb/pharos) in the top rows,
instead of a generic entity-type priority burying them past the downstream top-N cap
(dev finding 2026-11-12)."""
from galaxy.ai.federated_query import _merge_results


def _results(order):
    return {s: {"source": s, "results": [{"name": s + "_top"}]} for s in order}


def test_facet_source_order_surfaces_bioactivity_first():
    # A SAR query: the facet router puts bioactivity/structure first, identity later.
    facet = ["chembl", "bindingdb", "pubchem", "chebi", "pharos", "uniprot", "pdb",
             "pdbe", "alphafold", "interpro", "opentargets", "string", "ncbi_gene", "ensembl"]
    top8 = [m["_source"] for m in _merge_results(_results(facet), "protein", source_order=facet)][:8]
    # The sources the SAR question needs are in the top-8, not cut.
    assert "bindingdb" in top8 and "chembl" in top8 and "pharos" in top8, top8


def test_falls_back_to_entity_priority_without_source_order():
    # No source_order → generic entity-type priority still works (uniprot-first for protein).
    facet = ["bindingdb", "uniprot", "pdb"]
    first = [m["_source"] for m in _merge_results(_results(facet), "protein")][0]
    assert first == "uniprot", first
