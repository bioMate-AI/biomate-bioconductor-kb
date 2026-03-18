# WS5 Continuation: Refresh + Sort Stability Stress Test

## Implemented

- Added new E2E:
  - `frontend/e2e/run-manager-refresh-sort-stability.e2e.ts`
- Scope of this test:
  - all-chats refresh evolution across multiple payload versions
  - per-bucket top-item stability (running/failed) under sort-mode changes
  - stress scope flip + manual refresh
  - final-state guard to ensure all-chats view does not render current-chat-only run

## Important adjustment made during debugging

- Initial assertions used rendered text snippets and global first-card ordering assumptions.
- This was fragile because:
  1) run IDs are intentionally shortened in UI text
  2) run cards are shown in separate status buckets (global first card is not sort-semantics proof)
- Updated test to assert deterministically via:
  - `data-testid` extraction from first card in explicit buckets
  - bucket-scoped expectations (`running`, `failed`)

## Validation results

### Run Manager suite
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-manager-refresh-sort-stability.e2e.ts e2e/run-manager-scope-race-guard.e2e.ts e2e/run-manager-all-chats-mixed-load.e2e.ts e2e/run-manager-multi-chat-scope.e2e.ts --project chromium`
- Result:
  - assertions pass
  - one run reported Playwright artifact I/O flake (`ENOENT` while writing trace/video package), then retry passed

### Isolated rerun of new test
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-manager-refresh-sort-stability.e2e.ts --project chromium --retries=1`
- Result:
  - passed

### Strict complete-workflow regression
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --trace off --retries=0`
- Result:
  - passed
  - workflow generated
  - execution completed
  - output evidence visible
  - visualization/download checks passed

## Observed runner issue (non-product)

- Repeated occasional Playwright artifact packaging failures:
  - `ENOENT` under `.playwright-artifacts-0/...trace` or zip path
- This causes flaky reporting despite successful product assertions.
- Mitigation used for clean confidence run:
  - `--trace off` on strict workflow test
