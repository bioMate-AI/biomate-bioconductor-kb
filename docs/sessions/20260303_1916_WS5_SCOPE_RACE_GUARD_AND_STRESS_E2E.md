# WS5 Continuation: Scope Race Guard + Stress E2E

## Completed in this cycle

- Added stale-response protection for Run Manager fetches during rapid scope changes.
- Added a dedicated race-condition E2E test for `current_chat` vs `all_chats` toggling.
- Re-ran Run Manager regression suite plus strict complete workflow E2E.

## Code changes

- `frontend/client/src/components/chat-with-artifacts.tsx`
  - Added request sequencing guard:
    - `runListRequestSeqRef`
    - each `fetchRunList()` call captures a `requestSeq`
    - only latest request is allowed to mutate:
      - `setRunList`
      - `setRunListError`
      - `setIsRunListLoading`
  - Prevents stale slower responses from overwriting UI after a newer scope selection.

- `frontend/e2e/run-manager-scope-race-guard.e2e.ts` (new)
  - Simulates delayed `current_chat` responses and fast `all_chats` responses.
  - Performs rapid toggles with final scope `all_chats`.
  - Asserts final rendered runs belong to `all_chats`.
  - Asserts `current_chat` run is absent in final state.
  - Asserts both request types were issued (coverage of race scenario).

## Test evidence

1. Run Manager stress + regression suite
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-manager-scope-race-guard.e2e.ts e2e/run-manager-all-chats-mixed-load.e2e.ts e2e/run-manager-multi-chat-scope.e2e.ts --project chromium`
- Result:
  - 3 passed

2. Full strict workflow regression
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=1`
- Result:
  - passed
  - workflow generated
  - execution started and reached UI-complete state
  - output evidence shown
  - visualization and download checks passed

## Notes

- Initial race test attempt failed due to using `page.waitForTimeout` inside route interception; replaced with a plain timer promise to avoid teardown-callback timing issues.
- No linter errors introduced.
