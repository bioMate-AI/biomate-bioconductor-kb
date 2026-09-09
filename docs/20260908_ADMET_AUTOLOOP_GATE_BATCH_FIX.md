# ADMET auto-loop QC gate did not fire on dev — diagnosis + fix (2026-09-08)

Branch: `integration/dev-test`
Commits: `b2ba73914`, `9fc540ce1`

## Symptom
The dev E2E (`frontend/e2e/autoloop-full-arc.e2e.ts`) reported the auto-loop
QC gate "did not materialize within the 12-min window" for a terfenadine
ADMET run. The AutoLoopPanel stayed empty.

## Diagnosis — the auto-loop IS wired; the gate metrics never reached the panel

The auto-loop is fully wired end-to-end and NOT experiment-only:

```
Nextflow ADMET process completes
  → qc_trace_monitor.NextflowQCGateHandler.handle_process_completion   (live trace-poll)
  → experiments.autoloop_bridge.evaluate_and_emit
  → ADMETQCEvaluator._herg_gates: herg_ic50_uM < 10 µM → HALT
  → SSE autoloop_gate_results (+ autoloop_update remediation)
  → frontend AutoLoopPanel (workflow-artifact.tsx / nextflow-workflow-viewer.tsx
    addEventListener("autoloop_gate_results" | "autoloop_update"))
```

`backend/experiments/admet_autoloop/{orchestrator,qc_evaluator,param_tuner,
enriched_tuner}.py` are the evaluator/tuner components; the product loads them
via `autoloop_bridge._load_components("admet")`. So the gap analysis suspicion
("auto-loop not wired into the product run path") is **wrong** — it is wired.

The firing condition is exact: **hERG IC50 < 10 µM → HALT** (profile
`admet_standard`, `herg_ic50_threshold_uM = 10.0`). Terfenadine's predicted
hERG IC50 is well below that, so the gate must fire.

### Why it didn't fire on dev (Batch is the default: NEXTFLOW_USE_AWS=true)

Two independent breaks in the Batch/S3 path, confirmed against a REAL completed
dev run (`66716e15`, terfenadine): S3 had `qc_metrics.json` with
`herg_ic50_uM: 0.0103` (and `herg_safe_above_10uM: false`) and
`toxicity_report.json` with the same nested value — yet the run record showed
`qc_gates: null` and the panel was empty.

1. **Decisive: the S3-completion path never emitted the auto-loop SSE.**
   The AutoLoopPanel renders ONLY from `autoloop_gate_results` /
   `autoloop_update` SSE events, not from the run's `qc_gates` field. On Batch,
   the completion-time gate (`_evaluate_qc_from_s3` in `nextflow_executor.py`)
   computed gate failures into `qc_gates` but never called
   `autoloop_bridge.evaluate_and_emit`, so no SSE ever reached the panel.

2. **The S3 report readers could not surface the metric reliably:**
   - `_evaluate_qc_from_s3` matched output files on `f["filename"]`, but
     `_list_s3_output_files` stores the basename under `f["name"]` → the
     filename check was always `""` (it relied entirely on the s3_uri suffix).
   - `_read_s3_workdir_report` hard-coded `qc_metrics.json`; the legacy
     `ADMET_pred` workflow emits `toxicity_report.json` (nested
     `toxicity.herg_ic50_uM`), and `_report_json_to_metrics` only passed
     through TOP-LEVEL scalars → the nested hERG was dropped, and the
     evaluator fell back to its 999.0 default → PASS → no gate.

(The AI Chemprop `predict_admet_properties` workflow — the dev default —
flattens `herg_ic50_uM` into `qc_metrics.json`, so its metric was readable;
its failure was break #1: no SSE emitted.)

## Fix (root cause, honest — real QC evaluation)

`backend/lib/galaxy/jobs/qc_trace_monitor.py`
- `_S3_REPORT_PATHS`: register `ADMET_PRED → toxicity_report.json`.
- `_read_s3_workdir_report`: match `toxicity_report.json` as well as
  `qc_metrics.json`.
- `_report_json_to_metrics`: extract nested `toxicity.{herg_ic50_uM, dili_risk,
  dili_probability, ames_*, clintox_probability}` for
  PREDICT_ADMET/ADMET_PRED/ADMET_SAFETY/ADMET_TOXICITY (mirrors the local
  `_parse_admet_toxicity_metrics` extraction).

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- `_evaluate_qc_from_s3` ADMET branch now calls
  `autoloop_bridge.evaluate_and_emit(...)` at completion — the missing SSE emit
  (idempotent with the live-poll path; the panel replaces `gateResults` on each
  event).
- File matching accepts `filename` OR `name` OR s3_uri suffix; falls back from
  `toxicity_report.json` to `qc_metrics.json`.

## Evidence

Verified against the REAL dev S3 objects from run `66716e15`:
extract `herg_ic50_uM = 0.0103` → `herg_ic50` HALT + `dili_probability` HALT +
`dili_risk_level` HALT + remediation (`logp_max → 3.4`, `mw_max_da → 400`).
`autoloop_gate_results` (overall FAIL) and `autoloop_update` SSE both fire.

Tests: 109/109 `experiments/admet_autoloop/tests` pass (`test_admet_ux_loop`
skipped — pre-existing missing `rich` dep, unrelated). Both modified files
`ast.parse` clean (Python 3.9).

## Deploy note
Fix committed on `integration/dev-test`. A live fixed-path run on dev requires
the deploy to land first (per repo discipline: sync only from next-phase after
PR/merge; never sync from a worktree). Predicted live outcome: terfenadine ADMET
Batch run → AutoLoopPanel shows `autoloop-gate-table` with `herg_ic50`
verdict=halt (0.0103 µM < 10) + remediation card `logp_max → 3.4`, satisfying the
`autoloop-full-arc.e2e.ts` gate assertion.
