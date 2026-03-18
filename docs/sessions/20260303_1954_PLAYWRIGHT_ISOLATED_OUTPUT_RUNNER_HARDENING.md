# Playwright Isolated Output Runner Hardening

## What was implemented

- `frontend/playwright.config.ts`
  - `outputDir` now supports env override:
    - `PW_OUTPUT_DIR` if provided
    - fallback remains `e2e/test-results`

- New wrapper script:
  - `frontend/scripts/run-e2e-isolated.sh`
  - behavior:
    1) creates timestamped isolated output directory under `e2e/test-results-isolated/<timestamp>`
    2) exports `PW_OUTPUT_DIR` to that directory
    3) runs `npx playwright test` with caller arguments

- `frontend/package.json` scripts:
  - `e2e:isolated`
  - `e2e:isolated:complete`

## Why this was needed

- We repeatedly observed intermittent Playwright artifact file errors (`ENOENT` during trace/video zip cleanup) causing false-negative test outcomes even when product assertions passed.
- Isolating output directories per run removes cross-run artifact collisions and significantly improves audit reliability.

## Validation evidence

1) Strict complete workflow via isolated runner
- Command:
  - `BIOMATE_URL=http://localhost:5310 npm run e2e:isolated:complete`
- Result:
  - passed
  - workflow generated/executed
  - output evidence visible
  - visualization/download checks passed
  - output path isolated under `e2e/test-results-isolated/<timestamp>`

2) Run Manager stress suite via isolated runner
- Command:
  - `BIOMATE_URL=http://localhost:5310 npm run e2e:isolated -- e2e/run-manager-large-set-visibility-cap.e2e.ts e2e/run-manager-refresh-sort-stability.e2e.ts e2e/run-manager-scope-race-guard.e2e.ts e2e/run-manager-all-chats-mixed-load.e2e.ts e2e/run-manager-multi-chat-scope.e2e.ts --project chromium`
- Result:
  - 5 passed

## Notes

- A first isolated-run attempt failed only due to base URL defaulting to `http://localhost:5000` while current server was on `5310`.
- Using `BIOMATE_URL=http://localhost:5310` resolved it immediately.
