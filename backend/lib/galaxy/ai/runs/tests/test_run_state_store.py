"""Tests for InMemoryRunStateStore (Stage 1).

Redis variant + recycle-survival integration test land in Stage 3.
"""

from galaxy.ai.runs.run_state_store import (
    InMemoryRunStateStore,
    reset_run_state_store,
    get_run_state_store,
)


def test_set_get_run_roundtrip():
    s = InMemoryRunStateStore()
    s.set_run("r1", {"status": "running", "outdir": "/tmp/x"})
    assert s.get_run("r1") == {"status": "running", "outdir": "/tmp/x"}


def test_get_run_returns_copy():
    s = InMemoryRunStateStore()
    s.set_run("r1", {"status": "running"})
    snap = s.get_run("r1")
    snap["status"] = "completed"
    # Mutating the snapshot must not change the store.
    assert s.get_run("r1")["status"] == "running"


def test_update_run_merges_fields():
    s = InMemoryRunStateStore()
    s.set_run("r1", {"status": "running", "returncode": None})
    s.update_run("r1", status="completed", returncode=0)
    assert s.get_run("r1") == {"status": "completed", "returncode": 0}


def test_update_run_is_noop_for_missing_id():
    """Matches existing `if run_id in _runs:` guarded writes."""
    s = InMemoryRunStateStore()
    s.update_run("ghost", status="completed")
    assert s.get_run("ghost") is None


def test_list_active_runs_excludes_terminal():
    s = InMemoryRunStateStore()
    s.set_run("r1", {"status": "running"})
    s.set_run("r2", {"status": "completed"})
    s.set_run("r3", {"status": "failed"})
    s.set_run("r4", {"status": "queued"})
    active = set(s.list_active_runs())
    assert active == {"r1", "r4"}


def test_pid_lifecycle():
    s = InMemoryRunStateStore()
    s.set_pid("r1", 12345)
    assert s.get_pid("r1") == 12345
    s.delete_run("r1")
    assert s.get_pid("r1") is None


def test_completion_lock_is_exclusive():
    s = InMemoryRunStateStore()
    assert s.acquire_completion_lock("r1") is True
    assert s.acquire_completion_lock("r1") is False  # held
    # Another run is independent.
    assert s.acquire_completion_lock("r2") is True


def test_singleton_env_var_redis_falls_back_to_memory(monkeypatch):
    """Until Stage 3 lands, RUN_STATE_STORE=redis must not crash —
    it must transparently fall back to InMemory so the env var can be
    set on dev now without breaking anything."""
    reset_run_state_store()
    monkeypatch.setenv("RUN_STATE_STORE", "redis")
    s = get_run_state_store()
    assert isinstance(s, InMemoryRunStateStore)
    reset_run_state_store()


def test_singleton_default_is_memory(monkeypatch):
    reset_run_state_store()
    monkeypatch.delenv("RUN_STATE_STORE", raising=False)
    s = get_run_state_store()
    assert isinstance(s, InMemoryRunStateStore)
    reset_run_state_store()
