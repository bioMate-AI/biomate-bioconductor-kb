# Phase 1B audit — Real inputs bound before compute (provenance)

**Date:** 2026-09-13
**Scope:** the P0 "Real inputs bound before compute" gap in Phase 1 of
[`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md)
— specifically the *record which exact dataset/version was bound* half.
**Commit(s):** `cf2c1e46b`.

## Problem

The plan requires a run to "state the resolved project dataset/version, reject
incompatible or missing inputs, and never report success for an unbound/default
workflow." The **rejection** half was already enforced server-side:

- `inputs_required` (routes.ts) blocks a run when required data-input steps are
  unbound — before any launch.
- `missing_required_params` blocks a run with empty required params — before any
  launch; the code explicitly forbids `allowLowConfidence` from turning missing
  inputs into a launch.

The **provenance** half was missing: `request.inputs` (the exact
`{stepId, datasetId, src}` bound to each data-input step) was used to launch but
never persisted on the run. A result could not be traced back to the exact
dataset that produced it — blocking the reproducibility record (Phase 2) and the
phase-gate requirement that the audit "records run id, input identity/version,
output evidence."

## Fix

- **Schema:** new `inputBindings: InputBinding[]` on the `ExecutionRun` model and
  an `execution_runs.input_bindings` TEXT column (migration
  `0021_execution_run_input_bindings.sql`, idempotent `ADD COLUMN IF NOT
  EXISTS`). An `InputBinding` records `{ stepId, datasetId, src?, name?, s3Uri?,
  projectFileId? }` — `s3Uri`/`projectFileId` captured when the input carries
  them so a result traces to an exact project object.
- **Extraction:** `extractInputBindings()` in `workflow-input-gate.ts` records
  the well-formed bindings (same id/stepId shape the gate enforces), accepting
  `stepId`/`step_id` and `s3Uri`/`s3_uri`/`projectFileId`/`project_file_id`, and
  dropping malformed entries (the gate rejects the run separately).
- **Persistence:** `createExecutionRun` populates `inputBindings` from
  `request.inputs`, writes it to the in-memory record and the PG row; the DB row
  mapping parses it back so the record survives a restart.

## Tests

- `workflow-input-gate.test.ts` (+4): extraction records stepId/datasetId/src/
  name; captures s3Uri/projectFileId (snake or camel); drops malformed entries;
  returns `[]` for non-array input.
- `storage.execution-run.test.ts` (new, 3): `createExecutionRun` records the
  binding for each data-input step; empty array when no data inputs; carries
  s3Uri/projectFileId through to the record and it is retrievable via
  `getExecutionRun`.
- Commands: `npx tsc --noEmit -p .` → clean; `npx vitest run` → **1478 passed,
  7 skipped, 0 failed**.

## Authenticated dev exercise

- **Environment:** https://dev-public.biomate.ai; frontend container rebuilt to
  the `cf2c1e46` bundle (created 2026-09-14T00:05:40Z, freshness-verified by the
  sync's post-swap check).
- **Migration applied:** `execution_runs.input_bindings` (type `text`) is present
  on `biomate-dev-postgres` (verified via `information_schema.columns`).
- **Code deployed:** `grep -c extractInputBindings /app/dist/index.js` = 2,
  `grep -c input_bindings` = 1.
- **Behavioral verification** is the deterministic unit + storage tests above,
  not a live launch: exercising the record end-to-end requires an actual
  workflow execution, which starts a billable AWS Batch job. Per the repo's
  "no speculative expensive runs" discipline, that is deferred to the next real
  run / the Phase-1 acceptance case rather than triggered solely to inspect a
  record. The write path (`createExecutionRun`) runs before launch and is fully
  covered in-memory by `storage.execution-run.test.ts`; the column now exists on
  dev so the persisted value survives.

## Remaining risks / follow-ups

- The run-meta API (`/api/runs/:anyId/meta`) returns a curated shape via
  `runsOutputsService`; surfacing `inputBindings` there is Phase-2
  reproducibility-record work, not required for this P0 (the record now stores
  it and `getExecutionRun` returns it).
- Still open in Phase 1: **compatibility validation for comparisons**; **honest
  blocked states** (block `workflowGenerationFailed`; thread unresolved
  references into execute).
- Unrelated: the sync's trailing `audit_batch_ce_lt_versions.sh --apply` step
  exited non-zero *after* the deploy succeeded (marker written, `result=healthy`,
  SNS ok). It does not affect the frontend deploy; worth a separate look at Batch
  CE launch-template pinning.

## Conclusion

**GO** for the provenance half of "real inputs bound before compute": the run
record now states which exact dataset was bound to each input step, persisted
and retrievable, with the rejection gates already enforcing no-compute-on-unbound.
Verified by unit/storage tests, an applied dev migration, and a deployed bundle.
Phase 1 is not yet complete — compatibility validation and honest-blocked-state
items remain.
