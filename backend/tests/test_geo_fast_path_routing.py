"""Regression coverage for GEO modality routing used by replication journeys.

These are deliberately unit-level: they exercise the deterministic fast path
without a live GEO request, database, or LLM.  The cases are sourced from the
East Hospital replication plan, where sending an array study through scRNA
pseudobulk or reducing a Seurat clustering request to DESeq2 would produce a
scientifically invalid workflow card before execution begins.
"""

import os
import re
import sys
from types import SimpleNamespace
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from galaxy.ai.ai_assistant import AIAssistant


def _assistant_with_platform(platform):
    assistant = object.__new__(AIAssistant)
    assistant._detect_geo_platform = lambda _gse_id: platform
    def _by_pattern(pattern):
        name = "geo_data_connector" if "geo_data_connector" in pattern else "geo_scrna_pseudobulk"
        return SimpleNamespace(
            id=10673,
            name=name,
            filename=f"biomni_workflows/transcriptomics/{name}/main.nf",
            domain="single_cell",
            description="test workflow",
        )
    assistant.workflow_search = SimpleNamespace(
        get_workflow_by_filename_pattern=_by_pattern,
        get_workflow_by_name=lambda _name: None,
    )
    return assistant


def test_geo_microarray_routes_to_retrieval_review_not_scrna_pseudobulk():
    """GSE108000 is an array study; it needs retrieval/review before limma."""
    assistant = _assistant_with_platform("microarray")

    result = assistant._try_fast_path_geo_scrna_pseudobulk(
        "Run differential expression on the GSE108000 microarray study with limma"
    )

    assert result is not None
    assert result["source"] == "geo_accession_preflight"
    assert result["workflow_ga"]["name"] == "geo_data_connector"
    assert result["workflow_ga"]["required_params"][0]["value"] == "GSE108000"
    assert "not automatically run differential expression" in result["workflow_ga"]["description"]


def test_geo_scrna_clustering_is_not_collapsed_to_pseudobulk_de():
    """GSE138689 needs Seurat-style clustering/markers, not aggregate DE."""
    assistant = _assistant_with_platform("scrna")

    result = assistant._try_fast_path_geo_scrna_pseudobulk(
        "For GSE138689, run Seurat clustering, UMAP, marker genes, and trajectory analysis"
    )

    assert result is None


def test_explicit_geo_scrna_pseudobulk_de_still_returns_a_complete_card():
    """The guard must preserve the supported cross-condition pseudobulk path."""
    assistant = _assistant_with_platform("scrna")

    result = assistant._try_fast_path_geo_scrna_pseudobulk(
        "Pseudobulk GSE138689 and run DESeq2 differential expression"
    )

    assert result is not None
    assert result["source"] == "template_reuse"
    assert result["workflow_ga"]["name"] == "geo_scrna_pseudobulk"
    assert result["workflow_ga"]["required_params"][0]["value"] == "GSE138689"


def test_bulk_geo_without_connector_returns_actionable_block_not_empty_de_card():
    """A missing connector must surface a recoverable preflight failure, never DESeq2."""
    assistant = object.__new__(AIAssistant)
    assistant._detect_geo_platform = lambda _gse_id: "bulk_rnaseq"
    assistant.workflow_search = SimpleNamespace(
        get_workflow_by_filename_pattern=lambda _pattern: None,
        get_workflow_by_name=lambda _name: None,
    )

    result = assistant._try_fast_path_geo_scrna_pseudobulk(
        "Run differential expression on GSE108000 bulk RNA-seq data"
    )

    assert result is not None
    assert result["success"] is False
    assert result["source"] == "geo_accession_preflight"
    assert "Differential expression was not created" in result["message"]
    assert result["validation"]["is_valid"] is False


def test_unknown_geo_is_not_guessed_to_be_single_cell():
    """A network/metadata miss must retrieve first unless the user explicitly says scRNA."""
    assistant = _assistant_with_platform(None)

    result = assistant._try_fast_path_geo_scrna_pseudobulk(
        "Run differential expression on GSE108000"
    )

    assert result is not None
    assert result["workflow_ga"]["name"] == "geo_data_connector"


def test_geo_connector_does_not_default_to_a_fake_accession_or_first_platform():
    """The executable connector must preserve the accession and require platform choice."""
    root = Path(__file__).resolve().parents[1]
    workflow_path = (
        root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" /
        "genomics" / "geo_data_connector" / "main.nf"
    )
    workflow = workflow_path.read_text()
    config = workflow_path.with_name("nextflow.config").read_text()

    assert "params.accession = null" in workflow
    assert re.search(r"\baccession\s*=\s*null", config)
    assert "params.accession = 'GSE999999'" not in workflow
    assert "no platform was selected automatically" in workflow
    assert "--platform_id" in workflow


def test_geo_connector_local_input_and_output_contract_are_wired():
    """Advertised local matrices and chain-facing sample_metadata must be real paths."""
    root = Path(__file__).resolve().parents[1]
    workflow = (
        root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" /
        "genomics" / "geo_data_connector" / "main.nf"
    ).read_text()

    assert "process GEO_LOAD_LOCAL" in workflow
    assert "tuple val(meta), path(local_series_matrix)" in workflow
    assert "GEO_LOAD_LOCAL(ch_local_input)" in workflow
    assert "sample_metadata   = GEO_CLINICAL_METADATA.out.sample_metadata" in workflow
    assert 'path("sample_metadata.csv"), emit: sample_metadata' in workflow
    assert 'path("clinical_metadata_clean.csv")' not in workflow
