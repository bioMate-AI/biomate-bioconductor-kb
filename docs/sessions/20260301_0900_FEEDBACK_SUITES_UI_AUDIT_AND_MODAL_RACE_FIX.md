# Feedback Suites UI Audit and Modal Race Fix (2026-03-01 09:00)

## Scope
- Continue case-based UI auditing after confidence-gating updates.
- Re-run feedback-focused suites and fix any regressions found in real UI interaction.

## Suites Executed
1. `frontend/e2e/feedback-regression.e2e.ts`
2. `frontend/e2e/feedback-branches-deterministic.e2e.ts`

## Issue Found (Real UI)
- `feedback-regression.e2e.ts` failed on download icon click due to modal overlay intercepting pointer events.
- Failure evidence:
  - Overlay node (`fixed inset-0 ... bg-black/80`) intercepted click.
  - Root cause dialog in page snapshot: `Quick feedback` surfaced asynchronously after run completion.

## Fix Applied
- Updated `frontend/e2e/feedback-regression.e2e.ts`:
  - Added `dismissBlockingDialogs()` sweep helper before download interactions.
  - Handles both:
    - `Quick feedback` dialog (Skip/Close),
    - `session-end-pulse-dialog`.
  - Added repeated short-interval sweep to catch late-appearing modal race.

## Validation Results
- `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-regression.e2e.ts --project chromium --retries=0`
  - **PASS** (1 passed)
  - Download outcome prompt successfully surfaced and submitted after dialog sweep.
- `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-branches-deterministic.e2e.ts --project chromium --retries=0`
  - **PASS** (1 passed)
  - Deterministic feedback payload coverage verified: `inline`, `post_run`, `download_check`, `confusion_report`.

## Current State
- Feedback regression and deterministic branch suites both green under current UI behavior.
- Modal-race handling is now explicit in regression coverage.
