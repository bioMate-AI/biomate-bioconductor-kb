# WS4/WS5 Progress Update (2026-03-04 21:45)

## Scope Completed

- WS4-T1 completion for confusion telemetry:
  - Added `workflow.confusion_signal` emission for `output_dead_end` when a run reaches `completed` but `artifactReadiness.meetsContract === false`.
  - Added `workflow.confusion_signal` emission for `retry_without_progress` when users repeatedly hit retry without measurable progress gain within a bounded window.
- WS5 expansion:
  - Run Manager request now always includes `limit=50` and `offset=0`.
  - Added stress test coverage for rapid scope switching with explicit limit/offset request assertions.

## Files Changed

- `frontend/client/src/components/chat-with-artifacts.tsx`
  - Added refs for dead-end and retry-no-progress signal state.
  - Added output dead-end detection effect.
  - Added retry-without-progress detection in retry handler.
  - Added `offset=0` to run-manager fetch query.
- `frontend/e2e/run-confusion-signals.e2e.ts` (new)
  - Verifies `output_dead_end` and `retry_without_progress` confusion signals.
- `frontend/e2e/run-manager-limit-offset-stress.e2e.ts` (new)
  - Verifies final-scope stability under rapid toggles and request query consistency.

## Validation Runs

Executed on local server (`BIOMATE_URL=http://localhost:5405`) in `NODE_ENV=test`.

- `npx playwright test e2e/run-confusion-signals.e2e.ts --project chromium --reporter=list --workers=1`
  - Result: 2 passed
- `npx playwright test e2e/run-manager-limit-offset-stress.e2e.ts --project chromium --reporter=list`
  - Result: 1 passed
- `npx playwright test e2e/run-manager-scope-race-guard.e2e.ts e2e/run-manager-refresh-sort-stability.e2e.ts e2e/run-manager-large-set-visibility-cap.e2e.ts --project chromium --reporter=list --workers=1`
  - Result: 3 passed
- Consolidated batch:
  - `npx playwright test e2e/survey-directions-real.e2e.ts e2e/run-confusion-signals.e2e.ts e2e/run-manager-scope-race-guard.e2e.ts e2e/run-manager-refresh-sort-stability.e2e.ts e2e/run-manager-large-set-visibility-cap.e2e.ts e2e/run-manager-limit-offset-stress.e2e.ts --project chromium --reporter=list --workers=1`
  - Result: 10 passed

## Notes

- Prior local instability root causes were environment-level (port/CORS/watchers), not workflow test logic.
- This update keeps user-facing behavior unchanged while improving backend-visible UX confusion telemetry and run-manager query stability for stress scenarios.
