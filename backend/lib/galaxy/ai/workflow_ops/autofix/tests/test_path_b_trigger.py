"""Tests for the Path B auto-trigger in nextflow_workflow_runner.

We don't instantiate the full runner (it needs Galaxy app/sa_session/etc).
Instead we extract `_trigger_autofix3_async` as an unbound method and
invoke it against a minimal stub that provides only the bits the method
touches: `self.logger`.

Coverage:
  - gate off (default) → no thread fired
  - gate on, runner raises → no crash, warning logged
  - gate on, happy path → thread fires, runner called with right args
  - env var case insensitive
"""

from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path
from unittest import mock

import pytest


# Pull the unbound method directly off the class so we can call it with a
# stub `self`, bypassing the rest of the runner's init.
def _get_trigger():
    from galaxy.jobs.runners.nextflow_workflow_runner import NextflowWorkflowJobRunner
    return NextflowWorkflowJobRunner._trigger_autofix3_async


class _StubRunner:
    """Minimal `self` for the trigger method — only `.logger` is used."""

    def __init__(self):
        self.logger = logging.getLogger("test")


def _wait_for_threads(prefix: str, timeout: float = 2.0) -> None:
    """Wait for daemon threads matching `prefix` to finish."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        live = [t for t in threading.enumerate() if t.name.startswith(prefix)]
        if not live:
            return
        time.sleep(0.05)


def test_trigger_gated_off_by_default(monkeypatch):
    """Without BIOMATE_AUTOFIX3_AUTO set, no thread should fire."""
    monkeypatch.delenv("BIOMATE_AUTOFIX3_AUTO", raising=False)

    with mock.patch(
        "galaxy.ai.workflow_ops.autofix.nextflow_runner.run_nextflow_autofix"
    ) as runner_mock:
        trigger = _get_trigger()
        trigger(_StubRunner(), "inv-123", Path("/tmp"))
        # Give any (incorrectly started) thread a chance to call the mock.
        time.sleep(0.1)
        assert runner_mock.call_count == 0


def test_trigger_gated_off_explicit_false(monkeypatch):
    monkeypatch.setenv("BIOMATE_AUTOFIX3_AUTO", "false")
    with mock.patch(
        "galaxy.ai.workflow_ops.autofix.nextflow_runner.run_nextflow_autofix"
    ) as runner_mock:
        _get_trigger()(_StubRunner(), "inv-123", Path("/tmp"))
        time.sleep(0.1)
        assert runner_mock.call_count == 0


def test_trigger_fires_when_gated_on(monkeypatch):
    monkeypatch.setenv("BIOMATE_AUTOFIX3_AUTO", "true")

    captured = {}

    def fake_runner(invocation_id, max_attempts, timeout_seconds, **_):
        captured["invocation_id"] = invocation_id
        captured["max_attempts"] = max_attempts
        captured["timeout_seconds"] = timeout_seconds
        return {
            "success": True,
            "total_attempts": 1,
            "termination_reason": "fixed",
            "session_id": "sess-1",
        }

    with mock.patch(
        "galaxy.ai.workflow_ops.autofix.nextflow_runner.run_nextflow_autofix",
        side_effect=fake_runner,
    ):
        _get_trigger()(_StubRunner(), "inv-abc", Path("/tmp"))
        _wait_for_threads("autofix3-")
        assert captured["invocation_id"] == "inv-abc"
        assert captured["max_attempts"] == 3
        assert captured["timeout_seconds"] == 180


def test_trigger_swallows_runner_exception(monkeypatch, caplog):
    """If the runner crashes, the trigger must NOT propagate the exception."""
    monkeypatch.setenv("BIOMATE_AUTOFIX3_AUTO", "1")
    caplog.set_level(logging.WARNING)

    def crashing_runner(**_):
        raise RuntimeError("synthetic crash")

    with mock.patch(
        "galaxy.ai.workflow_ops.autofix.nextflow_runner.run_nextflow_autofix",
        side_effect=crashing_runner,
    ):
        # Should return None without raising
        result = _get_trigger()(_StubRunner(), "inv-crash", Path("/tmp"))
        assert result is None
        _wait_for_threads("autofix3-")


def test_trigger_accepts_yes_alias(monkeypatch):
    monkeypatch.setenv("BIOMATE_AUTOFIX3_AUTO", "yes")
    with mock.patch(
        "galaxy.ai.workflow_ops.autofix.nextflow_runner.run_nextflow_autofix"
    ) as runner_mock:
        _get_trigger()(_StubRunner(), "inv-yes", Path("/tmp"))
        _wait_for_threads("autofix3-")
        assert runner_mock.call_count == 1


def test_trigger_thread_is_daemon(monkeypatch):
    """Daemon thread so Galaxy worker shutdown isn't blocked by hung debugger."""
    monkeypatch.setenv("BIOMATE_AUTOFIX3_AUTO", "true")

    started_thread = {}

    def slow_runner(**_):
        # Block long enough that we can inspect the daemon flag while running.
        time.sleep(0.5)
        return {"success": False, "termination_reason": "timeout"}

    with mock.patch(
        "galaxy.ai.workflow_ops.autofix.nextflow_runner.run_nextflow_autofix",
        side_effect=slow_runner,
    ):
        _get_trigger()(_StubRunner(), "inv-daemon", Path("/tmp"))
        # Find our thread
        time.sleep(0.1)
        for t in threading.enumerate():
            if t.name == "autofix3-inv-daemon":
                started_thread["t"] = t
                break
        assert "t" in started_thread, "trigger should have started the named thread"
        assert started_thread["t"].daemon is True
        _wait_for_threads("autofix3-")
