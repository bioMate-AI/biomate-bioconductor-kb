"""Composed workflows never show the placeholder name "Generated Workflow".

Run: cd backend && PYTHONPATH=lib pytest tests/test_composed_workflow_name.py -v
"""
from galaxy.ai.ai_assistant import _composed_workflow_name as name


def test_own_name_wins():
    assert name({"name": "scRNA QC and annotation", "description": "x"}) == "scRNA QC and annotation"


def test_placeholder_or_missing_name_uses_the_description():
    d = "Single-cell RNA-seq QC, clustering, and cell-type annotation for GSE157703 with UMAP visualization."
    assert name({"name": "Generated Workflow", "description": d}).startswith("Single-cell RNA-seq QC, clustering")
    assert len(name({"description": d})) <= 60
    assert name({"description": "Fold change table. Then a plot."}) == "Fold change table"


def test_nothing_to_go_on():
    assert name({}) == "Custom workflow"
    assert name(None) == "Custom workflow"


def test_steps_name_a_workflow_without_description():
    wf = {"steps": [{"name": "geo_data_connector"}, {"tool_id": "scrnaseq_qc_pipeline"}, {"name": "annotate_celltype_scRNA"}, {"name": "x"}]}
    assert name(wf).startswith("geo data connector → scrnaseq qc pipeline")
    assert name({"steps": {"0": {"name": "fastqc"}, "1": {"name": "multiqc"}}}) == "fastqc → multiqc"
