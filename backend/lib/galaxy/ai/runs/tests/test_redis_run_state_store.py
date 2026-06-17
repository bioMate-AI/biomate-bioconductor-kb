"""Tests for RedisRunStateStore (Stage 3).

Uses fakeredis to exercise the same contract as InMemoryRunStateStore.
"""

import fakeredis
import pytest

from galaxy.ai.runs.run_state_store import RedisRunStateStore


@pytest.fixture
def store() -> RedisRunStateStore:
    return RedisRunStateStore(fakeredis.FakeRedis(decode_responses=True))


def test_set_get_run_roundtrip(store):
    store.set_run("r1", {"status": "running", "outdir": "/tmp/x", "qc_overrides": {}})
    assert store.get_run("r1") == {
        "status": "running",
        "outdir": "/tmp/x",
        "qc_overrides": {},
    }


def test_nested_fields_roundtrip(store):
    """Dicts and lists must survive the JSON-encode round-trip."""
    fields = {
        "status": "running",
        "qc_overrides": {"hERG_IC50_uM": 1.5, "DILI": "strict"},
        "required_modules": ["docker", "nextflow"],
        "accession_params": {"smiles": "CCO"},
    }
    store.set_run("r1", fields)
    assert store.get_run("r1") == fields


def test_update_run_merges_fields(store):
    store.set_run("r1", {"status": "running", "returncode": None})
    store.update_run("r1", status="completed", returncode=0)
    assert store.get_run("r1") == {"status": "completed", "returncode": 0}


def test_update_run_is_noop_for_missing_id(store):
    store.update_run("ghost", status="completed")
    assert store.get_run("ghost") is None


def test_list_active_runs_excludes_terminal(store):
    store.set_run("r1", {"status": "running"})
    store.set_run("r2", {"status": "completed"})
    store.set_run("r3", {"status": "failed"})
    store.set_run("r4", {"status": "queued"})
    assert set(store.list_active_runs()) == {"r1", "r4"}


def test_update_moves_run_to_terminal(store):
    """When a run transitions to terminal, list_active_runs must drop it."""
    store.set_run("r1", {"status": "running"})
    assert "r1" in store.list_active_runs()
    store.update_run("r1", status="completed", completed_at=12345)
    assert "r1" not in store.list_active_runs()


def test_pid_lifecycle(store):
    store.set_pid("r1", 12345)
    assert store.get_pid("r1") == 12345
    store.delete_run("r1")
    assert store.get_pid("r1") is None
    assert store.get_run("r1") is None


def test_completion_lock_is_exclusive(store):
    assert store.acquire_completion_lock("r1") is True
    assert store.acquire_completion_lock("r1") is False
    # Different run is independent.
    assert store.acquire_completion_lock("r2") is True


def test_completion_lock_expires(store):
    """SETNX with EX=1 must allow re-acquire after the TTL window."""
    import time
    assert store.acquire_completion_lock("r1", ttl_s=1) is True
    assert store.acquire_completion_lock("r1", ttl_s=1) is False
    time.sleep(1.2)
    assert store.acquire_completion_lock("r1", ttl_s=1) is True


def test_set_run_replaces_stale_fields(store):
    """A second set_run must not leave fields from the first record."""
    store.set_run("r1", {"status": "running", "outdir": "/tmp/x", "extra": "yes"})
    store.set_run("r1", {"status": "completed", "outdir": "/tmp/x"})
    snap = store.get_run("r1")
    assert snap == {"status": "completed", "outdir": "/tmp/x"}
    assert "extra" not in snap


def test_get_run_returns_none_for_missing(store):
    assert store.get_run("ghost") is None
