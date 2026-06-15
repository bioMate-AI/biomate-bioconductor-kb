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
_TERMINAL = frozenset({"completed", "failed", "cancelled", "paused", "ok", "error"})


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


# Module-level singleton — created lazily on first access so the env
# var is consulted at runtime, not at import time. Tests can call
# reset_run_state_store() to swap in a fresh InMemory instance.

_store_singleton: Optional[RunStateStore] = None
_store_lock = threading.Lock()


def get_run_state_store() -> RunStateStore:
    """Return the process-wide RunStateStore singleton.

    Selection:
      RUN_STATE_STORE=memory (default) → InMemoryRunStateStore
      RUN_STATE_STORE=redis            → RedisRunStateStore (Stage 3)
    """
    global _store_singleton
    if _store_singleton is not None:
        return _store_singleton
    with _store_lock:
        if _store_singleton is not None:
            return _store_singleton
        backend = os.environ.get("RUN_STATE_STORE", "memory").strip().lower()
        if backend == "redis":
            # Stage 3 — not yet implemented. Fall back to InMemory with a
            # warning so the env-var is forward-compatible and dev can
            # set it now without breaking anything.
            import logging
            logging.getLogger(__name__).warning(
                "RUN_STATE_STORE=redis requested but RedisRunStateStore "
                "is not implemented yet (Stage 3). Falling back to "
                "InMemoryRunStateStore. See "
                "docs/20260615_RUNS_PERSISTENCE_DESIGN.md."
            )
        _store_singleton = InMemoryRunStateStore()
        return _store_singleton


def reset_run_state_store() -> None:
    """Test hook. Drops the singleton so the next get_run_state_store()
    call constructs a fresh instance."""
    global _store_singleton
    with _store_lock:
        _store_singleton = None
