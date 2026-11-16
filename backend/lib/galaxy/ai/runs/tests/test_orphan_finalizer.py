"""Tests for finalize_orphaned_run.

Verify the safe subset of post-completion side effects (status update,
returncode inference) without requiring the full nextflow_executor
module to be loaded.
"""

import os
import time

import pytest

from galaxy.ai.runs.orphan_finalizer import (
    _read_returncode_from_disk,
    finalize_orphaned_run,
)
from galaxy.ai.runs.run_state_store import InMemoryRunStateStore


def test_returncode_from_pipeline_completed_successfully(tmp_path):
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text(
        "Some preamble\n"
        "Pipeline completed successfully at 2026-06-15 17:00:00\n"
    )
    rc, _ = _read_returncode_from_disk({"log_path": str(log_path)})
    assert rc == 0


def test_returncode_from_exit_line(tmp_path):
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text(
        "Some preamble\n"
        "Process [PIPELINE:FOO] exit: 2 status: FAILED\n"
    )
    rc, _ = _read_returncode_from_disk({"log_path": str(log_path)})
    assert rc == 2


def test_returncode_from_pipeline_with_errors(tmp_path):
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text("Pipeline completed with errors at 2026-06-15 17:00:00\n")
    rc, _ = _read_returncode_from_disk({"log_path": str(log_path)})
    assert rc == 1


def test_returncode_unknown_when_no_log():
    rc, _ = _read_returncode_from_disk({"log_path": "/nonexistent/path"})
    assert rc == -1


def _write_trace(tmp_path, rows):
    """rows: list of (name, status, exit). Writes a Nextflow trace.txt whose
    columns match the parser (task_id hash native_id name status exit ...)."""
    trace = tmp_path / "trace.txt"
    lines = ["task_id\thash\tnative_id\tname\tstatus\texit"]
    for i, (name, status, code) in enumerate(rows, 1):
        lines.append(f"{i}\tab/{i:06d}\t{1000+i}\t{name}\t{status}\t{code}")
    trace.write_text("\n".join(lines) + "\n")
    return trace


def test_script_compile_failure_reports_failure_despite_all_tasks_ok(tmp_path):
    """Regression (2026-07-08 test-container nca_pknca run): a process that
    fails at script COMPILATION never enters the trace, so the trace shows only
    the successfully-dispatched tasks (all COMPLETED exit 0). The launcher log,
    however, aborts the session. The finalizer must report failure (rc=1) — not
    infer success from the trace — else a broken run is silently 'succeeded'."""
    trace = _write_trace(
        tmp_path,
        [("NCA_PKNCA:NCA_INPUT_VALIDATION", "COMPLETED", "0"),
         ("NCA_PKNCA:NCA_PKNCA_ANALYSIS", "COMPLETED", "0")],
    )
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text(
        "Jul-08 11:39:07 [Actor Thread 2] ERROR nextflow.processor.TaskProcessor - "
        "Error executing process > 'NCA_PKNCA:NCA_REPORT_HTML (nca_report)'\n"
        "  error [nextflow.exception.ProcessUnrecoverableException]: "
        "Process `NCA_PKNCA:NCA_REPORT_HTML (nca_report)` script contains error(s)\n"
        "Jul-08 11:39:07 [Actor Thread 2] INFO nextflow.Session - "
        "Execution cancelled -- Finishing pending tasks before exit\n"
    )
    rc, _ = _read_returncode_from_disk(
        {"trace_path": str(trace), "log_path": str(log_path)}
    )
    assert rc == 1, "session-abort log marker must override optimistic trace inference"


def test_all_tasks_ok_and_clean_log_still_succeeds(tmp_path):
    """Guard: the Bug-B fix must NOT flip genuine successes to failure. A trace
    with all tasks COMPLETED exit 0 and a log with no abort marker => rc 0."""
    trace = _write_trace(
        tmp_path,
        [("FOO:STEP_A", "COMPLETED", "0"), ("FOO:STEP_B", "COMPLETED", "0")],
    )
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text("Jul-08 [main] DEBUG nextflow.Session - Workflow completed\n")
    rc, _ = _read_returncode_from_disk(
        {"trace_path": str(trace), "log_path": str(log_path)}
    )
    assert rc == 0


def test_returncode_local_outdir_with_files(tmp_path):
    """Heuristic: a non-S3 outdir with content => succeeded."""
    outdir = tmp_path / "out"
    outdir.mkdir()
    (outdir / "result.csv").write_text("x,y\n1,2\n")
    rc, _ = _read_returncode_from_disk(
        {"outdir": str(outdir), "log_path": "/nonexistent"}
    )
    assert rc == 0


def test_finalize_sets_terminal_status_on_success(tmp_path, monkeypatch):
    store = InMemoryRunStateStore()
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text("Pipeline completed successfully\n")
    store.set_run("r1", {
        "status": "running",
        "outdir": str(tmp_path),
        "log_path": str(log_path),
        "invocation_id": None,  # don't try to narrate in tests
    })
    # Don't actually call narrator or S3 — let lazy imports no-op
    finalize_orphaned_run(store, "r1", store.get_run("r1"))
    snap = store.get_run("r1")
    assert snap["status"] == "succeeded"
    assert snap["returncode"] == 0
    assert snap["finalized_by"] == "orphan_poller"
    assert "completed_at" in snap


