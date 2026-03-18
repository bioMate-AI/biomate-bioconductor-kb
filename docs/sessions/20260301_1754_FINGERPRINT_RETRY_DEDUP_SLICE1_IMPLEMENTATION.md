# 2026-03-01 17:54 — Slice 1 Implementation: Fingerprint-Based Retry De-dup

## Scope

Implemented the first roadmap slice in the existing AutoFix/manual-retry guard path:

- Added workflow fingerprint computation in `frontend/server/routes.ts`.
- Upgraded the Stage-C implicit retry guard in `POST /api/workflows/execute` to match by:
  1) workflow fingerprint (primary), then
  2) normalized workflow name (fallback).
- Preserved all current AutoFix lifecycle logic and blocking semantics (`409 autofix_active_retry_blocked`).

No frontend contract changes were required for this slice.

## Why this change

Current implicit retry matching can miss same-workflow retries when names drift and can over-match when generic names are reused.

Fingerprint matching improves identity precision by using the workflow structure (engine hint, format/type, Nextflow path, normalized steps, and parameters), while keeping name fallback for compatibility and graceful degradation.

## Code changes

### 1) Added deterministic fingerprint utilities

File: `frontend/server/routes.ts`

- Imported `createHash` from Node `crypto`.
- Added:
  - `normalizeForFingerprint(value)` — recursively sorts object keys for deterministic serialization.
  - `buildWorkflowFingerprint(workflowDef)` — computes SHA-256 hash from normalized workflow shape.

Fingerprint input shape includes:
- `executionEngineHint` (via existing `getWorkflowExecutionEngine`)
- `workflow_type`
- `format`
- `nextflow_path`
- `parameters`
- normalized `steps` list:
  - `stepId`, `type`, `tool_id`, `name`, `annotation`, `inputs`, `input_connections`, `tool_state`
  - `tool_state` is JSON-parsed when possible before normalization.

### 2) Upgraded Stage-C implicit retry guard

File: `frontend/server/routes.ts` in `POST /api/workflows/execute`

Previous behavior:
- matched only on normalized workflow name + recent failed Nextflow run + active AutoFix.

New behavior:
- computes `incomingWorkflowFingerprint`.
- scans recent runs and identifies candidate if:
  - failed Nextflow run,
  - within 2-hour window,
  - and (`fingerprintMatches` OR normalized-name-match).
- on block response, `retryContext.inferredBy` now reports:
  - `"fingerprint"` when blocked by structural match
  - `"name"` when fallback match was used.

All existing explicit retry guards (Stage-B by `retryOfRunId` / `retryOfInvocationId`) remain unchanged.

## Verification and test evidence

### Build + targeted + critical matrix

Executed in `frontend/`:

1. `npm run build`
2. `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/ux-autofix-gate.e2e.ts --project chromium --retries=0`
3. `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/ux-run-manager-panel.e2e.ts --project chromium --retries=0`
4. `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/ux-background-assist-panel.e2e.ts --project chromium --retries=0`
5. `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`

Result:
- Build: PASS
- `ux-autofix-gate`: PASS
- `ux-run-manager-panel`: PASS
- `ux-background-assist-panel`: PASS
- feedback release matrix: PASS
  - `feedback-real-ui-strict.e2e.ts`: PASS
  - `pm-user-stories-comprehensive.e2e.ts`: PASS

Artifact generated:
- `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_174646.txt`

### Lint check

`ReadLints` on edited file:
- `frontend/server/routes.ts`: no linter errors.

## Risk assessment

- **Low-to-medium risk**: only guard matching logic changed; block response contract unchanged except optional `retryContext.inferredBy`.
- **Performance**: fingerprint is computed at request time for at most recent run set (`limit=30`), acceptable for current scope.
- **Compatibility**: name fallback retained, so behavior does not regress when workflow definitions are sparse.

## Known limitations (next iterations)

- Fingerprint is not yet persisted on run records; it is computed on demand.
- Fingerprint currently includes `parameters`; if parameter defaults are normalized differently across producers, matching may become stricter than desired.
- No dedicated E2E yet asserting `inferredBy: "fingerprint"` path specifically (existing suites validate guard behavior end-to-end).

## Recommended next slice

Proceed with roadmap Slice 2:
- Canonical run status adapter to unify Galaxy/Nextflow/UI state mapping and reduce status interpretation drift across panels and telemetry.
