"""RunStateStore — abstraction over the per-run state previously held
in the module-level `_runs` dict in nextflow_executor.py.

Stage 1 of the migration described in
docs/20260615_RUNS_PERSISTENCE_DESIGN.md:

  - Protocol + InMemoryRunStateStore land first (this file).
  - Existing call sites continue to use the module-level `_runs` dict.
  - One new call site in nextflow_executor.py mirror-writes to the
    store, exercising the InMemory impl without changing semantics.

Stage 2 will replace the 57 in-process call sites with store calls.
Stage 3 adds the Redis-backed impl + completion poller.

The Popen handle is deliberately NOT part of this interface — see the
design doc. We track PID instead and rely on psutil/pid checks plus
the Nextflow trace/log files to determine completion from any worker.
"""

from __future__ import annotations

import os
import threading
import time
from typing import Any, Optional, Protocol, runtime_checkable


@runtime_checkable
class RunStateStore(Protocol):
    """Per-run state for Nextflow / CryoSPARC executors.

    Implementations: InMemoryRunStateStore (this file), RedisRunStateStore
    (added in Stage 3). Selection via env var RUN_STATE_STORE.
    """

    def set_run(self, run_id: str, fields: dict) -> None:
        """Create or overwrite the run record. Adds run to the active
        set if status is non-terminal."""
        ...

    def update_run(self, run_id: str, **fields: Any) -> None:
        """Merge fields into an existing run record. No-op if the
        record does not exist (matches current `_runs[]` semantics
        where `if run_id in _runs` guards writes)."""
        ...

    def get_run(self, run_id: str) -> Optional[dict]:
        """Return a copy of the run record, or None if not found."""
        ...

    def delete_run(self, run_id: str) -> None:
        """Remove the run record. Also removes from active set + PID."""
        ...

    def list_active_runs(self) -> list[str]:
        """Return run_ids whose status is non-terminal.

        Used by the completion poller (Stage 3).
        """
        ...

    def set_pid(self, run_id: str, pid: int) -> None:
        """Record the detached subprocess PID. Used by the completion
        poller to detect process exit via psutil.pid_exists()."""
        ...

    def get_pid(self, run_id: str) -> Optional[int]:
        """Return the recorded PID, or None if not set / cleared."""
        ...

    def acquire_completion_lock(self, run_id: str, ttl_s: int = 60) -> bool:
        """SETNX-style lock so only one worker runs completion per run.

        Returns True if this caller acquired the lock; False if another
        caller already holds it. Stage 3 adds a Redis impl; the
        in-memory variant uses a threading.Lock plus a timestamp.
        """
        ...


# Terminal statuses (mirror existing nextflow_executor semantics).
_TERMINAL = frozenset({
    "completed", "succeeded", "failed", "interrupted",
    "cancelled", "paused", "ok", "error",
})


class InMemoryRunStateStore:
    """Default impl — semantically equivalent to the existing
    `_runs[]` dict + `_runs_lock`. Use this in tests, in local dev,
    and as the fallback if Redis is unreachable.
    """

    def __init__(self) -> None:
        self._runs: dict[str, dict] = {}
        self._pids: dict[str, int] = {}
        self._completion_locks: dict[str, float] = {}  # run_id → expiry
        self._lock = threading.Lock()

    def set_run(self, run_id: str, fields: dict) -> None:
        with self._lock:
            self._runs[run_id] = dict(fields)

    def update_run(self, run_id: str, **fields: Any) -> None:
        with self._lock:
            if run_id in self._runs:
                self._runs[run_id].update(fields)

    def get_run(self, run_id: str) -> Optional[dict]:
        with self._lock:
            r = self._runs.get(run_id)
            return dict(r) if r is not None else None

    def delete_run(self, run_id: str) -> None:
        with self._lock:
            self._runs.pop(run_id, None)
            self._pids.pop(run_id, None)
            self._completion_locks.pop(run_id, None)

    def list_active_runs(self) -> list[str]:
        with self._lock:
            return [
                rid for rid, r in self._runs.items()
                if r.get("status") not in _TERMINAL
            ]

    def set_pid(self, run_id: str, pid: int) -> None:
        with self._lock:
            self._pids[run_id] = int(pid)

    def get_pid(self, run_id: str) -> Optional[int]:
        with self._lock:
            return self._pids.get(run_id)

    def acquire_completion_lock(self, run_id: str, ttl_s: int = 60) -> bool:
        now = time.time()
        with self._lock:
            expiry = self._completion_locks.get(run_id, 0.0)
            if expiry > now:
                return False
            self._completion_locks[run_id] = now + ttl_s
            return True


