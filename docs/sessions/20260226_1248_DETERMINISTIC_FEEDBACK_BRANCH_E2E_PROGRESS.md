# 2026-02-26 12:48 Progress: Deterministic Feedback Branch E2E Coverage

## Scope completed

Added deterministic E2E coverage for previously optional/skip-prone feedback branches:
- `report_confusion`
- `download_check`

## New test added

- File: `frontend/e2e/feedback-branches-deterministic.e2e.ts`

### Test design
- Mocks `POST /api/feedback` to capture and assert all submitted feedback payload types.
- Mocks `GET /api/invocations/*/outputs` with deterministic output data that satisfies UI schema, ensuring outputs section is rendered.
- Runs through flow:
  1. inline thumbs up
  2. workflow run + post-run survey submit
  3. download outcome prompt submit (via deterministic download action path)
  4. report confusion submit with comment
- Final assertion verifies captured feedback types include:
  - `inline`
  - `post_run`
  - `download_check`
  - `confusion_report`

## Issues encountered and fixes

1. **Strict locator collision** on output state badge (`data-testid` appeared twice).
   - Fix: scoped to first badge.

2. **Download action non-determinism** due to multiple output card variants and missing exact button in some branches.
   - Fix: adjusted flow to use deterministic UI path available in this run.

3. **Session-end pulse overlay interference** after post-run survey (blocked subsequent actions).
   - Fix: test explicitly detects and skips session pulse dialog before continuing branch checks.

## Validation

### Deterministic branch test
- Command: `cd frontend && BIOMATE_URL=http://localhost:5310 npx playwright test feedback-branches-deterministic.e2e.ts`
- Result: **PASS**

### Baseline regression still intact
- Command: `cd frontend && BIOMATE_URL=http://localhost:5310 npx playwright test feedback-regression.e2e.ts`
- Result: **PASS**

## Outcome

Feedback branch coverage is now deterministic for confusion and download feedback paths, reducing false skips and improving confidence in feedback flow regressions.
