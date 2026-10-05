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
import os
import re
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
        batch_check_age_s: float = 300.0,
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
        # Only ask AWS Batch about a run once it's this old — avoids describe_jobs
        # calls on young runs whose local driver is still healthily finalizing.
        self._batch_check_age = max(0.0, float(batch_check_age_s))
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
        age: Optional[float] = None
        started_at = record.get("started_at")
        if isinstance(started_at, (int, float)) and started_at > 0:
            age = time.time() - float(started_at)
            if age < self._min_age:
                return False
        pid = self._store.get_pid(run_id)
        pid_gone = pid is not None and not _pid_exists(int(pid))

        # Staging-phase orphan (local runs only): a run whose launching worker died
        # DURING staging never recorded a PID — set_pid happens only after the
        # Nextflow head launches. pid_gone then stays False forever, and the Batch
        # branch below never fires for a local run (no batch ids), so the run leaks
        # as configuring/running indefinitely. If no PID was ever recorded, it is
        # not a Batch run, and it is older than the grace window, finalize it as an
        # orphan instead of leaking. (2026-10-05 committee review: completion_poller
        # had no finalization path for is_batch=false staging deaths.)
        if (pid is None and not bool(record.get("is_batch"))
                and age is not None and age >= self._batch_check_age):
            pid_gone = True

        batch_status: Optional[str] = None
        if not pid_gone:
            # The local Nextflow driver is still alive (or its PID was never
            # recorded), so it can't be trusted to finalize. For an AWS Batch
            # run the driver's completion callback can silently never fire,
            # leaving the run 'running' forever (the 282-stuck-run bug). Ask
            # AWS Batch directly — the authoritative signal nothing else reads —
            # but only once the run is old enough to avoid hammering the API.
            if age is None or age < self._batch_check_age:
                return False
            batch_status = self._batch_terminal_status(run_id, record)
            if batch_status is None:
                # No Batch ids yet, at least one job still running, or the
                # describe call failed — leave it for a later sweep.
                return False
        # Either the local PID is gone, or every Batch job is terminal.
        if not self._store.acquire_completion_lock(run_id, ttl_s=120):
            return False
        try:
            if batch_status is not None:
                # Hand the authoritative Batch verdict to the finalizer so it
                # doesn't have to infer the returncode from local disk artifacts.
                try:
                    self._store.update_run(run_id, batch_terminal_status=batch_status)
                except Exception:
                    pass
                record["batch_terminal_status"] = batch_status
            self._handler(run_id, record)
            return True
        except Exception:
            # Re-raise so _sweep logs with context.
            raise

    def _batch_terminal_status(self, run_id: str, record: dict) -> Optional[str]:
        """Return 'succeeded'/'failed' iff EVERY AWS Batch job for this run is
        terminal, else None (still running / unknown / error).

        Batch job ids come from the run-state store (persisted on an earlier
        sweep) or, failing that, are scraped from the local .nextflow.log and
        persisted so a later worker/container can still see them after a recycle.
        """
        ids = record.get("batch_job_ids") or []
        if not ids:
            ids = self._scrape_and_persist_batch_ids(run_id, record)
        if not ids:
            return None
        try:
            import boto3  # Galaxy runtime has boto3
            region = (os.environ.get("AWS_REGION")
                      or os.environ.get("AWS_DEFAULT_REGION") or "us-west-2")
            client = boto3.client("batch", region_name=region)
            statuses: list = []
            for i in range(0, len(ids), 100):
                resp = client.describe_jobs(jobs=list(ids[i:i + 100]))
                statuses.extend(j.get("status") for j in resp.get("jobs", []))
        except Exception as exc:
            log.debug("[completion_poller] %s: describe_jobs failed: %s", run_id, exc)
            return None
        if not statuses or any(s not in ("SUCCEEDED", "FAILED") for s in statuses):
            return None  # at least one job still pending/running (or none found)
        return "failed" if any(s == "FAILED" for s in statuses) else "succeeded"

    def _scrape_and_persist_batch_ids(self, run_id: str, record: dict) -> list:
        """Scrape AWS Batch job ids from the run's local .nextflow.log (shared
        across gunicorn workers in the container) and persist them to the store
        (Redis) so they survive a worker/container recycle."""
        try:
            work_base = os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")
            nf_log = os.path.join(work_base, run_id, "work", ".nextflow.log")
            if not os.path.isfile(nf_log):
                return []
            ids: list = []
            seen: set = set()
            pat = re.compile(r"submitted > job=([0-9a-f\-]{36})")
            with open(nf_log, errors="replace") as fh:
                for line in fh:
                    m = pat.search(line)
                    if m and m.group(1) not in seen:
                        seen.add(m.group(1))
                        ids.append(m.group(1))
            if ids:
                try:
                    self._store.update_run(run_id, batch_job_ids=ids)
                except Exception:
                    pass
            return ids
        except Exception as exc:
            log.debug("[completion_poller] %s: scrape batch ids failed: %s", run_id, exc)
            return []
