# 2026-10-21 — Run-state bugs surfaced by the drug-dev demo re-record

While re-capturing the drug-dev demo assets (ADMET), live ADMET runs on dev
exposed two real run-state bugs. Both are "does it work smoothly" issues: a
successfully-completed ADMET run was being shown to the user as **failed**.
Diagnosed against live runs and fixed at root cause (not worked around).

## Context
Re-recording `outputs.png` (d2 / drug-dev / t3 decks) needs a completed ADMET
run's Results view. Every ADMET run I launched came back **failed** in the UI
despite producing real outputs — which is what led to these two fixes.

---

## Bug 1 — a QC-gate/paused run shown as FAILED (transient divergence)

**Observed (run `47c1633c`):** the reproducibility record read `Status: paused`
while the Findings panel showed "workflow did not complete successfully" and the
footer showed Restart — i.e. two surfaces of the same after-run panel disagreed.

**Root cause (two layers):**
1. Frontend reconciliation (`routes.ts` `GET /api/workflows/runs/:id/status`)
   promoted only `succeeded`/`failed`/`error` (+ orphan-interrupt). It had **no
   branch for Galaxy's `paused`/`cancelled`**, which are set only by the deliberate
   soft/hard cancel. So a halted run never adopted Galaxy's authoritative `paused`.
2. Backend `_run_lookup` returned the launching worker's in-memory `_runs` record
   first; a racing process-exit handler could clobber that to `failed`/`interrupted`
   (the SIGKILL the pause itself sent) before the store's `paused` write landed.

**Fix:**
- `routes.ts`: deliberate-halt propagation branch — adopt Galaxy's `paused`/`cancelled`
  over the prior frontend status; clear the stale failure message. (`3207f46d`)
- `nextflow_executor.py` `_run_lookup`: when in-memory shows a non-deliberate terminal
  (`failed`/`interrupted`/`error`), let a stored `paused`/`cancelled` win. (this session)
- `nextflow-workflow-viewer` passes `paused` through; `findings-card` shows
  "Paused at a QC gate — resume to continue" (not the failed message / spinner).

**Status:** committed + deployed. Note: this divergence is transient — a run that
ultimately fails settles to `failed` in the store (verified: `47c1633c` is now
`failed` on both reads post-restart). The fix is correct hardening for a genuine
sustained pause; positive confirmation needs a run that stays paused.

---

## Bug 2 — a cleanly-completed run SIGKILL'd at shutdown shown as FAILED (the real one)

**Observed (run `f0d735a2`):**
- `completedTasks: 2 / totalTasks: 2`, `failedTasks: 0`, **8 S3 outputs**
- log: **"Execution complete -- Goodbye"**, "Workflow completed"
- but `returncode: -9` (SIGKILL) → backend `interrupted` → UI **`failed`**

The Nextflow workflow **finished successfully**, then the driver JVM was SIGKILL'd
during shutdown; the non-zero/signal exit was treated as a failure.

**Root cause:** the exit-handler salvage (`_looks_like_false_failure`) reads only the
debug `.nextflow.log`, which lacks the task-count summary, so it could not prove
success and left the signal-kill as a failure. (The `PRODUCTION_MD` config-selector
warning in the log is unrelated — benign noise from a shared dev nextflow.config
whose `withName:` selector matches no process in the ADMET workflow.)

**Fix (`nextflow_executor.py`, exit handler):** add a **trace-authoritative salvage** —
read `workflow-trace.txt` (the same source the status API uses for completedTasks/
failedTasks) via `_evaluate_workflow_trace_terminal`; when it shows every task
COMPLETED, 0 FAILED, and the log's completion marker with no failure markers, mark
the run **succeeded** despite the non-zero/signal driver exit. Safe: a genuinely
failed run has FAILED tasks or a log failure marker (`trace_failed=True`), so real
failures are never rescued. Regression test added (`test_nextflow_false_success.py`,
`test_evaluate_trace_terminal_all_completed_is_success`).

**Status:** committed + deployed (`55036052`). **Verification:** a fresh ADMET run
after deploy — _result pending, to be appended_ (expect `completed`, not `failed`).

