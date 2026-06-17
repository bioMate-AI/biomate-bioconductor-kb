"""Completion poller — detects orphaned Nextflow subprocesses and
runs the completion path from any gunicorn worker.

The L3 bug we're fixing (see docs/20260615_RUNS_PERSISTENCE_DESIGN.md):
gunicorn recycles its single worker every ~3 min on dev. The detached
Nextflow subprocess (`start_new_session=True`) survives, but the Popen
handle in worker-local _runs[] is lost. The completion path
(_evaluate_qc_from_s3 + SSE emit + LTM record) is gated on
process.wait() in the launching worker, which never returns. Result:
runs stuck in 'running' forever, autoloop SSE never fires, every long
workflow leaks silently.

This poller fills the gap. It runs as a background thread in every
worker; idempotency comes from a Redis SETNX completion lock. Worker A
might launch the run and ride process.wait() to completion. Worker B
(after recycle) sees the same active run in Redis, polls the PID,
detects exit, takes the completion lock, runs the handler. Either path
arrives at the same terminal state.

Stage 3b (this file) ships the poller class with a completion_handler
callable injected at construction. The actual wiring of the handler to
nextflow_executor._evaluate_qc_from_s3 etc. lands in Stage 3c when that
file is quiet.

Usage (target shape):

    from galaxy.ai.runs import get_run_state_store, CompletionPoller

    def _completion_handler(run_id: str, run_record: dict) -> None:
        # Calls into nextflow_executor — wired in Stage 3c
        ...

    poller = CompletionPoller(
        store=get_run_state_store(),
        completion_handler=_completion_handler,
        interval_s=5.0,
    )
    poller.start()  # spawns daemon thread; safe across worker forks
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Callable, Optional

try:
    import psutil  # type: ignore
    _HAS_PSUTIL = True
except ImportError:
    _HAS_PSUTIL = False

from .run_state_store import RunStateStore

log = logging.getLogger(__name__)


def _pid_exists(pid: int) -> bool:
    """psutil if available; fall back to os.kill(pid, 0)."""
    if _HAS_PSUTIL:
        try:
            return psutil.pid_exists(pid)
        except Exception:
            pass
    try:
        import os
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        # PermissionError means the process exists but we can't signal
        # it (different uid). For our purposes that counts as alive.
        return False if isinstance(_exc := None, ProcessLookupError) else True
    except OSError:
        return False


# Type alias: handler signature is (run_id, run_record_snapshot) → None.
# The handler is responsible for: reading outputs, evaluating QC, emitting
# SSE, writing terminal status to the store, doing LTM bookkeeping.
CompletionHandler = Callable[[str, dict], None]


class CompletionPoller:
    """Background thread that detects subprocess exit and triggers
    completion from any worker.

    Idempotent across workers via store.acquire_completion_lock(). Daemon
    thread so it doesn't block worker shutdown — but completion is
    safe-to-retry on the next worker since the lock has a TTL.
    """

    def __init__(
        self,
        store: RunStateStore,
        completion_handler: CompletionHandler,
        interval_s: float = 5.0,
        min_run_age_s: float = 5.0,
    ) -> None:
        """
        Args:
            store:              RunStateStore singleton.
            completion_handler: Callable(run_id, run_record_snapshot)
                                that runs the terminal-state side effects.
                                Stage 3c wires this to
                                nextflow_executor._evaluate_qc_from_s3
                                etc. via a public surface.
            interval_s:         Seconds between polling sweeps. 5s is the
                                design-doc default — short enough to be
                                near-real-time, long enough that the
                                idle cost on Redis + psutil is trivial.
            min_run_age_s:      Don't run completion for a run that
                                started less than this long ago. Guards
                                against false positives when a freshly
                                launched subprocess hasn't been seen by
                                psutil yet.
        """
        self._store = store
        self._handler = completion_handler
        self._interval = max(0.5, float(interval_s))
        self._min_age = max(0.0, float(min_run_age_s))
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._loop,
            name="run-completion-poller",
            daemon=True,
        )
        self._thread.start()
        log.info(
            "[completion_poller] started — interval=%.1fs min_age=%.1fs",
            self._interval, self._min_age,
        )

    def stop(self, join_timeout_s: float = 2.0) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=join_timeout_s)
            self._thread = None

    def tick_once(self) -> int:
        """Public single-sweep entry point — useful for unit tests.

        Returns the number of runs for which completion was triggered
        in this sweep.
        """
        return self._sweep()

    def _loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                self._sweep()
            except Exception as exc:
                # Never let a poller exception kill the thread.
                log.warning("[completion_poller] sweep error: %s", exc)
            if self._stop_event.wait(self._interval):
                break

    def _sweep(self) -> int:
        triggered = 0
        try:
            active = self._store.list_active_runs()
        except Exception as exc:
            log.debug("[completion_poller] list_active_runs failed: %s", exc)
            return 0
        for run_id in active:
            try:
                if self._maybe_complete(run_id):
                    triggered += 1
            except Exception as exc:
                log.warning("[completion_poller] %s: handler error: %s", run_id, exc)
        return triggered

    def _maybe_complete(self, run_id: str) -> bool:
        record = self._store.get_run(run_id)
        if record is None:
            return False
        # Check min age to avoid racing freshly-launched subprocesses.
        started_at = record.get("started_at")
        if isinstance(started_at, (int, float)) and started_at > 0:
            age = time.time() - float(started_at)
            if age < self._min_age:
                return False
        pid = self._store.get_pid(run_id)
        if pid is None:
            # We don't know the PID — either Stage 2a hasn't wired the
            # set_pid call for this run yet, or it was a non-subprocess
            # path (e.g., an external Galaxy invocation). Skip.
            return False
        if _pid_exists(int(pid)):
            return False
        # Process is gone but status is still non-terminal. This is the
        # scenario the L3 bug creates. Take the lock and run completion.
        if not self._store.acquire_completion_lock(run_id, ttl_s=120):
            return False
        try:
            self._handler(run_id, record)
            return True
        except Exception:
            # Re-raise so _sweep logs with context.
            raise