# ─── Redis impl ─────────────────────────────────────────────────────
# Mirrors the billing pattern at
# backend/lib/galaxy/ai/billing/core/realtime_cost_service.py: lazy
# client construction, decode_responses=True for str values, JSON-encode
# any structured field (dict/list) since Redis hashes are flat str→str.
# TTL = 7 days on run records (matches study log retention).

_RUN_KEY = "nextflow:run:{run_id}"
_ACTIVE_SET_KEY = "nextflow:runs:active"
_PID_KEY = "nextflow:run:{run_id}:pid"
_LOCK_KEY = "nextflow:run:{run_id}:completing"
_RUN_TTL_S = 7 * 24 * 3600


class RedisRunStateStore:
    """Production impl — backs _runs[] state with AWS ElastiCache so
    the in-memory dict can be freely wiped by gunicorn worker recycles
    without losing run state. Cross-worker visibility is automatic since
    every worker reads the same Redis keys.

    Implementation notes:
      - All fields stored as JSON-encoded strings in a Redis hash to
        preserve nested dicts/lists losslessly.
      - active runs tracked in a SET for O(1) `list_active_runs()`.
      - completion lock via SETNX with TTL — multiple poller threads
        across workers race for it; loser skips.
      - PID stored separately so the poller can `psutil.pid_exists()`
        without deserializing the full record.
    """

    def __init__(self, redis_client) -> None:
        self._r = redis_client

    @staticmethod
    def _encode(fields: dict) -> dict:
        """Convert a fields dict to a Redis-safe HASH payload."""
        return {
            k: (
                v if isinstance(v, str)
                else (str(v) if isinstance(v, (int, float, bool)) and not isinstance(v, bool)
                      else _json_dumps(v))
            )
            for k, v in fields.items()
        }

    @staticmethod
    def _decode(payload: dict) -> dict:
        """Best-effort decode: anything that round-trips as JSON gets
        deserialized; everything else stays a string. Designed to be
        symmetric with _encode for nested dicts/lists."""
        out: dict = {}
        for k, v in payload.items():
            try:
                out[k] = _json_loads(v)
            except Exception:
                out[k] = v
        return out

    def set_run(self, run_id: str, fields: dict) -> None:
        key = _RUN_KEY.format(run_id=run_id)
        pipe = self._r.pipeline()
        # Atomic replace: delete then HSET so stale fields don't linger.
        pipe.delete(key)
        if fields:
            pipe.hset(key, mapping=self._encode(fields))
            pipe.expire(key, _RUN_TTL_S)
        if str(fields.get("status", "")).lower() not in _TERMINAL:
            pipe.sadd(_ACTIVE_SET_KEY, run_id)
        pipe.execute()

    def update_run(self, run_id: str, **fields) -> None:
        if not fields:
            return
        key = _RUN_KEY.format(run_id=run_id)
        # Match in-memory semantics: no-op if record doesn't exist.
        if not self._r.exists(key):
            return
        pipe = self._r.pipeline()
        pipe.hset(key, mapping=self._encode(fields))
        pipe.expire(key, _RUN_TTL_S)
        status = fields.get("status")
        if status is not None:
            if str(status).lower() in _TERMINAL:
                pipe.srem(_ACTIVE_SET_KEY, run_id)
            else:
                pipe.sadd(_ACTIVE_SET_KEY, run_id)
        pipe.execute()

    def get_run(self, run_id: str) -> Optional[dict]:
        key = _RUN_KEY.format(run_id=run_id)
        payload = self._r.hgetall(key)
        if not payload:
            return None
        return self._decode(payload)

    def delete_run(self, run_id: str) -> None:
        pipe = self._r.pipeline()
        pipe.delete(_RUN_KEY.format(run_id=run_id))
        pipe.delete(_PID_KEY.format(run_id=run_id))
        pipe.delete(_LOCK_KEY.format(run_id=run_id))
        pipe.srem(_ACTIVE_SET_KEY, run_id)
        pipe.execute()

    def list_active_runs(self) -> list[str]:
        members = self._r.smembers(_ACTIVE_SET_KEY)
        return list(members) if members else []

    def set_pid(self, run_id: str, pid: int) -> None:
        self._r.set(_PID_KEY.format(run_id=run_id), int(pid), ex=_RUN_TTL_S)

    def get_pid(self, run_id: str) -> Optional[int]:
        v = self._r.get(_PID_KEY.format(run_id=run_id))
        return int(v) if v is not None else None

    def acquire_completion_lock(self, run_id: str, ttl_s: int = 60) -> bool:
        # SETNX with EX — only first caller in the TTL window succeeds.
        ok = self._r.set(
            _LOCK_KEY.format(run_id=run_id),
            value="1",
            nx=True,
            ex=ttl_s,
        )
        return bool(ok)


