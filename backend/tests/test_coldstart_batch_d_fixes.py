"""Regression guards for coldstart Batch D (try-sample-data-0/3/8).

1. PRODUCTION_MD withName is emitted ONLY when the .nf declares that process
   (Nextflow 24+ strict mode aborts on unmatched withName — flow cytometry).
2. Remote scalar file params are localized via boto3 before Channel.fromPath
   (differentialabundance storage-download failure).
3. ChIP-seq / DE / flow-cytometry demo fixtures exist on disk under sample_data/.
"""
from __future__ import annotations

import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

REPO = Path(__file__).resolve().parents[1]
SAMPLE = REPO / "biomni_workflows" / "sample_data"


def test_chipseq_demo_fixtures_vendored():
    chip = SAMPLE / "chipseq"
    assert (chip / "CTCF_SE_ChIP_chr22_50k.bed.gz").is_file()
    assert (chip / "CTCF_SE_CTRL_chr22_50k.bed.gz").is_file()
    assert (chip / "CTCF_SE_ChIP_chr22_50k.bed.gz").stat().st_size > 1000


def test_mg_demo_fixtures_vendored():
    mg = SAMPLE / "mg_demo"
    for name in ("sample_metadata.csv", "counts_matrix.csv", "contrasts.csv"):
        assert (mg / name).is_file(), name
    meta = (mg / "sample_metadata.csv").read_text()
    assert "MG_AChR_pos" in meta and "HC" in meta


def test_flow_cytometry_fcs_fixture_present():
    fcs = SAMPLE / "flow_cytometry" / "Accuri_C6_A01_H2O.fcs"
    assert fcs.is_file()
    assert fcs.stat().st_size > 1000


def test_flow_cytometry_stages_fcs_as_path_input():
    """analysis-try-sample-data-3: bare projectDir string is not mounted on Batch.

    The process must declare `path(... stageAs: 'input.fcs')` and the entry
    workflow must `file(..., checkIfExists: true)` so Nextflow stages the Accuri
    blank into the task work dir. Regression: .command.sh showed
    PARAM_FCS_FILE_PATH=/app/biomni_workflows/.../Accuri_....fcs with exit 1 and
    empty .command.err ("Essential container in task exited").
    """
    nf = (
        REPO
        / "biomni_workflows/nextflow_nfcore/subworkflows/cell_biology"
        / "analyze_flow_cytometry_immunophenotyping/main.nf"
    ).read_text()
    assert "stageAs: 'input.fcs'" in nf
    assert "file(fcs_src, checkIfExists: true)" in nf
    assert "tuple val(meta), path(fcs_file" in nf
    # Must not export the host projectDir path as the only FCS handle.
    assert 'PARAM_FCS_FILE_PATH="${params.fcs_file_path' not in nf
    assert "input.fcs" in nf and "PARAM_FCS_FILE_PATH=" in nf


def test_workflow_tools_dockerfile_installs_flowio():
    """FCS workflows import flowio inside biomate/workflow-tools."""
    df = (REPO / "docker/workflow-tools/Dockerfile").read_text()
    assert "flowio" in df
    smoke = (REPO / "docker/workflow-tools/smoke.py").read_text()
    assert "import flowio" in smoke


def test_chipseq_entry_uses_vendored_sample_data_not_github_raw():
    nf = (
        REPO
        / "biomni_workflows/nextflow_nfcore/subworkflows/genomics"
        / "perform_chipseq_peak_calling_with_macs2/main.nf"
    ).read_text()
    assert "sample_data/chipseq/CTCF_SE_ChIP_chr22_50k.bed.gz" in nf
    assert "raw.githubusercontent.com/macs3-project/MACS" not in nf


def test_differentialabundance_entry_has_demo_and_check_if_exists():
    nf = (REPO / "biomni_workflows/nfcore/differentialabundance/main.nf").read_text()
    assert "sample_data/mg_demo" in nf
    assert "checkIfExists: true" in nf


def _import_executor():
    import sys

    sys.path.insert(0, str(REPO / "lib"))
    from galaxy.webapps.galaxy.api import nextflow_executor as ne  # noqa: PLC0415

    return ne


def test_production_md_selector_only_when_process_declared():
    ne = _import_executor()
    with tempfile.TemporaryDirectory() as tmp:
        cfg_dir = Path(tmp)
        compute = {
            "executor": "awsbatch",
            "queue": "biomate-test-queue",
            "region": "us-west-2",
            "workDir": "s3://biomate-nextflow-work/test",
            "gpu_batch_queue": "biomate-gpu-spot-queue",
        }
        # Flow-cytometry-like .nf: no PRODUCTION_MD process
        no_md = cfg_dir / "flow.nf"
        no_md.write_text("process ANALYZE_FLOW { label 'process_medium'\n  script: 'true'\n}\n")
        path = ne._generate_executor_config(
            compute, cfg_dir, user_id="u", run_id="r1", credentials={},
            nf_path=str(no_md), output_location=None,
        )
        assert path is not None
        text = Path(path).read_text()
        assert "withLabel: 'process_gpu'" in text
        assert "withName: 'PRODUCTION_MD'" not in text

        # MD workflow that declares PRODUCTION_MD
        md = cfg_dir / "md.nf"
        md.write_text(
            "process EQUILIBRATION { label 'process_gpu'\n  script: 'true'\n}\n"
            "process PRODUCTION_MD { label 'process_gpu'\n  script: 'true'\n}\n"
        )
        path2 = ne._generate_executor_config(
            compute, cfg_dir, user_id="u", run_id="r2", credentials={},
            nf_path=str(md), output_location=None,
        )
        assert path2 is not None
        text2 = Path(path2).read_text()
        assert "withName: 'PRODUCTION_MD'" in text2


def test_localize_remote_file_params_rewrites_s3_to_local(tmp_path):
    ne = _import_executor()
    params = {
        "samplesheet": "s3://biomate-nextflow-work/demo/mg_demo/sample_metadata.csv",
        "matrix": "s3://biomate-nextflow-work/demo/mg_demo/counts_matrix.csv",
        "outdir": "s3://biomate-nextflow-work/nextflow/outputs/x",
        "movies_path": "s3://biomate-cryo-data/empiar-10028/Micrographs/",
    }

    def fake_stage(src, dest):
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(f"staged-from:{src}")

    with patch.object(ne, "_stage_declared_input", side_effect=fake_stage):
        ne._localize_remote_file_params(params, tmp_path / "staged", run_id="t")

    assert params["samplesheet"].startswith(str(tmp_path))
    assert Path(params["samplesheet"]).is_file()
    assert params["matrix"].startswith(str(tmp_path))
    # Directory-style / outdir keys must stay remote
    assert params["outdir"].startswith("s3://")
    assert params["movies_path"].startswith("s3://")
