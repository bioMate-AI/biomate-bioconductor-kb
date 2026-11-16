"""Guard: a COMPLETED Nextflow run must NEVER silently publish zero outputs.

Root-cause incident (2026-11, this branch): a `completed`, exit-0 Cox run returned
`output_files: []`. The outputs physically existed in S3 — under the Nextflow WORK
dir (bioc subworkflows carry no `publishDir`, so their files only ever land there) —
but the completion resolver read `_runs[run_id].get("workdir")` (no underscore) while
the launch record stored the real S3 work dir under `"work_dir"` (underscore). The
work-dir fallback therefore never fired, and EVERY Bioconductor run published nothing.

This guard closes the CLASS, not the instance:
  1. Both resolution sites (completion path + status endpoint) MUST route through the
     ONE canonical resolver `_resolve_s3_outputs`.
  2. `_resolve_run_workdir` MUST tolerate both the canonical `work_dir` key and the
     legacy `workdir` key, and reconstruct the deterministic S3 path for Batch runs.
  3. The launch record MUST write the work dir under `work_dir`.
  4. A completed-but-empty resolution MUST log loudly (fail loud, not silent []).

STATIC assertions read the source and run in plain CI (no heavy imports). RUNTIME
assertions exercise the real functions when the module is importable.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
EXECUTOR = (
    REPO_ROOT / "backend" / "lib" / "galaxy" / "webapps" / "galaxy" / "api"
    / "nextflow_executor.py"
)


def _extract_function_body(text: str, fn_name: str) -> str:
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^def\s+{re.escape(fn_name)}\s*\(", line):
            start = i
            break
    if start is None:
        raise AssertionError(f"function {fn_name} not found in {EXECUTOR}")
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^def\s+\w+\s*\(", lines[j]) or re.match(r"^class\s+\w+", lines[j]):
            end = j
            break
    return "\n".join(lines[start:end])


# ─────────────────────────── STATIC guards (plain CI) ────────────────────────

def test_canonical_resolver_exists():
    text = EXECUTOR.read_text()
    for fn in ("_resolve_s3_outputs", "_resolve_run_workdir", "_reconstruct_s3_work_dir"):
        assert f"def {fn}(" in text, f"missing canonical resolver helper {fn}"


def test_resolve_run_workdir_reads_both_keys():
    """The key-mismatch fix: the reader must accept BOTH work_dir and workdir."""
    body = _extract_function_body(EXECUTOR.read_text(), "_resolve_run_workdir")
    assert '"work_dir"' in body or "'work_dir'" in body or '.get("work_dir"' in body, (
        "_resolve_run_workdir must read the canonical 'work_dir' key"
    )
    assert "workdir" in body, (
        "_resolve_run_workdir must also tolerate the legacy 'workdir' key"
    )


def test_launch_record_writes_work_dir_key():
    """The launch record must store the work dir under the canonical 'work_dir'."""
    text = EXECUTOR.read_text()
    assert '"work_dir": _s3_work_dir if _s3_work_dir else str(work_dir)' in text, (
        "the launch record must persist the real S3 work dir under key 'work_dir' — "
        "the completion resolver reads that key"
    )


def test_completion_path_uses_canonical_resolver():
    """The completion path MUST NOT read a bare `.get('workdir')` for the fallback —
    it must route through _resolve_s3_outputs (which reads the correct key)."""
    body = _extract_function_body(EXECUTOR.read_text(), "_stream_logs")
    assert "_resolve_s3_outputs(" in body, (
        "the completion path must resolve outputs via _resolve_s3_outputs — "
        "the key-mismatch regression came from inlining a `.get('workdir')` fallback"
    )
    # The old broken line must not come back.
    assert '.get("workdir", "")' not in body, (
        "completion path reintroduced the broken no-underscore 'workdir' read"
    )


def test_status_endpoint_uses_canonical_resolver():
    body = _extract_function_body(EXECUTOR.read_text(), "_get_nextflow_status_impl")
    assert "_resolve_s3_outputs(" in body, (
        "the status endpoint must resolve outputs via _resolve_s3_outputs so bioc "
        "work-dir-only outputs surface here too"
    )


def test_completed_empty_outputs_fails_loud():
    body = _extract_function_body(EXECUTOR.read_text(), "_stream_logs")
    assert "output_resolution_gap" in body, (
        "a completed run that resolved 0 outputs must set output_resolution_gap "
        "(fail loud), not surface a silent output_files: []"
    )
    assert "OUTPUT RESOLUTION GAP" in body, "expected a loud warning for the gap"


def test_manifest_contract_helpers_exist():
    text = EXECUTOR.read_text()
    for fn in ("_build_results_manifest", "_build_design_json", "_write_run_manifests_to_s3"):
        assert f"def {fn}(" in text, f"missing Phase 0 manifest helper {fn}"


# ─────────────────────────── RUNTIME guards (skip if no deps) ─────────────────

def _import_executor():
    import sys
    sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))
    from galaxy.webapps.galaxy.api import nextflow_executor as ne  # noqa: E402
    return ne


def test_resolve_run_workdir_runtime():
    try:
        ne = _import_executor()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"nextflow_executor not importable: {type(e).__name__}: {e}")

    rid = "7c6d9313-ffdd-45a9-9464-ab26b2e9f202"
    # canonical key
    assert ne._resolve_run_workdir({"work_dir": "s3://b/nextflow/work/u/" + rid}, rid) == \
        "s3://b/nextflow/work/u/" + rid
    # legacy key tolerated
    assert ne._resolve_run_workdir({"workdir": "s3://b/legacy"}, rid) == "s3://b/legacy"
    # reconstruct for batch runs when the record carries no work dir
    recon = ne._resolve_run_workdir({"is_batch": True, "user_id": "u1"}, rid)
    assert recon.startswith("s3://") and recon.endswith("/nextflow/work/u1/" + rid)
    # non-batch, no work dir → empty (no reconstruction)
    assert ne._resolve_run_workdir({"is_batch": False}, rid) == ""


def test_resolve_s3_outputs_falls_back_to_workdir(monkeypatch):
    try:
        ne = _import_executor()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"nextflow_executor not importable: {type(e).__name__}: {e}")

    # outdir lists NOTHING (publishDir disabled, as for every bioc subworkflow).
    monkeypatch.setattr(ne, "_list_s3_output_files", lambda uri: [])
    work_files = [{
        "s3_uri": "s3://b/nextflow/work/u/rid/19/h/cox_hazard_ratios.csv",
        "name": "cox_hazard_ratios.csv", "size": 811, "extension": "csv",
    }]
    monkeypatch.setattr(ne, "_list_s3_work_output_files", lambda uri: work_files)

    info = {
        "outdir": "s3://b/nextflow/outputs/u/abcd1234",
        "work_dir": "s3://b/nextflow/work/u/rid",
        "is_batch": True, "user_id": "u",
    }
    out = ne._resolve_s3_outputs(info, "rid")
    assert out == work_files, "work-dir fallback must fire when outdir is empty"


def test_build_results_manifest_roles(monkeypatch):
    try:
        ne = _import_executor()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"nextflow_executor not importable: {type(e).__name__}: {e}")

    files = [
        {"s3_uri": "s3://b/x/cox_hazard_ratios.csv", "name": "cox_hazard_ratios.csv", "size": 811, "extension": "csv"},
        {"s3_uri": "s3://b/x/cox_zph_plots.pdf", "name": "cox_zph_plots.pdf", "size": 73029, "extension": "pdf"},
        {"s3_uri": "s3://b/x/cox_fit.rds", "name": "cox_fit.rds", "size": 16410, "extension": "rds"},
        {"s3_uri": "s3://b/x/versions.yml", "name": "versions.yml", "size": 73, "extension": "yml"},
    ]
    info = {"nextflow_path": "a/b/cox_proportional_hazards_regression.nf",
            "outdir": "s3://b/x", "workflow_domain": "general"}
    m = ne._build_results_manifest("rid", info, files)
    assert m["schema_version"] == "1.0" and m["kind"] == "results_manifest"
    assert m["file_count"] == 4 and m["has_outputs"] is True
    roles = {f["name"]: f["role"] for f in m["files"]}
    assert roles["cox_hazard_ratios.csv"] == "table"
    assert roles["cox_zph_plots.pdf"] == "figure"
    assert roles["cox_fit.rds"] == "model"
    assert roles["versions.yml"] == "provenance"


def test_build_design_json_splits_inputs_and_scalars():
    try:
        ne = _import_executor()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"nextflow_executor not importable: {type(e).__name__}: {e}")

    info = {"nextflow_path": "a/b/cox.nf", "workflow_domain": "general"}
    params = {
        "patient_clinical_data": "s3://b/uploads/clin.csv",
        "outdir": "s3://b/out",         # must be dropped
        "alpha": 0.05,
        "ties": "efron",
    }
    d = ne._build_design_json("rid", info, params)
    assert d["kind"] == "design" and d["schema_version"] == "1.0"
    assert d["inputs"] == {"patient_clinical_data": "s3://b/uploads/clin.csv"}
    assert "outdir" not in d["parameters"] and "outdir" not in d["inputs"]
    assert d["parameters"] == {"alpha": 0.05, "ties": "efron"}
    assert set(d["design"].keys()) == {"formula", "covariates", "group_sizes"}
