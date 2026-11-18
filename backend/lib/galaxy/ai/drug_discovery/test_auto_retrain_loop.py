"""
Cross-worker coordination for the DMTA auto-retrain background loop.

Under gunicorn --workers=N the loop registry must be shared, or N workers each run
a duplicate daemon and /retrain/status is wrong on most polls. These tests use a
minimal fake Redis to prove the Redis lease makes exactly one worker own the loop,
that any worker can stop it, that is_loop_running is correct from any worker, and
that the in-process fallback still works when Redis is absent.
"""
import galaxy.ai.drug_discovery.auto_retrain as ar


class _FakeRedis:
    """Just the ops the lease uses, with SET NX semantics (no real TTL)."""
    def __init__(self):
        self.d = {}
    def set(self, k, v, nx=False, ex=None):
        if nx and k in self.d:
            return None
        self.d[k] = v
        return True
    def get(self, k):
        return self.d.get(k)
    def delete(self, *ks):
        for k in ks:
            self.d.pop(k, None)
        return len(ks)
    def exists(self, k):
        return 1 if k in self.d else 0
    def expire(self, k, ttl):
        return True
    def ping(self):
        return True


def _reset():
    ar._active_loops.clear()
    ar._loop_stop_events.clear()


def test_lease_makes_exactly_one_worker_own_the_loop(monkeypatch):
    fake = _FakeRedis()
    monkeypatch.setattr(ar, "_loop_redis", lambda: fake)
    _reset()
    cid = "lease-one-owner"

    # Worker A starts → wins the lease, runs the daemon.
    ar.start_background_loop(":memory:", cid, check_interval_s=3600)
    assert ar.is_loop_running(cid) is True
    assert fake.exists(ar._lease_key(cid))
    owner = fake.get(ar._lease_key(cid))

    # Worker B (a different process → empty local registry, same Redis) must NOT
    # start a second daemon while the lease is held.
    _reset()  # mimic worker B's own in-process registry
    ar.start_background_loop(":memory:", cid, check_interval_s=3600)
    assert cid not in ar._active_loops            # no second daemon on worker B
    assert fake.get(ar._lease_key(cid)) == owner  # lease owner unchanged


def test_stop_and_status_work_from_any_worker(monkeypatch):
    fake = _FakeRedis()
    monkeypatch.setattr(ar, "_loop_redis", lambda: fake)
    _reset()
    cid = "cross-worker-stop"

    # No lease yet → not running, from any worker.
    assert ar.is_loop_running(cid) is False

    # Lease present (set by whichever worker owns it) → running, read from here.
    fake.set(ar._lease_key(cid), "tok-from-another-worker")
    assert ar.is_loop_running(cid) is True

    # Stop from THIS worker (which does not own the thread) still signals a stop.
    ar.stop_background_loop(cid)
    assert fake.exists(ar._stop_key(cid))


def test_fallback_in_process_when_no_redis(monkeypatch):
    monkeypatch.setattr(ar, "_loop_redis", lambda: None)
    _reset()
    cid = "no-redis"
    assert ar.is_loop_running(cid) is False
    ar.start_background_loop(":memory:", cid, check_interval_s=3600)
    assert ar.is_loop_running(cid) is True   # this worker's in-process thread
    # Idempotent on the same worker.
    ar.start_background_loop(":memory:", cid, check_interval_s=3600)
    ar.stop_background_loop(cid)              # sets the local stop event (no raise)
