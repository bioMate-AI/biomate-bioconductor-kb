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


# Nextflow log markers that mean the *session* failed even when every
# DISPATCHED task shows COMPLETED/exit 0 in the trace. The canonical case is a
# process whose `script:` block fails to compile (e.g. an unescaped `$` in an
# embedded R/Python heredoc): that process never becomes a task, so it never
# appears in the trace, yet Nextflow aborts the run with returncode=1. Trusting
# the trace's "all tasks OK ⟹ success" heuristic here silently reports a broken
# run as succeeded. These markers are authoritative for failure.
_HARD_FAILURE_LOG_MARKERS = (
    "script contains error(s)",
    "ProcessUnrecoverableException",
    "Execution cancelled",
    "Execution aborted",
    "Pipeline completed with errors",
    "ERROR ~",
)


def _log_shows_hard_failure(log_path: Optional[str]) -> bool:
    """True when the Nextflow launcher log contains a definitive session-abort
    marker. Reads a generous tail because the abort banner lands after the last
    task's output. Best-effort: any read error returns False (fall through)."""
    if not log_path or not os.path.exists(log_path):
        return False
    try:
        with open(log_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 32768))  # last 32KB — abort banner is near EOF
            tail = f.read().decode("utf-8", errors="ignore")
        return any(m in tail for m in _HARD_FAILURE_LOG_MARKERS)
    except Exception as exc:  # pragma: no cover — defensive
        log.debug("[orphan_finalizer] hard-failure log scan failed: %s", exc)
        return False


def _read_returncode_from_disk(run_record: Dict[str, Any]) -> Tuple[int, bool]:
    """Try to determine returncode from .nextflow.log / trace files.

    Returns (returncode, is_inferred). When we can't tell, returns
    (-1, True) and the caller treats it as a soft-failed orphan.

    Detection order (most-reliable first):
      1. Nextflow trace file — all tasks COMPLETED with exit 0 ⟹ success.
      2. stdout log tail — "Pipeline completed successfully" / "exit: 0".
      3. stdout log tail — Nextflow ✔ completion line (Nextflow 25+ omits
         "Pipeline completed successfully" on AWS Batch runs when gunicorn
         recycles before Nextflow writes that line).
      4. S3 outdir: if run_record has s3_output_files ≥ 1 ⟹ success.
      5. Local outdir non-empty ⟹ success.
      6. Fall back to (-1, True) — caller treats as interrupted orphan.
    """
    # ── 0. Authoritative session-abort markers ───────────────────────────────
    # Check the launcher log for a hard-failure banner FIRST. A process that
    # fails at script-compilation never enters the trace, so the trace heuristic
    # below would otherwise see "all tasks COMPLETED exit 0" and wrongly report
    # success (the orphan_finalizer / executor terminal-state disagreement).
    if _log_shows_hard_failure(run_record.get("log_path")):
        log.info("[orphan_finalizer] launcher log shows session-abort marker — failure (rc=1)")
        return 1, True

    # ── 1. Trace file ────────────────────────────────────────────────────────
    trace_path = run_record.get("trace_path")
    if trace_path and os.path.exists(trace_path):
        try:
            lines = Path(trace_path).read_text(encoding="utf-8", errors="ignore").splitlines()
            data_lines = [l for l in lines if l.strip() and not l.startswith("task_id")]
            if data_lines:
                all_ok = True
                any_failed = False
                for dl in data_lines:
                    cols = dl.split("\t")
                    # Trace columns: task_id hash native_id name status exit ...
                    status_col = cols[4].strip() if len(cols) > 4 else ""
                    exit_col   = cols[5].strip() if len(cols) > 5 else ""
                    if status_col.upper() in ("FAILED", "ABORTED"):
                        any_failed = True
                        all_ok = False
                    elif status_col.upper() != "COMPLETED":
                        all_ok = False  # still running or unknown
                    elif exit_col not in ("0", ""):
                        all_ok = False
                if any_failed:
                    return 1, True
                if all_ok and data_lines:
                    log.debug("[orphan_finalizer] trace shows all tasks COMPLETED exit 0 — success")
                    return 0, True
        except Exception as exc:
            log.debug("[orphan_finalizer] trace read failed for %s: %s",
                      run_record.get("run_id"), exc)

    # ── 2 + 3. stdout log tail ────────────────────────────────────────────────
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
            # Nextflow 25+ AWS Batch: ends with "N of N ✔" without the
            # "Pipeline completed successfully" banner when the gunicorn
            # worker recycled before Nextflow finished flushing.
            import re as _re
            if _re.search(r"\d+ of \d+ ✔", tail) and "Pipeline completed with errors" not in tail and "Execution aborted" not in tail:
                log.debug("[orphan_finalizer] log tail shows ✔ completion marker — inferring success")
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

    # ── 4. S3 output files recorded in run record ─────────────────────────────
    if run_record.get("s3_output_files"):
        log.debug("[orphan_finalizer] s3_output_files present — inferring success")
        return 0, True

    # ── 5. Local outdir non-empty ─────────────────────────────────────────────
    outdir = run_record.get("outdir", "")
    if outdir and not str(outdir).startswith("s3://") and os.path.isdir(outdir):
        try:
            if any(Path(outdir).iterdir()):
                return 0, True
        except Exception:
            pass
    return -1, True


