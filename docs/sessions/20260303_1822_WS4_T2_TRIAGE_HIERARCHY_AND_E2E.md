# WS4-T2 Completion: Execution Triage Hierarchy + Regression Audit

## Scope completed

- Implemented a fixed triage hierarchy in the workflow execution surface:
  - `Status`
  - `Next action`
  - `Logs`
  - `Outputs`
- Added deterministic `data-testid` hooks for each triage item.
- Added a new E2E test to enforce hierarchy presence and order.
- Updated an existing mismatch-guard E2E test to validate focused-context behavior without relying on brittle global text absence.

## Files changed

- `frontend/client/src/components/nextflow-workflow-viewer.tsx`
  - Added `execution-triage-summary` panel.
  - Added:
    - `execution-triage-status`
    - `execution-triage-next-action`
    - `execution-triage-logs`
    - `execution-triage-outputs`
  - Added status-aware triage message derivation:
    - failed: review reason/logs, retry with corrections
    - completed: verify outputs/downloadables
    - running: monitor logs and wait for terminal state
    - idle: prepare params/prerequisites and run

- `frontend/e2e/run-triage-hierarchy.e2e.ts` (new)
  - Verifies triage block is rendered.
  - Verifies exactly four triage fields exist.
  - Verifies enforced order of test IDs:
    1) status
    2) next-action
    3) logs
    4) outputs

- `frontend/e2e/run-context-mismatch-guard.e2e.ts`
  - Replaced global negative assertions with scoped focused-artifact assertions:
    - validates focused anchor content contains selected run/invocation
    - validates focused anchor content excludes non-selected run/invocation

## Test evidence

1) New hierarchy test
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-triage-hierarchy.e2e.ts --project chromium`
- Result:
  - Passed

2) Focus mismatch guard + hierarchy regression pair
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-context-mismatch-guard.e2e.ts e2e/run-triage-hierarchy.e2e.ts --project chromium`
- Result:
  - Passed (2/2)

3) End-to-end real workflow guardrail
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=1`
- Result:
  - Passed
  - Verified:
    - workflow generation
    - workflow execution to terminal completion
    - output evidence visible
    - visualization indicator present
    - download control enabled

## Notes

- The initial hierarchy test failure was due to stale built assets; running `npm run build` refreshed the served frontend bundle and resolved this.
- No linter errors were introduced in edited files.