def test_finalize_marks_failed_on_unknown_exit(tmp_path):
    store = InMemoryRunStateStore()
    store.set_run("r1", {
        "status": "running",
        "outdir": "s3://fake/path",
        "log_path": "/nonexistent",
        "invocation_id": None,
    })
    finalize_orphaned_run(store, "r1", store.get_run("r1"))
    snap = store.get_run("r1")
    assert snap["status"] == "interrupted"  # returncode -1
    assert snap["returncode"] == -1


def _install_fake_executor(monkeypatch, outdir_files, workdir_files):
    """Inject a stub nextflow_executor exposing the three listing/QC helpers the
    finalizer lazily imports, so the work-dir-fallback path can be tested without
    loading the real (heavy, S3-touching) module."""
    import sys
    import types
    mod = types.ModuleType("galaxy.webapps.galaxy.api.nextflow_executor")
    mod._list_s3_output_files = lambda uri: list(outdir_files)
    mod._list_s3_work_output_files = lambda uri: list(workdir_files)
    mod._evaluate_qc_from_s3 = lambda **kw: None
    monkeypatch.setitem(sys.modules, "galaxy.webapps.galaxy.api.nextflow_executor", mod)
    return mod


def test_finalize_persists_workdir_outputs_when_outdir_empty(tmp_path, monkeypatch):
    """Regression (Cox `output_files: []`): a no-publishDir workflow writes its
    declared outputs only to work/<hash>/ on S3, never the outdir. The orphan
    finalizer must scan the outdir, fall back to the work dir, and PERSIST the
    discovered files to the store so get_run / analyze_results see them."""
    workdir_files = [
        {"s3_uri": "s3://b/work/x/cox_hazard_ratios.csv", "name": "cox_hazard_ratios.csv",
         "size": 377, "extension": "csv"},
        {"s3_uri": "s3://b/work/x/cox_zph_test.csv", "name": "cox_zph_test.csv",
         "size": 263, "extension": "csv"},
    ]
    _install_fake_executor(monkeypatch, outdir_files=[], workdir_files=workdir_files)
    store = InMemoryRunStateStore()
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text("Pipeline completed successfully\n")
    store.set_run("r1", {
        "status": "running",
        "outdir": "s3://b/outputs/x",       # publishDir target — stays EMPTY
        "workdir": "s3://b/work/x",          # declared outputs land here
        "log_path": str(log_path),
        "invocation_id": None,
    })
    finalize_orphaned_run(store, "r1", store.get_run("r1"))
    snap = store.get_run("r1")
    assert snap["status"] == "succeeded"
    assert len(snap.get("s3_output_files") or []) == 2, \
        "work-dir outputs must be persisted when the publishDir outdir is empty"
    assert {f["name"] for f in snap["s3_output_files"]} == {
        "cox_hazard_ratios.csv", "cox_zph_test.csv"}


def test_finalize_prefers_outdir_outputs_over_workdir(tmp_path, monkeypatch):
    """Guard: when the publishDir outdir HAS files (e.g. MHC), the finalizer
    persists those and does NOT fall through to the (noisier) work-dir scan."""
    outdir_files = [
        {"s3_uri": "s3://b/outputs/x/predictions.csv", "name": "predictions.csv",
         "size": 263, "extension": "csv"},
    ]
    workdir_files = [
        {"s3_uri": "s3://b/work/x/predictions.csv", "name": "predictions.csv",
         "size": 263, "extension": "csv"},
        {"s3_uri": "s3://b/work/x/noise.csv", "name": "noise.csv", "size": 1, "extension": "csv"},
    ]
    _install_fake_executor(monkeypatch, outdir_files=outdir_files, workdir_files=workdir_files)
    store = InMemoryRunStateStore()
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text("Pipeline completed successfully\n")
    store.set_run("r1", {
        "status": "running",
        "outdir": "s3://b/outputs/x",
        "workdir": "s3://b/work/x",
        "log_path": str(log_path),
        "invocation_id": None,
    })
    finalize_orphaned_run(store, "r1", store.get_run("r1"))
    snap = store.get_run("r1")
    assert len(snap.get("s3_output_files") or []) == 1
    assert snap["s3_output_files"][0]["name"] == "predictions.csv"


def test_finalize_run_moves_out_of_active_set(tmp_path):
    """After finalize, the run must be excluded from list_active_runs()
    so the poller doesn't re-fire."""
    store = InMemoryRunStateStore()
    log_path = tmp_path / ".nextflow.log"
    log_path.write_text("Pipeline completed successfully\n")
    store.set_run("r1", {
        "status": "running",
        "outdir": str(tmp_path),
        "log_path": str(log_path),
        "invocation_id": None,
    })
    assert "r1" in store.list_active_runs()
    finalize_orphaned_run(store, "r1", store.get_run("r1"))
    # InMemory _TERMINAL set includes "succeeded"? Check via list_active_runs
    # (test_list_active_runs_excludes_terminal covers this for "completed"/"failed")
    snap = store.get_run("r1")
    assert snap["status"] == "succeeded"
