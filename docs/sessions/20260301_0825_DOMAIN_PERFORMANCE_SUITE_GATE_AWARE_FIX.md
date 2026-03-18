# Domain Performance Suite Gate-Aware Fix (2026-03-01 08:25)

## Issue Found
- `frontend/e2e/domain-case-performance.e2e.ts` failed in real UI run:
  - The suite attempted to click `Run Workflow` when that button was intentionally disabled by confidence gating.
  - Failure mode: Playwright timeout on disabled button click.

## Root Cause
- Test logic only checked button **visibility** (`runActionVisible`) and assumed clickability.
- After low-confidence policy hardening, real product behavior can validly present:
  - disabled `Run Workflow`
  - visible `Confirm and Run Anyway`.
- The old suite did not model that user path.

## Fix Applied
- Updated `gatherCaseMetric` in `frontend/e2e/domain-case-performance.e2e.ts`:
  - Detect whether `Run Workflow` is enabled.
  - If enabled: click run.
  - If disabled and override button is visible: click `button-confirm-low-confidence-run`.
  - Added `overrideUsed` metric for auditability.

## Validation
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/domain-case-performance.e2e.ts --project chromium --retries=0`
- Result:
  - **PASS** (1 passed)

## Impact
- Domain performance suite now aligns with current confidence-gated UX.
- Reduces false failures and preserves real-user execution path coverage.
