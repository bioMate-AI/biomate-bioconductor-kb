# AutoFix vs Manual Retry De-dup Integration (Stage-A)

Timestamp: 2026-03-01 12:07

## Why this work

We confirmed Nextflow has backend AutoFix capability, while recent UX work added manual retry CTAs.
Without integration, users could trigger manual reruns while AutoFix is already active, causing duplicate recovery paths.

## What was reviewed

1. Existing AutoFix endpoints and runners:
   - `frontend/server/routes.ts`
     - `/api/workflows/runs/:id/ai/autofix`
     - `/api/invocations/:id/ai/autofix`
     - `/api/galaxy/workflows/:workflowId/invocations/:invocationId/autofix3/run`
     - `/api/galaxy/workflows/:workflowId/invocations/:invocationId/autofix3/sessions`
   - `backend/lib/galaxy/jobs/runners/nextflow_monitor.py`
     - automatic fix detection/application/restart pipeline.

2. Main chat execution UI path:
   - `chat-message` -> `nextflow-workflow-viewer`
   - legacy `workflow-artifact` has autofix controls but is not the primary chat path.

## Implemented contract (status API)

Updated `GET /api/workflows/runs/:id/status` in `frontend/server/routes.ts`:

1. Added normalized `autofix` lifecycle object to response:
   - `state`: `idle | analyzing | fixing | restarting | succeeded | failed`
   - `source`: `auto | manual | unknown`
   - `active`: boolean (`true` for analyzing/fixing/restarting)
   - optional metadata: `lastActionAt`, `message`, `sessionId`, `totalAttempts`, `terminationReason`

2. Derived from latest AutoFix3 session (`limit=1`) using robust mapping:
   - supports variant field names (`status/state/phase`, `source/trigger_source/mode`, etc.)

3. Embedded the same lifecycle under `nextflowStatus.autofix` for frontend compatibility.

## Frontend integration

### Shared schema

Updated `frontend/shared/schema.ts`:
- `executionRunStatusResponseSchema` now includes optional `autofix` object with normalized fields.

### Unified execution hook

Updated `frontend/client/src/hooks/useUnifiedExecution.ts`:
- status polling type includes optional `autofix`.
- merges `autofix` into `currentRun.execution.nextflowStatus.autofix`.

### Execution gating in main workflow panel

Updated `frontend/client/src/components/nextflow-workflow-viewer.tsx`:
- new optional prop `autofix`.
- computes `isAutofixActive` from `autofix.active` or lifecycle state.
- disables:
  - `button-run-workflow-panel`
  - `button-confirm-low-confidence-run`
  while AutoFix is active.
- added clear banner:
  - `data-testid="autofix-active-banner"`
  - copy: manual retry is temporarily disabled to avoid duplicate reruns.

Updated `frontend/client/src/components/chat-message.tsx`:
- passes `currentExecutionRun.execution.nextflowStatus.autofix` into `NextflowWorkflowViewer`.

### Retry CTA gating

Updated `frontend/client/src/components/chat-with-artifacts.tsx`:
- execution error panel `button-execution-try-again` is disabled while autofix is active.
- label changes to `Auto-fix in progress` in active state.

## New E2E coverage

Added `frontend/e2e/ux-autofix-gate.e2e.ts`:
- simulates run status transitioning to `failed` with `autofix.state=fixing` and `active=true`.
- verifies:
  - autofix active banner visible,
  - manual run button disabled.

## Validation results

1. Lint:
- no linter errors in changed files.

2. Targeted suites:
- `ux-autofix-gate.e2e.ts` PASS
- `ux-async-error-cta.e2e.ts` PASS
- `ux-offline-recovery.e2e.ts` PASS

3. Release gate regression:
- `feedback-real-ui-strict.e2e.ts` PASS
- `pm-user-stories-comprehensive.e2e.ts` PASS
- matrix result: `SUCCESS`
- artifact: `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_120302.txt`

## Stage-A limitations

1. AutoFix lifecycle is inferred from latest session payload shape; if backend schema changes, mapping should be adjusted.
2. We gate manual retry on active lifecycle states only; no queue position/ETA yet.
3. Execution-level retry de-dup is now enforced in UI, not yet hard-enforced server-side.

## Recommended Stage-B

1. Add server-side protection: reject manual rerun attempts while autofix is active for same invocation.
2. Add richer lifecycle fields from backend (`phase`, `progress`, `estimatedRemaining`).
3. Add telemetry events:
   - `autofix.active_banner_shown`
   - `autofix.manual_retry_blocked`
   - `autofix.lifecycle_state_changed`