def _post_frontend_status(invocation_id: str, status: str, returncode: int,
                          completed_at: float, finalized_by: str) -> None:
    """POST to the frontend's /internal/runs/by-invocation/<inv>/status so the
    execution_runs Postgres row goes from "running" to terminal. Mirrors the
    _post_sse pattern used by the narrator.
    """
    import os, json as _json, urllib.request as _urllib
    frontend_url = os.environ.get("FRONTEND_URL", "http://localhost:5000")
    url = f"{frontend_url}/internal/runs/by-invocation/{invocation_id}/status"
    body = _json.dumps({
        "status": status,
        "returncode": returncode,
        "completed_at": completed_at,
        "finalized_by": finalized_by,
    }).encode("utf-8")
    req = _urllib.Request(url, data=body, headers={"Content-Type": "application/json"})
    with _urllib.urlopen(req, timeout=5) as r:
        if r.status >= 400:
            log.warning("[orphan_finalizer] frontend status push: %s -> HTTP %s",
                        url, r.status)


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

    # Step 3b — push terminal status to the frontend's Postgres execution_runs
    # row so the UI stops showing "running". Without this the L3 poller marks
    # Redis terminal but the frontend page sticks on "running" forever.
    if invocation_id:
        try:
            _post_frontend_status(invocation_id, final_status, returncode,
                                  completed_at, "orphan_poller")
        except Exception as _fe_exc:
            log.debug("[orphan_finalizer] frontend status push failed for inv=%s: %s",
                      invocation_id, _fe_exc)

    # Step 3c — write the durable per-run study log (matches the normal-completion
    # path at nextflow_executor.py:3322). Audit logs were silently missing for
    # every L3-finalized run before this.
    try:
        run_meta = dict(run_record)
        run_meta.update({
            "run_id": run_id,
            "status": final_status,
            "returncode": returncode,
            "completed_at": completed_at,
            "finalized_by": "orphan_poller",
        })
        from galaxy.ai.study_run_logger import StudyRunLogger
        StudyRunLogger.record(run_meta)
    except Exception as _log_err:
        log.debug("[orphan_finalizer] StudyRunLogger write failed for %s: %s",
                  run_id, _log_err)

    # Step 4–5 — S3 QC + autoloop SSE.
    if final_status == "succeeded":
        qc_gates = _run_s3_qc(run_id, run_record)
        if qc_gates:
            store.update_run(run_id, qc_gates=qc_gates)
            log.info("[orphan_finalizer] %s: %d gate(s) from S3 QC",
                     run_id, len(qc_gates))

    log.info("[orphan_finalizer] %s finalized — status=%s returncode=%d",
             run_id, final_status, returncode)
