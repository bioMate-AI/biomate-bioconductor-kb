# Low-Confidence Override E2E and UI Signal Hardening (2026-03-01 07:24)

## Objective
- Add a dedicated regression test that permanently guards the policy flow:
  1) blocked run state surfaced in UI,
  2) explicit "Confirm and Run Anyway" action,
  3) execution request includes low-confidence override flag.

## Changes Implemented
- Added deterministic E2E test: `frontend/e2e/low-confidence-override.e2e.ts`.
  - Mocks `/api/chat` with a low-confidence workflow response.
  - Verifies blocked run state is rendered.
  - Clicks `button-confirm-low-confidence-run`.
  - Asserts `/api/workflows/execute` receives:
    - `executionConfig.allowLowConfidence === true`
    - `generationAssessment.userConfirmedLowConfidence === true`
- Hardened blocked-reason derivation in `frontend/client/src/components/chat-message.tsx`.
  - `executionBlockedReason` now resolves from either:
    - message-level metadata (`domainGuard`, `needsUserFeedback`, `feedbackPrompt`)
    - workflow-level metadata fallback (`domain_guard`, `needs_user_feedback`, `feedback_prompt`).
- Fixed runtime telemetry bug in `frontend/client/src/components/chat-interface.tsx`.
  - Added missing import for `emitUxEvent` to prevent `ReferenceError` on workflow generation telemetry path.

## Validation
- Lint checks: clean for all modified files.
- Playwright:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/low-confidence-override.e2e.ts --project chromium --retries=0`
  - Result: **PASS** (1 passed).

## Root-Cause Notes
- Initial failures were caused by testing against a stale server bundle on port 5310.
  - Rebuilt frontend and restarted the test server to align runtime behavior with latest source.
- While validating the new flow, the workflow-generated telemetry path exposed a missing import (`emitUxEvent`), now fixed.

## Impact
- The low-confidence override policy now has a dedicated deterministic E2E guard.
- UI block-state signal handling is more resilient across metadata-shape variants.
- Workflow-generation telemetry path no longer throws runtime `ReferenceError`.
