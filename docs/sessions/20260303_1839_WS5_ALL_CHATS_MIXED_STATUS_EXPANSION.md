# WS5 Expansion: All-Chats Mixed-Status Run Manager Coverage

## What was added

- New E2E test:
  - `frontend/e2e/run-manager-all-chats-mixed-load.e2e.ts`
- New deterministic Run Manager bucket test IDs:
  - `run-manager-bucket-running`
  - `run-manager-bucket-queued`
  - `run-manager-bucket-failed`
  - `run-manager-bucket-completed`
  - `run-manager-bucket-count-running`
  - `run-manager-bucket-count-queued`
  - `run-manager-bucket-count-failed`
  - `run-manager-bucket-count-completed`

## Why this change

- Existing scope test confirmed control visibility only.
- It did not validate:
  - current-chat vs all-chats fetch contract behavior
  - mixed-status bucket rendering under denser run lists
  - search/filter/sort behavior under larger cardinality
- Added explicit bucket IDs to avoid brittle text-based assertions and improve test maintainability.

## New test coverage details

`run-manager-all-chats-mixed-load.e2e.ts` validates:

1. **Scope contract**
   - `current_chat` request includes `chatSessionId`
   - `all_chats` request omits `chatSessionId`
2. **Dense mixed-status rendering**
   - running/queued/failed/completed buckets all populate
   - bucket counts match mocked payload composition
3. **Filter behavior**
   - status filter `failed` hides non-failed run cards
4. **Search behavior**
   - query narrows to specific run/workflow match
5. **Sort behavior**
   - `running_first` lifts a running run item to first visible slot

## Validation run

- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-manager-all-chats-mixed-load.e2e.ts e2e/run-manager-multi-chat-scope.e2e.ts --project chromium`
- Result:
  - 2 passed

## Regression validation

- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/run-context-traceability.e2e.ts e2e/run-manager-switch-anchoring.e2e.ts e2e/run-context-mismatch-guard.e2e.ts --project chromium`
- Result:
  - 3 passed

## Notes

- Initial failure was assertion brittleness (generic text count matching), not behavior regression.
- Replaced brittle checks with stable bucket test IDs and reran successfully.
