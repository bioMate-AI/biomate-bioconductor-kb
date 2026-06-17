"""Worker-side bootstrap for the run-state subsystem.

Spawns one CompletionPoller per worker, wired to the orphan finalizer.
Safe to call repeatedly — the poller is a singleton per process.

Stage 3c of docs/20260615_RUNS_PERSISTENCE_DESIGN.md.

Usage from nextflow_executor.py (added in this stage):

    from galaxy.ai.runs.bootstrap import ensure_poller_started
    ensure_poller_started()

Call it from the run-launch path so the first ever workflow on a worker
brings the poller up. Subsequent calls are no-ops.
"""

from __future__ import annotations

import logging
import threading
from typing import Optional

from .completion_poller import CompletionPoller
from .orphan_finalizer import finalize_orphaned_run
from .run_state_store import get_run_state_store

log = logging.getLogger(__name__)

_poller: Optional[CompletionPoller] = None
_bootstrap_lock = threading.Lock()


def ensure_poller_started(interval_s: float = 5.0, min_run_age_s: float = 10.0) -> None:
    """Start the completion poller for this worker, if not already running.

    Idempotent. The longer min_run_age (10s vs the unit-test default 5s)
    gives the launching worker time to drive its own process.wait() return
    before the orphan poller kicks in — minimises duplicate work.
    """
    global _poller
    if _poller is not None:
        return
    with _bootstrap_lock:
        if _poller is not None:
            return
        store = get_run_state_store()
        _poller = CompletionPoller(
            store=store,
            completion_handler=lambda run_id, record: finalize_orphaned_run(
                store=store, run_id=run_id, run_record=record,
            ),
            interval_s=interval_s,
            min_run_age_s=min_run_age_s,
        )
        _poller.start()
        log.info(
            "[runs.bootstrap] completion poller started "
            "(interval=%.1fs min_age=%.1fs)",
            interval_s, min_run_age_s,
        )


def stop_poller() -> None:
    """Test/teardown hook."""
    global _poller
    if _poller is not None:
        _poller.stop()
        _poller = None
