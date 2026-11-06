"""Explicitly named workflows route to exactly that workflow.

Measured 2026-11-03 on the cold-start examples (exact UI payloads): "Try sample data"
prompts that NAME their workflow ("Run perform_chipseq_peak_calling_with_macs2 using its
built-in ... demo files") were routed by keyword retrieval to a different workflow
(nf-core/chipseq, which needs real reads; a metaboanalystr sibling). The named-workflow
fast path runs first and resolves the name exactly (resolve_named_workflow).

Run: cd backend && PYTHONPATH=lib pytest tests/test_named_workflow_routing.py -v
"""
from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from galaxy.ai.ai_assistant import AIAssistant

DB = Path(__file__).resolve().parent.parent / "database" / "galaxy_ai_tools.db"


# ── tokenizer (pure) ─────────────────────────────────────────────────────────

def test_tokens_are_workflow_ids_not_files_params_or_paths():
    toks = AIAssistant._named_workflow_tokens(
        "Run perform_chipseq_peak_calling_with_macs2 on counts_matrix.csv with "
        "min_fold_change=2, smiles_list: [..] from s3://bucket/raw_reads/x"
    )
    assert toks == ["perform_chipseq_peak_calling_with_macs2"]


def test_the_name_workflow_phrase_counts_without_underscores():
    assert "metaboanalystr" in AIAssistant._named_workflow_tokens(
        "Run the metaboanalystr workflow using its built-in demo dataset."
    )


# ── fast-path decision rules (fake catalog) ──────────────────────────────────

class _Catalog:
    def __init__(self, known):
        self.known = known

    def resolve_named_workflow(self, token):
        wid = self.known.get(token)
        return SimpleNamespace(id=wid, name=token, score=0.0) if wid else None


def _assistant(known):
    a = object.__new__(AIAssistant)  # no LLM/DB setup needed for the routing decision
    a.workflow_search = _Catalog(known)
    a._return_nextflow_match = lambda match, **kw: {"routed_to": match.name, "intent": kw["user_intent"]}
    return a


def test_one_named_workflow_routes_to_it():
    a = _assistant({"perform_chipseq_peak_calling_with_macs2": 10680})
    out = a._try_fast_path_named_catalog_workflow(
        "Run perform_chipseq_peak_calling_with_macs2 using its built-in MACS3 CTCF_SE demo files."
    )
    assert out["routed_to"] == "perform_chipseq_peak_calling_with_macs2"


def test_no_named_workflow_falls_through():
    a = _assistant({"perform_chipseq_peak_calling_with_macs2": 10680})
    assert a._try_fast_path_named_catalog_workflow("Call peaks on my ChIP-seq data.") is None


def test_two_named_workflows_are_left_to_chain_routing():
    a = _assistant({"geo_data_connector": 10672, "qsar_rf_model": 10784})
    assert a._try_fast_path_named_catalog_workflow(
        "Run geo_data_connector and then qsar_rf_model on the result."
    ) is None


def test_explicit_nfcore_is_left_to_the_nfcore_fast_path():
    a = _assistant({"qsar_rf_model": 10784})
    assert a._try_fast_path_named_catalog_workflow("Run nf-core/rnaseq then qsar_rf_model.") is None


def test_memory_context_from_past_turns_does_not_name_this_request():
    a = _assistant({"hts_plate_qc_hit_calling": 12882})
    intent = ("Summarise this assay table.\n\n[Memory context] This user previously corrected:\n"
              "- Suggested: assay_ingestion_and_ranking → User chose: hts_plate_qc_hit_calling")
    assert a._try_fast_path_named_catalog_workflow(intent) is None


# ── resolver against the real catalog (skipped where the git-ignored DB is absent) ──

@pytest.fixture(scope="module")
def catalog():
    if not DB.exists():
        pytest.skip("galaxy_ai_tools.db not present in this checkout")
    from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
    return UnifiedWorkflowSearch(DB)


@pytest.mark.parametrize("identifier,expected_dir", [
    ("perform_chipseq_peak_calling_with_macs2", "perform_chipseq_peak_calling_with_macs2"),
    ("Perform Chipseq Peak Calling With Macs2", "perform_chipseq_peak_calling_with_macs2"),
    ("metaboanalystr", "metaboanalystr"),                      # directory slug
    ("REINVENT4 Generative Lead Design", "reinvent4_lead_design"),  # display name
    ("hts_plate_qc_hit_calling", "hts_plate_qc_hit_calling"),  # duplicated row → deterministic pick
])
def test_resolves_every_identifier_form(catalog, identifier, expected_dir):
    m = catalog.resolve_named_workflow(identifier)
    assert m is not None
    assert f"/{expected_dir}/" in m.filename.lower() or m.filename.lower().endswith(f"/{expected_dir}.nf")


@pytest.mark.parametrize("identifier", [
    "main", "workflows", "counts_matrix", "sample_metadata", "smiles_list", "plate_reshape_long_format",
])
def test_non_workflow_identifiers_do_not_resolve(catalog, identifier):
    assert catalog.resolve_named_workflow(identifier) is None


def test_duplicate_rows_resolve_to_the_same_row_every_time(catalog):
    ids = {catalog.resolve_named_workflow("qsar_rf_model").id for _ in range(3)}
    assert len(ids) == 1
