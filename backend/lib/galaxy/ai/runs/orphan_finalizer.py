"""Orphan finalizer — the completion handler the CompletionPoller calls.

Stage 3c of docs/20260615_RUNS_PERSISTENCE_DESIGN.md. The poller detects
that a Nextflow subprocess exited but no worker drove the post-completion
side effects (because the launching worker was recycled by gunicorn).
This module runs those side effects from any worker.

Scope is deliberately minimal: it handles the safe subset of the
completion path — status update + narrator chat emission + S3 QC
evaluation. Heavier downstream effects (StudyRunLogger, LTM record,
billing tags) still ride the launching worker's process.wait() return
when that worker survives; for orphaned runs they're a future stage.

The handler uses lazy imports so this module has no compile-time
dependency on nextflow_executor.py — keeps the contention surface
small.
"""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from .run_state_store import RunStateStore

log = logging.getLogger(__name__)


def _read_returncode_from_disk(run_record: Dict[str, Any]) -> Tuple[int, bool]:
    """Try to determine returncode from .nextflow.log / trace files.

    Returns (returncode, is_inferred). When we can't tell, returns
    (-1, True) and the caller treats it as a soft-failed orphan.
    """
    log_path = run_record.get("log_path")
    if log_path and os.path.exists(log_path):
        try:
            with open(log_path, "rb") as f:
                # Read last ~8KB — Nextflow writes the exit line near the end
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 8192))
                tail = f.read().decode("utf-8", errors="ignore")
            if "Pipeline completed successfully" in tail or "exit: 0" in tail:
                return 0, True
            for line in tail.splitlines()[::-1]:
                if "exit: " in line:
                    try:
                        return int(line.split("exit: ", 1)[1].split()[0]), True
                    except (ValueError, IndexError):
                        pass
            # If we see explicit failure language, assume non-zero
            if "Pipeline completed with errors" in tail or "Execution aborted" in tail:
                return 1, True
        except Exception as exc:
            log.debug("[orphan_finalizer] log tail read failed for %s: %s",
                      run_record.get("run_id"), exc)
    # Last-resort heuristic: outdir exists with content => success.
    outdir = run_record.get("outdir", "")
    if outdir and not str(outdir).startswith("s3://") and os.path.isdir(outdir):
        try:
            if any(Path(outdir).iterdir()):
                return 0, True
        except Exception:
            pass
    return -1, True


def _emit_narrator(invocation_id: str, kind: str, technical: Dict[str, Any]) -> None:
    """Lazy import of nextflow_executor's narrator. Stays a no-op if the
    import fails (e.g. unit-test contexts that don't have the full
    backend loaded)."""
    try:
        from galaxy.webapps.galaxy.api.nextflow_executor import _narrate_chat
        _narrate_chat(invocation_id, kind, technical)
    except Exception as exc:
        log.debug("[orphan_finalizer] narrator emit skipped: %s", exc)


def _run_s3_qc(run_id: str, run_record: Dict[str, Any]) -> Optional[list]:
    """Lazy import + call into _evaluate_qc_from_s3 (which has our
    fixed SSE callback wiring from commit 45db54b48)."""
    outdir = run_record.get("outdir", "")
    if not str(outdir).startswith("s3://"):
        return None
    try:
        from galaxy.webapps.galaxy.api.nextflow_executor import (
            _evaluate_qc_from_s3, _list_s3_output_files,
        )
        s3_files = _list_s3_output_files(outdir)
        return _evaluate_qc_from_s3(
            run_id=run_id,
            s3_output_files=s3_files,
            workflow_domain=run_record.get("workflow_domain", ""),
            qc_overrides=run_record.get("qc_overrides", {}),
        )
    except Exception as exc:
        log.warning("[orphan_finalizer] S3 QC eval failed for %s: %s", run_id, exc)
        return None


def finalize_orphaned_run(
    store: RunStateStore,
    run_id: str,
    run_record: Dict[str, Any],
) -> None:
    """Completion handler — matches CompletionPoller.CompletionHandler.

    Run from any worker (including one that didn't launch the subprocess).
    Idempotent: the poller's SETNX lock guarantees one finalizer wins.

    Side effects, in order:
      1. Determine returncode from disk artifacts.
      2. Update store status to terminal (succeeded / failed).
      3. Emit narrator workflow.completed / workflow.failed to chat
         (via /internal/sse-inject).
      4. For S3 Batch runs, call _evaluate_qc_from_s3 — which now emits
         autoloop_gate_results / autoloop_update SSE (commit 45db54b48).
      5. Stash S3 outputs + qc_gates back in the store so subsequent
         /api/workflows/runs/<id> reads see the terminal state.
    """
    returncode, _ = _read_returncode_from_disk(run_record)
    final_status = "succeeded" if returncode == 0 else (
        "interrupted" if returncode < 0 else "failed"
    )
    completed_at = time.time()

    # Step 2 — persist terminal status.
    store.update_run(
        run_id,
        status=final_status,
        returncode=returncode,
        completed_at=completed_at,
        finalized_by="orphan_poller",
    )

    # Step 3 — chat narrator.
    invocation_id = run_record.get("invocation_id")
    if invocation_id:
        if final_status == "succeeded":
            _emit_narrator(invocation_id, "workflow.completed",
                           {"run_id": run_id, "returncode": returncode})
        elif final_status == "failed":
            _emit_narrator(invocation_id, "workflow.failed",
                           {"run_id": run_id, "returncode": returncode,
                            "reason": f"exit {returncode}"})
        else:
            _emit_narrator(invocation_id, "workflow.failed",
                           {"run_id": run_id, "reason": "workflow was interrupted"})

    # Step 4–5 — S3 QC + autoloop SSE.
    if final_status == "succeeded":
        qc_gates = _run_s3_qc(run_id, run_record)
        if qc_gates:
            store.update_run(run_id, qc_gates=qc_gates)
            log.info("[orphan_finalizer] %s: %d gate(s) from S3 QC",
                     run_id, len(qc_gates))

    log.info("[orphan_finalizer] %s finalized — status=%s returncode=%d",
             run_id, final_status, returncode)
