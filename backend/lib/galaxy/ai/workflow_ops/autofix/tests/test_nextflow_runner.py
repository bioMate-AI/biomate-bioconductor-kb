"""Local tests for the standalone Nextflow autofix runner.

Covers the failure modes the langgraph pipeline needs to handle without
requiring a live Galaxy transaction, LLM credentials, or a real
Nextflow installation:

  - workflow_dir_not_found  (run_id with no matching dir)
  - no_errors                (workflow dir exists but logs are clean)
  - import_error             (graceful degradation when deps missing)

The "happy path" (debugger actually fixes something) requires LLM API
keys + a real Nextflow trace and is exercised by the existing
autofix3.py HTTP smoke tests, not here.

Run from backend/:  PYTHONPATH=lib python3.9 -m pytest \\
  lib/galaxy/ai/workflow_ops/autofix/tests/test_nextflow_runner.py -v
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path
from unittest import mock

import pytest


@pytest.fixture
def fresh_dir(tmp_path):
    """Return an empty workflow dir."""
    return tmp_path


@pytest.fixture
def dir_with_failing_trace(tmp_path):
    """A workflow dir with a Nextflow trace showing a failed task."""
    (tmp_path / "nextflow.out").write_text(
        "Some log lines\nProcess `myproc` failed with exit code 137\nMore lines\n"
    )
    (tmp_path / "workflow-trace.txt").write_text(
        "task_id\tname\tstatus\n"
        "1\tMOTION_CORRECTION\tFAILED\n"
        "2\tCTF_ESTIMATION\tCOMPLETED\n"
    )
    return tmp_path


def test_resolve_returns_none_for_unknown_id():
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import resolve_workflow_dir
    assert resolve_workflow_dir("does-not-exist-anywhere-2026") is None


def test_resolve_finds_disk_dir(tmp_path):
    """Should pick up /tmp/biomate_runs/<id> convention."""
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import resolve_workflow_dir
    test_id = "test-resolve-fixture"
    target = Path("/tmp/biomate_runs") / test_id
    target.mkdir(parents=True, exist_ok=True)
    try:
        assert resolve_workflow_dir(test_id) == target
    finally:
        target.rmdir()


def test_read_error_logs_empty_dir(fresh_dir):
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import read_error_logs
    assert read_error_logs(fresh_dir) == ""


def test_read_error_logs_extracts_failure_lines(dir_with_failing_trace):
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import read_error_logs
    out = read_error_logs(dir_with_failing_trace)
    assert "failed with exit code 137" in out
    assert "MOTION_CORRECTION\tFAILED" in out


def test_get_first_failed_task_parses_trace(dir_with_failing_trace):
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import get_first_failed_task
    assert get_first_failed_task(dir_with_failing_trace) == "MOTION_CORRECTION"


def test_get_first_failed_task_returns_unknown_when_missing(fresh_dir):
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import get_first_failed_task
    assert get_first_failed_task(fresh_dir) == "UNKNOWN_TASK"


def test_run_nextflow_autofix_workflow_dir_not_found():
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import run_nextflow_autofix
    result = run_nextflow_autofix(invocation_id="this-id-truly-does-not-exist-2026-06-06")
    assert result["success"] is False
    assert result["termination_reason"] == "workflow_dir_not_found"
    assert result["total_attempts"] == 0


def test_run_nextflow_autofix_no_errors_returns_early(tmp_path):
    """If logs are clean, exit before trying to instantiate the LLM stack."""
    from galaxy.ai.workflow_ops.autofix.nextflow_runner import run_nextflow_autofix
    test_id = "test-clean-fixture"
    target = Path("/tmp/biomate_runs") / test_id
    target.mkdir(parents=True, exist_ok=True)
    try:
        # No nextflow.out or workflow-trace.txt → empty error logs
        result = run_nextflow_autofix(invocation_id=test_id)
        assert result["success"] is True
        assert result["termination_reason"] == "no_errors"
    finally:
        target.rmdir()


def test_run_nextflow_autofix_graceful_on_import_error(dir_with_failing_trace, monkeypatch):
    """If the LLM/agent stack import fails, return import_error not crash."""
    from galaxy.ai.workflow_ops.autofix import nextflow_runner
    monkeypatch.setattr(nextflow_runner, "resolve_workflow_dir", lambda _id: dir_with_failing_trace)

    # Force the import to fail by removing the agent module from sys.modules
    # and inserting a sentinel that raises.
    bad_mod_name = "galaxy.ai.workflow_ops.autofix.agent"
    real = sys.modules.pop(bad_mod_name, None)
    sys.modules[bad_mod_name] = None  # forces ImportError on next import
    try:
        result = nextflow_runner.run_nextflow_autofix(invocation_id="fake-id")
        assert result["success"] is False
        assert result["termination_reason"] in {"import_error", "debugger_crash"}
    finally:
        if real is not None:
            sys.modules[bad_mod_name] = real
        else:
            sys.modules.pop(bad_mod_name, None)


def test_langgraph_node_calls_runner_and_clears_error(monkeypatch):
    """End-to-end: the run_autofix node invokes our runner and clears error."""
    from galaxy.ai.langgraph_pipeline import _make_run_autofix_node

    captured = {}

    def fake_runner(invocation_id, **kwargs):
        captured["invocation_id"] = invocation_id
        captured["kwargs"] = kwargs
        return {
            "success": True,
            "total_attempts": 2,
            "termination_reason": "fixed_on_attempt_2",
            "session_id": "sess-xyz",
        }

    import galaxy.ai.workflow_ops.autofix.nextflow_runner as runner_mod
    monkeypatch.setattr(runner_mod, "run_nextflow_autofix", fake_runner)

    node = _make_run_autofix_node(ai_assistant=None)
    state = {
        "execution_run_id": "run-abc-123",
        "error": "Process MOTION_CORRECTION failed with exit 137",
        "autofix_attempts": 0,
    }
    result = node(state)
    assert result["autofix_attempts"] == 1
    assert result["error"] is None  # cleared so dispatch retries
    assert result["autofix_result"]["success"] is True
    assert result["autofix_result"]["session_id"] == "sess-xyz"
    assert captured["invocation_id"] == "run-abc-123"


def test_langgraph_node_handles_runner_crash(monkeypatch):
    """Runner exception must NOT propagate; node records failure + retries."""
    from galaxy.ai.langgraph_pipeline import _make_run_autofix_node

    def crashing_runner(invocation_id, **kwargs):
        raise RuntimeError("synthetic crash")

    import galaxy.ai.workflow_ops.autofix.nextflow_runner as runner_mod
    monkeypatch.setattr(runner_mod, "run_nextflow_autofix", crashing_runner)

    node = _make_run_autofix_node(ai_assistant=None)
    state = {
        "execution_run_id": "run-crash-1",
        "error": "boom",
        "autofix_attempts": 1,
    }
    result = node(state)
    assert result["autofix_attempts"] == 2
    assert result["error"] is None
    assert result["autofix_result"]["success"] is False
    assert result["autofix_result"]["termination_reason"] == "node_exception"


def test_langgraph_node_skips_when_no_run_id(monkeypatch):
    """No run_id (e.g. dispatch never produced one) → skip the call entirely."""
    from galaxy.ai.langgraph_pipeline import _make_run_autofix_node

    called = {"value": False}
    def fail_if_called(*_args, **_kwargs):
        called["value"] = True
        raise AssertionError("runner should not be invoked when run_id is None")

    import galaxy.ai.workflow_ops.autofix.nextflow_runner as runner_mod
    monkeypatch.setattr(runner_mod, "run_nextflow_autofix", fail_if_called)

    node = _make_run_autofix_node(ai_assistant=None)
    result = node({
        "execution_run_id": None,
        "error": "no dispatch happened",
        "autofix_attempts": 0,
    })
    assert called["value"] is False
    assert result["autofix_attempts"] == 1
    assert result["error"] is None
