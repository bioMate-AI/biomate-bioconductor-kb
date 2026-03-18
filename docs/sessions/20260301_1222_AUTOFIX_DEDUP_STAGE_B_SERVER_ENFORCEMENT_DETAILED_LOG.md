# AutoFix De-dup Stage-B (Server Enforcement) — Detailed Work Log

Timestamp: 2026-03-01 12:22

## Objective

Implement backend-enforced de-duplication so manual execution retries cannot race against active AutoFix remediation for the same run/invocation, then document evidence with timestamps and validation artifacts.

## Timeline (UTC-local session time)

- **12:08–12:10** — Reviewed `POST /api/workflows/execute` flow and identified the safest insertion point for retry de-dup checks (before execution-run creation and backend dispatch).
- **12:10–12:13** — Added reusable AutoFix lifecycle resolver in `frontend/server/routes.ts`:
  - normalizes state to: `idle | analyzing | fixing | restarting | succeeded | failed`
  - supports cached status (`run.execution.nextflowStatus.autofix`) first
  - falls back to AutoFix3 sessions API (`limit=1`) if cached data absent
- **12:13–12:15** — Added server-side block in `/api/workflows/execute` for explicit retry requests:
  - reads retry context from:
    - `request.retryContext`
    - `request.workflowDefinition.__retryContext`
    - `request.executionConfig.retryOfRunId`
    - `request.executionConfig.retryOfInvocationId`
  - resolves source run by run ID or Galaxy invocation ID
  - returns `409` with `autofix_active_retry_blocked` if lifecycle is active
- **12:15–12:16** — Sanitized internal metadata before workflow persistence/execution:
  - strips `__retryContext` (and existing `__generationAssessment`) from workflow definition payloads.
- **12:16–12:17** — Extended shared contract:
  - `frontend/shared/schema.ts` `executionConfigSchema` now includes:
    - `retryOfRunId?: string`
    - `retryOfInvocationId?: string`
- **12:17–12:18** — Wired frontend retry context propagation:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
    - execution retry path now injects `__retryContext` into workflow run request
    - `executeWorkflow` call now sends:
      - `executionConfig.retryOfRunId`
      - `executionConfig.retryOfInvocationId`
      - `retryContext`
  - `frontend/client/src/hooks/useUnifiedExecution.ts`
    - updated request type to include optional `retryContext`
- **12:18–12:20** — Lint + build + regression test validation.

## Files changed

1. `frontend/server/routes.ts`
   - Added:
     - `getAutofixLifecycleForRun(run)` helper.
   - Updated:
     - `POST /api/workflows/execute` to enforce de-dup when retry context is present.
     - Workflow sanitation to drop `__retryContext`.

2. `frontend/shared/schema.ts`
   - Updated `executionConfigSchema` with:
     - `retryOfRunId`
     - `retryOfInvocationId`

3. `frontend/client/src/hooks/useUnifiedExecution.ts`
   - `ExecuteWorkflowParams` now supports:
     - `retryContext?: { runId?: string; galaxyInvocationId?: string }`

4. `frontend/client/src/components/chat-with-artifacts.tsx`
   - Retry path now passes explicit retry context to backend for enforcement.

## Server-side enforcement contract

### Retry request context (accepted sources)

- `retryContext.runId`
- `retryContext.galaxyInvocationId`
- `executionConfig.retryOfRunId`
- `executionConfig.retryOfInvocationId`
- `workflowDefinition.__retryContext` (internal fallback)

### Block condition

When a referenced source run resolves and AutoFix lifecycle is active:
- `state in { analyzing, fixing, restarting }` OR `active === true`

### Block response

HTTP `409`

```json
{
  "error": "autofix_active_retry_blocked",
  "message": "Manual retry blocked while AutoFix is active for the referenced run.",
  "guidance": "Wait for AutoFix to complete before triggering a manual rerun.",
  "retryContext": {
    "runId": "...",
    "galaxyInvocationId": "..."
  },
  "autofix": {
    "state": "fixing",
    "source": "auto",
    "active": true
  }
}
```

## Validation log

### Lint

- `ReadLints` on modified files: **no lint errors**.

### Build

- `npm run build`: **success**.

### E2E targeted

- `e2e/ux-autofix-gate.e2e.ts` — **PASS**
- `e2e/ux-async-error-cta.e2e.ts` — **PASS**
- `e2e/ux-offline-recovery.e2e.ts` — **PASS**

### Release gate matrix

Command:
- `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`

Result:
- `feedback-real-ui-strict.e2e.ts` — **PASS**
- `pm-user-stories-comprehensive.e2e.ts` — **PASS** (one flaky attempt auto-retried and passed)
- Matrix summary: **SUCCESS**

Artifact:
- `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_121210.txt`

## Notes on residual risk

1. The server guard applies to **explicit** retry flows that pass retry context (now wired from execution error CTA path).
2. If a non-standard client bypasses retry context, UI gating still protects normal users, but hard guarantee depends on clients honoring the retry contract.
3. Stage-C recommendation: reject duplicate rerun attempts based on invocation identity + active AutoFix even when retry context is absent.

## Next recommended step

Implement Stage-C hard guarantee:
- on `/api/workflows/execute`, infer duplicate retry intent by invocation lineage and chat/run linkage, not only explicit retry metadata, then reject when active AutoFix is detected.