---

## Verification (fresh ADMET runs post-fix) — INCONCLUSIVE; deeper root cause found

Five consecutive ADMET runs on dev (47c1633c, f0d735a2, a55ab8d3, fa6192ab + one)
ALL ended `failed`, each with **2/2 tasks COMPLETED, 0 FAILED, 8 S3 outputs**.
The Bug-2 salvage did NOT rescue them, and the reason is informative.

Full log of `fa6192ab` (from the status `log_tail`):
```
04:14:22 [SIGTERM handler] Session aborted -- Cause: SIGTERM
04:14:25 WorkflowStatsObserver - Workflow completed > WorkflowStats[succeededCount=2; failedCount=0]
04:14:27 ScriptRunner - > Execution complete -- Goodbye
```
→ The driver is **SIGTERM'd**, Nextflow finishes gracefully (all tasks succeed,
clean "Execution complete"), but the `Session aborted -- Cause: SIGTERM` line is a
member of BOTH failure-marker sets:
- `_NF_LOG_FAILURE_MARKERS` (Bug-2 salvage guard `_log_indicates_nextflow_failure`)
- `_HARD_FAILURE_LOG_MARKERS` (orphan_finalizer `_log_shows_hard_failure`)

So the run is classified `failed` even though it completed. **The Bug-2 salvage is
correctly inert here** (a `Session aborted` marker is a real failure signal in
general); it only helps a pure SIGKILL-with-no-marker case.

### The actual root cause (needs backend logs to close)
Something SIGTERMs the ADMET driver right as it completes. Prime suspect: the
**ADMET QC gate** firing a halt (soft-cancel = SIGTERM) — which ties back to Bug 1
(a QC halt that should surface as `paused`/`completed`, not `failed`). But
`qc_gates: []` (the S3 eval path doesn't emit gate events — see nextflow_executor
~L3579), so the SIGTERM source is NOT confirmable from the API. Resolving it
properly (not a "Session aborted after success" special-case, which would mask the
spurious SIGTERM) requires the dev Galaxy container logs around the SIGTERM.

### CONFIRMED root cause (dev Galaxy logs, /app/galaxy.log)
The SIGTERM is the **ADMET QC gate halt**. The dev log shows the exact chain:
```
[QC Gate] S3 evaluation for fa825572: 1 gate(s)
[workflow.paused] ... terminated_pids=[613379]        # _terminate_run_process → SIGTERM
[Nextflow run fa825572] exit -9 ... all tasks COMPLETED ... — marking succeeded   # my salvage worked
[Nextflow] Downgrading false success for run fa825572 (steps=2, outputs=8)        # re-failed here
```
The QC gate fires a halt AFTER the fast ADMET workflow already finished, so
`_terminate_run_process` SIGTERMs the driver; Nextflow drains + completes, but the
leftover `Session aborted -- Cause: SIGTERM` line is in `_NF_LOG_FAILURE_MARKERS`,
so `_looks_like_false_success` → `_log_indicates_nextflow_failure` **downgrades the
completed run to failed** (repeatedly, on status polls across workers). A QC-gate
verdict on a finished prediction is a **finding**, not an execution failure.

### Fix (committed)
`_log_indicates_nextflow_failure`: a `Session aborted -- Cause: SIGTERM` line is
benign when the log ALSO has Nextflow's clean-completion marker (`Execution
complete -- Goodbye`) and zero failed tasks (`failedCount` not `[1-9]`). A SIGTERM
that interrupted a run mid-flight has neither, so it still fails. 3 regression tests.
(orphan_finalizer's `_HARD_FAILURE_LOG_MARKERS` does NOT include "Session aborted",
so that path was never the culprit and needs no change.)

**Verification:** fresh ADMET run after deploy — _pending, expect `completed`._

## Demo impact
`outputs.png` (d2 / drug-dev / t3) is captured from a completed ADMET Results view —
blocked until Bug 2 is fixed (no ADMET run would complete). `qsar-live-panel.png`
(d1) was already re-captured & swapped (old composer + CN1C phantom-param bug gone).
