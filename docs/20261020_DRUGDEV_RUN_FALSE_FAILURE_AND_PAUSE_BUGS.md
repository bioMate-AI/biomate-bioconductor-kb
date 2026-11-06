# Drug-dev runs: false-failure on signal-kill + paused-run clobber (2026-10-20)

Found while trying to capture a clean "Completed" ADMET run for the d2 / drug-dev
decks. ADMET runs on dev **never reach a clean Completed** — every run ends
"Failed", blocking the demo capture. Two distinct bugs.

## Bug A — completion thread clobbers a deliberately-paused run (FIXED)
`/api/nextflow/pause` (`nextflow_executor.py:7158`, soft cancel) terminates the
Nextflow process with SIGTERM and sets `status="paused"` so a later `-resume`
works. But the completion thread (`process.wait()` returns `returncode < 0`,
line ~4521) then **overrode** the status to `"interrupted"/"failed"` — so a
user-paused run showed "Failed" and Resume (which needs `status=paused`) was dead.
**Fix:** before classifying a signal-killed run, check the stored status; if it is
`"paused"`, keep it `"paused"` (resumable) instead of interrupted/failed.
py3.9 compiles; only changes behaviour when the run was already deliberately
paused (no risk of faking success / hiding failure). Needs a Batch run to verify
the user pause→resume round-trips.

## RESOLUTION (2026-10-20): Bug B WAS Bug A (fixed)
Deeper tracing showed the ADMET false-failure is the same mechanism as Bug A, not
a separate signal-kill-salvage problem. On a halt-severity QC gate the FRONTEND
calls `/api/workflows/runs/:id/pause` (`nextflow-workflow-viewer.tsx:2220`, default
`pauseAtQcFailures`), which soft-cancels the backend run: `_terminate_run_process`
SIGTERMs the Nextflow process and marks `status="paused"`. The bug: it wrote that
status AFTER the SIGTERM, and the completion thread (process.wait()) wakes the
instant the signal lands and classifies `returncode<0` → interrupted/failed —
racing ahead of the "paused" write and clobbering it → "RUN FAILED", Resume dead.
**Fix:** `_terminate_run_process` now writes `status=paused/cancelled` (+ store)
BEFORE signalling, and the `returncode<0` handler keeps a deliberate paused/
cancelled status. So a gate-halted ADMET run shows **paused (resumable)**; a run
that passes all gates completes cleanly. Needs a Batch run on dev to confirm
paused→resume. (The output-completeness salvage below is no longer the blocker,
but remains a sound defence-in-depth idea.)

## Bug B (original hypothesis) — false-failure on signal-kill with complete outputs
The actual ADMET blocker. Observed on every ADMET capture run:
- The ADMET workflow **completes its compute** — 6 outputs published to S3
  (`toxicity_report.json`, `qc_metrics.json`, `pk_summary.json`, …), the
  "Explore in Jupyter" affordance shows, the QC gate evaluates.
- Yet the panel shows **RUN FAILED**, last log line the benign
  `[SIGTERM handler] WARN nextflow.dag.GraphvizRenderer – Graphviz is required…`.
- The local Nextflow process was **signal-killed** (`returncode < 0`) →
  classified `"interrupted"/"failed"` (line 4521-4552).
- The existing salvage `_looks_like_false_failure` (line 1262) does NOT rescue it:
  it requires the Nextflow log to contain `"execution complete"` + success stats,
  which a process killed during teardown (at the DAG-render step) never wrote —
  even though every output is present.

### Why it matters
- A completed-but-signal-killed run is a **false failure**: all work done, outputs
  published, but marked Failed. This blocks the drug-dev demo "Completed" capture
  and, more importantly, misreports real user runs.
- "Paused on a safety QC gate" is **frontend-only** (`nextflow-workflow-viewer.tsx:2231`,
  gated by `pauseAtQcFailures`); the backend never sets `status="paused"` on a halt,
  so Bug A's fix does not cover this path.

### Open question (needs confirming)
Why is the process signal-killed **systematically** (every run), not just on the
rare gunicorn recycle? Candidates: a per-run wall-clock timeout that fires at the
DAG-render teardown; the auto-loop/QC-halt path terminating the run; a
process-group signal. Confirm from the dev Galaxy logs around the SIGTERM
timestamp before fixing.

### Fix options (pick after confirming the SIGTERM origin)
1. **Recognise signal-kill + complete outputs as success.** Loosen the salvage so
   a `returncode < 0` run whose **expected** outputs are all present in S3
   (success by output-completeness, not just a log marker) is marked `succeeded`.
   Risk: a run killed mid-way with partial outputs must NOT be faked — gate on the
   workflow's declared output set, or on the Batch job's own terminal state
   (SUCCEEDED) rather than the local driver's exit.
2. **Don't terminally-classify a signal-killed Batch run in the local thread.**
   Batch jobs run independently of the local driver; on a local signal-kill, defer
   to the orphan poller / a Batch-state check to finalize (the orphan_finalizer
   already infers success from outputs). This is the architecturally-correct fix
   and matches the run-state/orphan work (`docs/20260615_RUNS_PERSISTENCE_DESIGN.md`).
3. **Stop the spurious SIGTERM** if it's a too-short per-run timeout at teardown.

### Impact on the demo campaign
The drug-dev deck "Completed/Outputs/Record" screenshots are **blocked** on Bug B —
ADMET can't reach a clean Completed until signal-killed-but-complete runs finalize
as succeeded. prerun + running capture fine. The QC-gate scenario (Scenario 2) can
be captured from the paused/gate UI state once the state is stable.
