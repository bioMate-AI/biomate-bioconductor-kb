"""Tests for CompletionPoller.

These verify the poller's policy (when to trigger completion, when to
skip, idempotency across simulated workers). The actual completion
handler is mocked; wiring it to nextflow_executor._evaluate_qc_from_s3
is Stage 3c.
"""

import os
import subprocess
import sys
import time

import pytest

from galaxy.ai.runs.run_state_store import InMemoryRunStateStore
from galaxy.ai.runs.completion_poller import CompletionPoller


def _spawn_short_lived(seconds: float = 0.05) -> int:
    """Start a detached subprocess that exits after `seconds`. Returns
    its PID. The subprocess is intentionally created with
    start_new_session=True to mirror the production launch pattern."""
    proc = subprocess.Popen(
        [sys.executable, "-c", f"import time; time.sleep({seconds})"],
        start_new_session=True,
    )
    return proc.pid


def _record(status: str = "running", started_at: float | None = None) -> dict:
    return {
        "status": status,
        "outdir": "/tmp/x",
        "started_at": started_at if started_at is not None else (time.time() - 30),
    }


def test_alive_process_does_not_trigger():
    """A subprocess that's still running must NOT fire completion."""
    store = InMemoryRunStateStore()
    handler_calls = []
    poller = CompletionPoller(store, lambda rid, rec: handler_calls.append(rid))

    # A long-lived subprocess that will outlast the sweep
    proc = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(60)"],
        start_new_session=True,
    )
    try:
        store.set_run("r1", _record("running"))
        store.set_pid("r1", proc.pid)
        triggered = poller.tick_once()
        assert triggered == 0
        assert handler_calls == []
    finally:
        proc.kill()
        proc.wait(timeout=2)


def test_exited_process_triggers_completion():
    store = InMemoryRunStateStore()
    handler_calls = []
    poller = CompletionPoller(store, lambda rid, rec: handler_calls.append((rid, rec.get("status"))))

    # Subprocess that exits quickly
    pid = _spawn_short_lived(0.05)
    store.set_run("r1", _record("running"))
    store.set_pid("r1", pid)
    # Wait for subprocess to actually exit
    time.sleep(0.3)
    # And reap it so psutil reflects exit promptly
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass

    triggered = poller.tick_once()
    assert triggered == 1
    assert handler_calls == [("r1", "running")]


def test_completion_lock_prevents_double_fire():
    """Simulate two workers polling concurrently — only one should
    actually fire the handler for the same run."""
    store = InMemoryRunStateStore()
    handler_calls = []
    poller_a = CompletionPoller(store, lambda rid, rec: handler_calls.append(("a", rid)))
    poller_b = CompletionPoller(store, lambda rid, rec: handler_calls.append(("b", rid)))

    pid = _spawn_short_lived(0.05)
    store.set_run("r1", _record("running"))
    store.set_pid("r1", pid)
    time.sleep(0.3)
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass

    triggered_a = poller_a.tick_once()
    triggered_b = poller_b.tick_once()
    # Exactly one worker fires
    assert (triggered_a + triggered_b) == 1
    assert len(handler_calls) == 1


def test_terminal_run_is_excluded_from_active_set():
    """A run already at terminal status must not be considered. The
    poller depends on store.list_active_runs() filtering it out."""
    store = InMemoryRunStateStore()
    handler_calls = []
    poller = CompletionPoller(store, lambda rid, rec: handler_calls.append(rid))

    store.set_run("r1", _record("completed"))
    store.set_pid("r1", 999999)  # nonexistent PID, but status is terminal
    assert "r1" not in store.list_active_runs()

    triggered = poller.tick_once()
    assert triggered == 0
    assert handler_calls == []


def test_missing_pid_skips_run():
    """If we don't know the PID we can't decide — must skip, not fire."""
    store = InMemoryRunStateStore()
    handler_calls = []
    poller = CompletionPoller(store, lambda rid, rec: handler_calls.append(rid))

    store.set_run("r1", _record("running"))
    # Deliberately do NOT set_pid

    triggered = poller.tick_once()
    assert triggered == 0
    assert handler_calls == []


def test_young_run_is_skipped():
    """A run that started <min_run_age_s seconds ago must be skipped to
    avoid racing the launching worker."""
    store = InMemoryRunStateStore()
    handler_calls = []
    poller = CompletionPoller(
        store, lambda rid, rec: handler_calls.append(rid), min_run_age_s=5.0
    )

    # Set started_at to "just now" — younger than 5s
    store.set_run("r1", _record("running", started_at=time.time() - 1.0))
    store.set_pid("r1", 999999)  # nonexistent — would otherwise trigger

    triggered = poller.tick_once()
    assert triggered == 0
    assert handler_calls == []


def test_handler_exception_does_not_kill_poller():
    """If the completion handler raises, the poller must continue and
    NOT mark the run as done — the lock TTL will allow a retry."""
    store = InMemoryRunStateStore()

    def boom(rid, rec):
        raise RuntimeError("simulated handler failure")

    poller = CompletionPoller(store, boom)
    pid = _spawn_short_lived(0.05)
    store.set_run("r1", _record("running"))
    store.set_pid("r1", pid)
    time.sleep(0.3)
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass

    # Should not raise — _sweep swallows handler errors with logging
    triggered = poller.tick_once()
    # triggered counts attempts that ran the handler without exception;
    # a raising handler returns 0 here per the contract.
    assert triggered == 0
    # And the lock is held (we don't release on exception) — second
    # call doesn't double-fire even if process is still gone
    assert poller.tick_once() == 0


def test_start_stop_thread_lifecycle():
    """The daemon thread must spin up and down cleanly."""
    store = InMemoryRunStateStore()
    poller = CompletionPoller(store, lambda rid, rec: None, interval_s=0.1)
    poller.start()
    time.sleep(0.3)
    poller.stop(join_timeout_s=1.0)
    # Idempotent double-start is fine
    poller.start()
    poller.stop()
