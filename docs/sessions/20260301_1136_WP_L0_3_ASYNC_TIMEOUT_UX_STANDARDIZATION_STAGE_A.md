# WP-L0-3 Async/Timeout UX Standardization (Stage-A)

Timestamp: 2026-03-01 11:36

## Objective

Start standardizing async/timeout failure UX so users get consistent guidance and explicit retry/report language across:
- chat generation failures (`/api/chat` path),
- workflow execution failures (run status/errors).

## Delivered changes

### 1) Shared guidance policy module

- Added `frontend/client/src/lib/async-guidance.ts`.
- Introduced:
  - `getChatAsyncGuidance(error, { isOnline })`
  - `getExecutionAsyncGuidance(error, { isOnline })`
- Both functions classify:
  - timeout-like errors,
  - network/disconnection-like errors,
  - generic backend/validation failures.

### 2) Execution error panel now uses shared policy

- Updated `frontend/client/src/components/chat-with-artifacts.tsx`:
  - Removed local one-off execution error classifier.
  - Replaced with `getExecutionAsyncGuidance(...)`.
  - Guidance now aligns with offline state and retains existing `ReportConfusionButton`.

### 3) Chat API error message now uses shared policy

- Updated `frontend/client/src/components/chat-interface.tsx`:
  - Integrated `getChatAsyncGuidance(...)`.
  - Uses a normalized message template:
    - Title
    - Reason
    - Try again guidance
    - Report issue guidance
  - Updated error suggestions to include explicit `"Report issue"` option.

### 4) Connectivity signal reused

- Reused `useNetworkStatus()` for guidance contextualization (`isOnline` input).

## Why this is Stage-A

- We standardized copy and decision policy first without introducing new retry side effects.
- Explicit "Try again" and "Report issue" are now always surfaced in failure guidance text/suggestions.
- Follow-up Stage-B can add dedicated CTA buttons with deterministic handlers (`retry_last_prompt`, `report_issue` action dispatch).

## Verification

Lints:
- No new lint errors in edited files.

E2E:
- `e2e/ux-offline-recovery.e2e.ts` PASS (`1 passed`)
- `e2e:feedback:matrix` in release strict mode PASS
  - `feedback-real-ui-strict.e2e.ts` PASS
  - `pm-user-stories-comprehensive.e2e.ts` PASS
  - Result: `SUCCESS`
  - Artifact: `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_113139.txt`

## Remaining WP-L0-3 items

1. Add explicit clickable retry CTA in execution error panel (not just text guidance).
2. Add explicit "Report issue" CTA for chat-generation failures (button-level affordance).
3. Add timeout-specific telemetry dimensions:
   - `async.error_classified`
   - `async.retry_clicked`
   - `async.report_issue_clicked`

