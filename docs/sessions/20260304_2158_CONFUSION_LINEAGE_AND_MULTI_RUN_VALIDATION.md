# Confusion Lineage + Multi-Run Validation (2026-03-04 21:58)

## What Was Added

- Lineage-aware confusion telemetry payloads in `frontend/client/src/components/chat-with-artifacts.tsx`:
  - For `workflow.confusion_signal` with `signal: "output_dead_end"`:
    - `runId`, `rootRunId`, `parentRunId`, `runSequence`
  - For `workflow.confusion_signal` with `signal: "retry_without_progress"`:
    - `runId`, `rootRunId`, `parentRunId`, `runSequence`
    - `retryChainKey`, `baselineProgressPercent`
- Multi-run lineage E2E coverage:
  - Added `frontend/e2e/run-confusion-lineage-multi-run.e2e.ts`
  - Validates that confusion telemetry emitted after run-manager switching carries the expected lineage (`rootRunId`, `parentRunId`) for a run in an iteration chain.

## Validation Commands and Results

Server used for this validation batch:
- `PORT=5406 NODE_ENV=test SESSION_SECRET=dev-session-secret node dist/index.js`

Tests:
- `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/run-confusion-lineage-multi-run.e2e.ts --project chromium --reporter=list --workers=1`
  - Result: 1 passed
- `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/run-confusion-signals.e2e.ts --project chromium --reporter=list --workers=1`
  - Result: 2 passed
- `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/run-confusion-signals.e2e.ts e2e/run-confusion-lineage-multi-run.e2e.ts e2e/run-manager-limit-offset-stress.e2e.ts --project chromium --reporter=list --workers=1`
  - Result: 4 passed

## Notes

- During one mixed test invocation, a Playwright artifact write race (`ENOENT` under `.playwright-artifacts`) produced a flaky failure despite successful retry. Running suites serially/standalone avoids this infra-level artifact issue.
- Functional behavior for telemetry signals remained consistent and validated in clean serial runs.