def _json_dumps(obj):
    import json as _json
    return _json.dumps(obj, default=str)


def _json_loads(s):
    import json as _json
    # If it doesn't look like JSON, raise so caller falls through to str.
    if not isinstance(s, str) or not s or s[0] not in "{[\"0123456789-tfn":
        raise ValueError("not json-ish")
    return _json.loads(s)


# Module-level singleton — created lazily on first access so the env
# var is consulted at runtime, not at import time. Tests can call
# reset_run_state_store() to swap in a fresh InMemory instance.

_store_singleton: Optional[RunStateStore] = None
_store_lock = threading.Lock()


def get_run_state_store() -> RunStateStore:
    """Return the process-wide RunStateStore singleton.

    Selection:
      RUN_STATE_STORE=memory (default) → InMemoryRunStateStore
      RUN_STATE_STORE=redis            → RedisRunStateStore backed by
                                         REDIS_URL (AWS ElastiCache)
    """
    global _store_singleton
    if _store_singleton is not None:
        return _store_singleton
    with _store_lock:
        if _store_singleton is not None:
            return _store_singleton
        backend = os.environ.get("RUN_STATE_STORE", "memory").strip().lower()
        if backend == "redis":
            redis_url = os.environ.get("REDIS_URL", "").strip()
            try:
                import redis as _redis_lib  # type: ignore
                if not redis_url:
                    raise RuntimeError("REDIS_URL env var is empty")
                client = _redis_lib.from_url(
                    redis_url, decode_responses=True, socket_timeout=5
                )
                # Quick liveness check — if Redis is unreachable, fall back
                # to InMemory instead of crashing the worker on startup.
                client.ping()
                _store_singleton = RedisRunStateStore(client)
                import logging
                logging.getLogger(__name__).info(
                    "RunStateStore: Redis backend active at %s", redis_url
                )
                return _store_singleton
            except Exception as exc:
                import logging
                logging.getLogger(__name__).warning(
                    "RunStateStore: Redis unreachable (%s); falling back "
                    "to InMemoryRunStateStore. Long workflows may lose "
                    "state on worker recycle. See "
                    "docs/20260615_RUNS_PERSISTENCE_DESIGN.md.", exc
                )
        _store_singleton = InMemoryRunStateStore()
        return _store_singleton


def reset_run_state_store() -> None:
    """Test hook. Drops the singleton so the next get_run_state_store()
    call constructs a fresh instance."""
    global _store_singleton
    with _store_lock:
        _store_singleton = None
