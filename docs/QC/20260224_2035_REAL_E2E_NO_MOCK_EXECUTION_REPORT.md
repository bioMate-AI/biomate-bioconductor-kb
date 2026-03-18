# BioMate Real E2E (No Mock) Execution Report

Date: 2026-02-24  
Scope: Drug-development UX comprehensive validation using only real backend/UI paths (no mock route interception).

## What Was Requested

- Document work in detail.
- Use real E2E tests after passing.
- Stop relying on mocked `/api/chat/stream` behavior.

## No-Mock Compliance

The previous mock interception in `frontend/e2e/drug-development-ux-comprehensive.e2e.ts` (`page.route("**/api/chat/stream", ...)`) was removed.

Current `DD-004` now:
- sends a real prompt to the live assistant,
- relies on real tool search/domain guard behavior,
- validates UI outcomes from real streamed responses.

## Files Updated

- `frontend/e2e/drug-development-ux-comprehensive.e2e.ts`
  - removed mocked SSE route for `DD-004`
  - added real-path prompt for diagnostic/failure-collaboration coverage
  - improved streaming completion waits (`AI is typing`, `BioMate is typing`, analysis status hidden, composer enabled)
  - made assertions resilient to real response variability while still validating UX outcomes
  - added single UI-level retry handling for transient connection errors

- `frontend/e2e/real-data-upload-through-chat.e2e.ts`
  - changed auth flow to login-first, register-second
  - switched default email from per-run random to stable `e2e_upload@biomate.test`
  - improved auth/upload failure diagnostics in assertions

## Real E2E Commands Run

From `frontend/`:

1) Comprehensive drug UX suite (real path)

`BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-ux-comprehensive.e2e.ts --project chromium --trace off`

2) Real data upload through chat (real file upload path)

`BIOMATE_URL=http://localhost:5000 npx playwright test e2e/real-data-upload-through-chat.e2e.ts --project chromium --trace off`

## Execution Result Matrix

### Suite A: `drug-development-ux-comprehensive.e2e.ts` (real, no mock)

- DD-001: pass
- DD-002: pass
- DD-003: pass
- DD-004: pass

Final run status: **4 passed (1.2m)**.

### Suite B: `real-data-upload-through-chat.e2e.ts` (real upload)

- Status: fail (environment/auth blocker)
- Observed:
  - register: `429 REGISTRATION_LIMIT_EXCEEDED`
  - login: `401 Invalid credentials`
  - upload: `401 Not authenticated`

This is a real-system limitation from current auth state/rate-limiter window, not a mock/test harness issue.

## Key Evidence Paths

- Drug UX suite latest artifacts:
  - `frontend/e2e/test-results/drug-development-ux-compre-92326-and-shows-full-run-controls-chromium/`
  - `frontend/e2e/test-results/drug-development-ux-compre-db4a7-ecovery-path-are-actionable-chromium/`
  - `frontend/e2e/test-results/drug-development-ux-compre-fd882-ible-for-drug-workflow-runs-chromium/`
  - `frontend/e2e/test-results/drug-development-ux-compre-ce929-e-and-diagnostic-real-path--chromium/`

- Real upload suite artifacts:
  - `frontend/e2e/test-results/real-data-upload-through-c-fcaf7-nd-proceeds-through-BioMate-chromium/`

## Interpretation

- The requested no-mock transition is complete for the comprehensive drug UX suite.
- The suite now verifies real UI behavior against live assistant/backend variability.
- One additional real E2E (upload-through-chat) is currently blocked by auth/rate-limit state in this environment.

## Immediate Unblock Plan for Real Upload E2E

Use one of the following before rerun:

1) Provide existing valid credentials:
- `BIOMATE_E2E_EMAIL=<existing_user_email>`
- `BIOMATE_E2E_PASSWORD=<existing_user_password>`

2) Wait for registration rate-limit window reset (1 hour), then rerun.

3) Pre-provision a dedicated persistent E2E user and use that account for login-only runs (recommended for CI/local repeatability).

## Next Recommended Real E2E Sequence

1) Keep running `drug-development-ux-comprehensive.e2e.ts` as the main no-mock UX gate.  
2) Rerun `real-data-upload-through-chat.e2e.ts` with pre-provisioned credentials to remove rate-limit dependence.  
3) Add this as a two-suite release gate for tomorrow demo readiness.

