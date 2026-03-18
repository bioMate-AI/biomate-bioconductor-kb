# AutoFix De-dup Stage-C: Implicit Retry Guard (Detailed)

Timestamp: 2026-03-01 12:28

## Goal

Extend de-dup protection beyond explicit retry metadata so backend can still block likely duplicate manual reruns while AutoFix is actively remediating a recent failed run.

This stage addresses the residual gap from Stage-B:
- Stage-B blocked explicit retry paths only.
- Stage-C adds conservative inference when retry metadata is absent.

## Scope implemented

### 1) Workflow-name normalization helper

File:
- `frontend/server/routes.ts`

Added:
- `normalizeWorkflowName(raw)`:
  - lowercase
  - trim
  - collapse repeated whitespace

Purpose:
- Stable identity matching between incoming execution request and recent failed runs.

### 2) Implicit retry inference in `/api/workflows/execute`

File:
- `frontend/server/routes.ts`

Insertion point:
- Early in `POST /api/workflows/execute`, before run creation and backend dispatch.

Rule:
- If explicit retry context is **missing**, and caller is scoped (`req.user?.id` or `request.projectId`):
  1. Compute incoming workflow identity from `workflowDefinition.name || annotation`
  2. Fetch recent runs (`limit=30`) for same user/project
  3. Find candidate run where all are true:
     - `execution.executionEngine === "nextflow"`
     - `execution.status === "failed"`
     - normalized `workflowName` matches incoming normalized name
     - updated within a 2-hour safety window
  4. Resolve candidate AutoFix lifecycle (`getAutofixLifecycleForRun`)
  5. If lifecycle active (`analyzing|fixing|restarting`), block with `409`

Block payload:
- `error: "autofix_active_retry_blocked"`
- guidance text
- inferred retry context:
  - source run ID
  - source galaxy invocation ID
  - `inferred: true`
- normalized `autofix` lifecycle object

### 3) No-auth safety boundary

Guard condition:
- implicit inference only runs when there is tenant scope (`userId` or `projectId`).

Reason:
- avoid global cross-user matching behavior for completely unscoped calls.

## Retained Stage-B behavior

Explicit retry de-dup remains unchanged and still has highest priority:
- explicit context accepted from:
  - `retryContext`
  - `workflowDefinition.__retryContext`
  - `executionConfig.retryOfRunId`
  - `executionConfig.retryOfInvocationId`
- explicit path still returns `409` with same `autofix_active_retry_blocked` code if active.

## Validation run (this stage)

### Lint
- `ReadLints` on changed server route file: clean.

### Build
- `npm run build`: success.

### Targeted E2E regression
- `e2e/ux-autofix-gate.e2e.ts` PASS
- `e2e/ux-async-error-cta.e2e.ts` PASS
- `e2e/ux-offline-recovery.e2e.ts` PASS

### Release matrix
- `feedback-real-ui-strict.e2e.ts` PASS
- `pm-user-stories-comprehensive.e2e.ts` PASS
- Matrix result: `SUCCESS`
- Artifact:
  - `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_122301.txt`

## Design trade-offs

1. Matching key:
   - currently workflow-name based (normalized),
   - intentionally simple and stable for immediate protection.

2. Time window:
   - 2 hours to avoid stale blocking while still catching near-term duplicates.

3. Conservative scope:
   - implicit matching only when user/project scope exists.

## Known limitations

1. Name-match heuristic can miss semantically identical workflows with changed titles.
2. Name-match can over-block in edge cases where user intentionally runs a fresh but same-named workflow while previous AutoFix is active.
3. No dedicated API-level deterministic test yet for implicit inference branch (regression and feature-adjacent E2E remain green).

## Recommended next hardening (Stage-D)

1. Add workflow fingerprint matching (e.g., stable hash from workflow definition graph) to reduce false positives/negatives.
2. Add deterministic integration/API test for implicit branch.
3. Add backend telemetry counters:
   - `autofix.retry_block.explicit`
   - `autofix.retry_block.inferred`
   - `autofix.retry_block.overridden` (if future override path is introduced).

