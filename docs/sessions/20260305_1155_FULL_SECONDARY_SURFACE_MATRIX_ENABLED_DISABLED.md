# 2026-03-05 11:55 Full Secondary-Surface Matrix (Enabled + Disabled Profiles)

## Scope

- Continue execution-focused system validation.
- Keep dataset-search work on hold.
- Produce one consolidated secondary-surface matrix artifact across feedback-enabled and feedback-disabled runtime profiles.

## Profile A: Feedback enabled runtime

Runtime target:
- `BIOMATE_URL=http://localhost:5407`

Command:
- `BIOMATE_URL=http://localhost:5407 npx playwright test e2e/ux-run-manager-panel.e2e.ts e2e/run-manager-large-set-visibility-cap.e2e.ts e2e/run-manager-refresh-sort-stability.e2e.ts e2e/run-manager-all-chats-mixed-load.e2e.ts e2e/ux-background-assist-panel.e2e.ts e2e/ux-offline-recovery.e2e.ts e2e/feedback-branches-deterministic.e2e.ts`

Results:
- Total: 7 tests
- Passed: 7
- Failed: 0

Notes:
- Deterministic feedback branch suite completed successfully and verified all expected feedback payload classes (`inline`, `post_run`, `download_check`, `confusion_report`).
- Run-manager edge tests remained stable (scope/filter/search/sort/refresh/visibility cap).
- Background assist and offline recovery surfaces both passed.

## Profile B: Feedback disabled runtime

Runtime target:
- `BIOMATE_URL=http://localhost:5411`
- `ENABLE_UX_FEEDBACK=false`

Sanity probe:
- `POST /api/feedback` returned `404` (disabled behavior confirmed before Playwright run).

Command:
- `ENABLE_UX_FEEDBACK=false BIOMATE_URL=http://localhost:5411 npx playwright test e2e/feedback-feature-flags-disabled.e2e.ts`

Results:
- Total: 1 test
- Passed: 1
- Failed: 0

Notes:
- Confirms disabled-mode expectations end-to-end:
  - feedback write endpoint rejected
  - feedback surfaces hidden
  - telemetry-disabled behavior remains aligned with suite expectation

## Consolidated matrix summary

- Combined executed tests: 8
- Combined passed: 8
- Combined failed: 0

## Operational takeaway

- Secondary surfaces are currently stable across both runtime feature-flag modes.
- No dataset-search behavior was modified in this pass.
