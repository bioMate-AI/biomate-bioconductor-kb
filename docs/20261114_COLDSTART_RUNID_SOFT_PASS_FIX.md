# Coldstart deep — missing runId / FAKE_OR_SOFT_PASS (Batch A)

**Date:** 2026-11-14  
**Evidence:** `docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md` §7; JSON under `frontend/e2e/execshots/coldstart-analysis-design-deep/`

## Root cause

1. **Harness:** `GET /api/workflows/runs` returns a **bare array**, but `extractRunId` only read `body.runs` / `body.items` → always `[]`. Session-less cases (and any case where message metadata lagged) could not recover a runId from the API.
2. **Product:** Live `NextflowWorkflowViewer` never set `data-run-id` (only unit-test mocks did). E2E selectors looking for `[data-run-id]` always missed.
3. **Secondary:** `paused` (QC / sequential pipeline) was not treated as terminal → soft-timeout with `error=no runId`. Confirm clicks that never started a run (missing `nextflow_path` / silent prereq bail) were graded `FAKE_OR_SOFT_PASS` after long idle polls.

## Fixes

| Layer | Change |
|-------|--------|
| Product | `data-run-id` on panel root + status badge; resolve `filename` / `nextflowPath` → `nextflow_path` before execute; toast / error instead of silent Confirm no-op |
| Harness | `e2e/lib/coldstart-run-id.ts` helpers; parse bare runs array; session `workflows[].workflow_id` backfill; capture execute POST; treat `paused` as terminal; idle-after-Confirm → `confirm_noop` / `NO_LAUNCH` |

## Verify

```bash
cd frontend && npx vitest run e2e/lib/coldstart-run-id.test.ts e2e/lib/coldstart-deep-grade.test.ts
cd frontend && npx tsc --noEmit -p .
# After sync_to_dev.sh (pre-sync checklist):
BIOMATE_DEEP_FILTER='analysis-try-sample-data-9|design-generate-pep-0|design-predict-filter-sm-0|design-generate-bio-0' \
  ./e2e/run_coldstart_deep.sh
```

Expect: when a run actually starts, JSON has `runId`; QC-paused pipelines report `terminal.status=paused` (not `no runId` timeout); Confirm that never starts grades `NO_LAUNCH` / `confirm_noop` instead of soft-pass.

## Not fixed in Batch A

- Soft-pass on completed antibody runs with empty `workflowNames` / missing Findings tab (use-case grade, not runId plumbing).
- Why some cyclic_peptide / WSI Confirm still fail server-side after path resolution (needs live DEV retest after sync).
- REINVENT / Cryo / param-validation classes (other inventory sections).
