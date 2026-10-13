# QC halt gate — pause for human intervention (Resume / Cancel)

**Date:** 2026-10-13 · **Commit:** `c0a604b64` · synced to dev.

## Problem
A live ADMET run showed a QC gate — `dili_risk high ≠ low` — with *"Pipeline continues in 0:10
unless you act"*, and the run **completed anyway**. Investigation (see the QC-gate machinery map)
found QC gates were **emit-only and post-hoc**: a detached monitor (`qc_trace_monitor.py`) fires a
`qc_gate_triggered` SSE event *after* a step completes; **nothing ever paused the pipeline**. The
frontend's 10s countdown auto-proceeded ("kept current parameters and continued"), and an explicit
auto-loop phase auto-reran. So a **safety signal (DILI/hERG/Ames high) could advance without the
user** — fail-open on a toxicity flag.

## Decision
Halt-severity gates must **pause and wait for the user → Resume or Cancel** (no auto-proceed).
Implemented the **simple, low-risk version**: frontend-only, reusing the existing pause/resume/cancel
endpoints — no backend executor (hot-path) change.

## What changed (`nextflow-workflow-viewer.tsx`)
- A `qc_gate_triggered` event only fires when a **blocking** (halt-threshold) failure exists
  (advisory-only crossings arrive via `qc_warning`), so a triggered gate *is* a halt gate.
- New branch in the `qc_gate_triggered` handler, **before** the auto-loop/countdown logic: when
  `pauseAtQcFailures` is on (default) and the phase is **not** an explicit auto-loop opt-in, a blocking
  gate now:
  1. `POST /api/workflows/runs/:id/pause` (stop advancing),
  2. shows a **"run paused · action required"** card with **Resume** (`POST /resume` — continues from
     cached steps) and **Cancel run** — **no 10s countdown**,
  3. emits a `workflow.qc_halt_paused` chat line.
- Blocking is `advisory !== true` (mirrors the backend `blocking_failures`). `pauseAtQcFailures` is
  read via a **ref** so the long-lived SSE listener sees the current value.
- **Unchanged:** advisory gates (`qc_warning`), explicitly auto-loop-enabled phases (they keep
  auto-remediating — a deliberate opt-in), and `pauseAtQcFailures=false` (restores the old
  auto-proceed). zh added (`qc_resume` 继续运行, `qc_gate_paused_suffix`).
- Verified: tsc clean; vitest 1860/0; viewer tests 31/31.

## Honest limitation + future work
The QC monitor is **post-step**: the gate fires after a step finishes, by which point the *next* step
may already be running (or, on a very short pipeline like 2-step ADMET, nearly done). The frontend
pause stops the orchestrator from advancing and waits for the user, but an in-flight step isn't
retroactively stopped. For a **guaranteed pre-step block** regardless of pipeline length, the proper
(larger) fix is a **blocking gate node in the Nextflow DAG** + a backend wait/resume-signal channel —
a deliberate executor change, deferred. `pauseAtQcFailures` is now honored client-side; threading it
(and a gate-level `action:'halt'`) through the backend is part of that future work.

See [[project_findings_outputs_architecture]] context and the QC-gate map in this session's notes.
