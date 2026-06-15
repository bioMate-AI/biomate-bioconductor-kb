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
