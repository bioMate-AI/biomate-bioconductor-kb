# Consolidated UI Acceptance Matrix (2026-03-01 09:08)

## Objective
- Execute a consolidated UI acceptance pass across core confidence-gating and feedback flows after recent fixes.
- Confirm stability with real UI interaction and deterministic branch coverage.

## Environment
- Base URL: `http://localhost:5310`
- Browser project: `chromium`
- Retry mode: `--retries=0`

## Suites and Results
1. `frontend/e2e/low-confidence-override.e2e.ts`
   - Command:
     - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/low-confidence-override.e2e.ts --project chromium --retries=0`
   - Result:
     - **PASS** (`3 passed`)
   - Coverage:
     - domain-guard blocked run path
     - feedback-only low-confidence blocked run path
     - high-confidence run-enabled path
     - override payload contract verification

2. `frontend/e2e/domain-case-performance.e2e.ts`
   - Command:
     - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/domain-case-performance.e2e.ts --project chromium --retries=0`
   - Result:
     - **PASS** (`1 passed`)
   - Coverage:
     - domain response/performance checks
     - confidence-gated execution path including override handling

3. `frontend/e2e/feedback-regression.e2e.ts`
   - Command:
     - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-regression.e2e.ts --project chromium --retries=0`
   - Result:
     - **PASS** (`1 passed`)
   - Notable runtime evidence:
     - Quick-feedback modal race occurred and was handled by dialog sweep.
     - Download outcome prompt was surfaced and successfully submitted.

4. `frontend/e2e/feedback-branches-deterministic.e2e.ts`
   - Command:
     - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-branches-deterministic.e2e.ts --project chromium --retries=0`
   - Result:
     - **PASS** (`1 passed`)
   - Deterministic payload branches verified:
     - `inline`, `post_run`, `download_check`, `confusion_report`

## Aggregate Outcome
- **Total suites:** 4
- **Total tests passed:** 6
- **Total tests failed:** 0

## Residual Risk / Gaps
- In `feedback-regression`, post-run survey can still be intermittently replaced/superseded by quick-feedback/session-pulse overlays depending on timing; the suite now handles this race explicitly, but UX sequencing remains timing-sensitive.
- Deterministic suite still contains intentional fallback POST behavior for branch completeness in mock contexts; this is acceptable for deterministic coverage but should be complemented by real-UI-only branch assertions where feasible.
