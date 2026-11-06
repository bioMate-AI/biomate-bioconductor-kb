# Phase 1D audit — Honest blocked states (no compute on failed/unresolved inputs)

**Date:** 2026-09-13
**Scope:** the Phase-1 P0 "honest blocked/error states; no compute on
unsupported/unbound requests" in
[`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md).
**Commit(s):** `fe3bb70ee`.

## Problem

`POST /api/workflows/execute` validated that `workflowDefinition` *exists*, and
already blocked missing required inputs (`inputs_required`) and required params
(`missing_required_params`) before any launch. Two holes remained:

1. **Failed generation could still run.** A `generatedWorkflow` carrying an
   explicit failure (`error`, or `success:false`) was not detected at execute —
   an API/connector caller could dispatch a non-runnable definition, burning a
   Batch job that fails at launch.
2. **Unresolved references were not blocked.** Chat surfaces
   `datasetReferenceUnresolvedIds` for files it could not bind to a real,
   authorized dataset, but execute never checked them — a run could proceed
   against a reference we know does not resolve.

## Fix

Two pure gates in `workflow-input-gate.ts`, wired into the execute path before
any launch (both return HTTP 400 with "No compute was launched"):

- `detectGenerationFailure(workflowDefinition)` — blocks on an explicit failure
  signal (`error`, `success:false`, or a missing/non-object definition).
  Conservative: a definition without these fields is treated as runnable, so no
  valid workflow is false-blocked. Wired immediately after the existence check →
  `400 workflow_generation_failed`.
- `findUnresolvedInputs(inputs, unresolvedIds)` — returns the input ids the
  caller declared unresolved (`request.datasetReferenceUnresolvedIds` /
  `executionConfig.datasetReferenceUnresolvedIds`); if any bound input is in that
  set, the run is blocked → `400 inputs_unresolved`. We never substitute another
  or newer dataset for an unresolved reference. Wired after the input gate.

## Tests

- `workflow-input-gate.test.ts` (+7): `detectGenerationFailure` (error /
  success:false / missing / runnable-pass); `findUnresolvedInputs` (overlap /
  no-overlap / empty / dedupe+malformed).
- Commands: `npx tsc --noEmit -p .` → clean; `npx vitest run --testTimeout=30000`
  → **1497 passed, 7 skipped, 0 failed**. (The `auth-service` bcrypt test needs a
  larger timeout under full-suite parallel load — pre-existing; passes standalone
  and with the raised timeout — unrelated to this change.)

## Authenticated dev exercise

- **Environment:** https://dev-public.biomate.ai; frontend rebuilt to include
  `fe3bb70ee` (`db5a3756` bundle, freshness-verified, image age 10s at swap).
- **Identity:** shared E2E fixture `lifeifei163361@163.com`. `POST
  /api/workflows/execute`, no Batch launched (all gates return first):

| Case | Request | Result |
|---|---|---|
| Generation error | `workflowDefinition:{error:"no matching tool"}` | **400 `workflow_generation_failed`** |
| success:false | `workflowDefinition:{success:false,message:"low confidence"}` | **400 `workflow_generation_failed`** |
| Unresolved input | input `missing-ref-1` + `datasetReferenceUnresolvedIds:["missing-ref-1"]` | **400 `inputs_unresolved`** |

## Remaining risks / follow-ups

- The unresolved-input gate is opt-in: it fires when the caller forwards
  `datasetReferenceUnresolvedIds`. The chat client should thread that field into
  the execute request (small UI/client task) so the gate engages for the chat
  path; server-side it is enforced whenever the field is present.
- A `lowConfidenceOverride` provenance flag on the run (record that a run
  bypassed the confidence gate) was scoped out as low-value; noted for later.
- Consumer wiring for the Phase-1C compatibility endpoint (chat/UI calling it
  before a two-file comparison) remains a small follow-up.

## Conclusion

**GO** for "honest blocked states": the execute path no longer launches compute
on a failed-generation workflow or an unresolved input, verified by unit tests
and a live dev exercise. This closes the last Phase-1 P0 item — with 1A
(authenticated output truth), 1B (input-binding provenance), and 1C (comparison
compatibility), **Phase 1 (execution & object coherence) is complete** pending
the noted client-wiring follow-ups.
