# CryoEM Auto-Loop: Data Visualization & Inspection UI

**Date:** 2026-04-16  
**Scope:** `backend/experiments/cryo_em_autoloop_ux/` only (standalone demo, NOT BioMate production)

## What was built

Extended the standalone server (`server.py`) with three new UI panels covering the full data lifecycle of a CryoEM auto-loop run.

### 1. Phase Data Inspector (`#data-inspector`)

Real-time panel driven by SSE events. Shows per-phase, per-attempt data:

- **Input Parameters table** (`data-section="input-params"`): Phase-relevant `CryoEMParams` fields from `autoloop_phase_start.params_summary`. Changed values from the previous attempt are highlighted in amber.
- **QC Gate Results table** (`data-section="gate-results"`): Full gate metrics from `autoloop_gate_results.gates`. Rows are color-coded green/amber/red for pass/advisory/halt. Shows measured value vs threshold for all gates in the phase.
- **Parameter Changes table** (`data-section="param-changes"`): Adjustments from `autoloop_update.remediations.param_changes`. Includes the rationale text below each table.

Phase tab bar (A–E) at the top auto-selects the active phase as the run progresses.

### 2. Findings Report (`#findings-card`)

Appears automatically after `run_complete`. Fetches from two new API endpoints:

- `GET /api/audit/:run_id` → JSON array of all audit records (attempt + phase_final events)
- `GET /api/summary/:run_id` → plain-text summary report

Shows:
- Stats chips: phases passed, escalated, total attempts, audit record count
- Full summary text in a `<pre>` block (`#summary-pre`)
- Download buttons for summary.txt and audit JSONL

### 3. API endpoints added

| Endpoint | Returns |
|---|---|
| `GET /api/audit/:run_id` | `application/json` — list of audit JSONL records |
| `GET /api/summary/:run_id` | `text/plain` — human-readable summary report |

Audit data is read from the tmpdir before cleanup and stored in `_runs[run_id]`.

## Bug fixed: SSE race condition

**Root cause:** In `_stream_events`, if the run completed between taking the stored-events snapshot and checking `run['done']`, the `run_complete` event was never sent to the client (it was in the queue but the handler returned early).

**Fix:** Instead of returning early on `run['done']`, check whether `run_complete` was already sent in the replay. Only return early if it was. Otherwise always enter the queue loop, which drains any remaining events including the missed `run_complete`. This also fixed intermittent 60-90s timeout failures across the full test suite.

Side effect: suite runtime dropped from ~187s to ~7s (queue loop no longer blocks 1s per empty poll).

## Tests

Added 8 new Playwright E2E tests (AL-17 through AL-24):

| ID | What it tests |
|---|---|
| AL-17 | `#data-inspector` hidden before run, visible after first phase event |
| AL-18 | Input params table shows phase_A params (`micrograph_batch_size`, etc.) |
| AL-19 | Gate results table shows measured/threshold values with pass/halt symbols |
| AL-20 | Param-changes table appears for phase_A after retry (motion_drift HALT) |
| AL-21 | `#findings-card` hidden before run, visible after `run_complete` |
| AL-22 | Findings `#summary-pre` contains `CryoEM Auto-Loop Run` header + gate data |
| AL-23 | `GET /api/audit/:run_id` returns JSON array with `attempt` records containing `phase`, `params`, `gate_results` |
| AL-24 | `GET /api/summary/:run_id` returns `text/plain` with run header and phase content |

**Final count: 24/24 E2E + 71/71 unit = 95/95 total tests passing.**

## How to run

```bash
cd backend/experiments
python -m cryo_em_autoloop_ux.server
# http://localhost:7788

pytest cryo_em_autoloop_ux/tests/test_e2e_ui.py -v
```
