# WP-L0-3 Stage-B: Clickable Retry / Report Issue CTAs

Timestamp: 2026-03-01 11:42

## Goal

Complete the missing actionable UX path from Stage-A guidance by adding explicit clickable controls for:
- `Try again`
- `Report issue`

across both:
- chat-generation failure surfaces,
- execution failure surfaces.

## Root cause addressed

Even after standardizing error copy, the UI still had a functional gap:
- suggestion chips rendered but click handler was no-op (`console.log` only),
- execution error panel had report path but no direct retry action.

This meant users still needed manual recovery steps instead of direct intent-preserving actions.

## Implementation details

### 1) Report button callback support

Updated:
- `frontend/client/src/components/feedback/report-confusion-button.tsx`

Change:
- Added optional `onClick?: () => void` prop.
- Invoked callback before opening the dialog.

Purpose:
- Enables telemetry emission for explicit "report issue" CTA clicks without changing feedback submission payload behavior.

### 2) Chat error CTA actions are now real

Updated:
- `frontend/client/src/components/chat-message.tsx`

Changes:
- Added prop:
  - `onSuggestionClick?: (suggestion: string, message: Message) => void`
- Suggestion buttons now call `onSuggestionClick(...)` instead of logging.
- Added explicit error-surface action row (only when `message.metadata?.type === "error"`):
  - `Try again` button (`data-testid="button-async-try-again"`)
  - `Report confusion` button (shared component) with chat error context.

### 3) ChatInterface suggestion action dispatcher

Updated:
- `frontend/client/src/components/chat-interface.tsx`

Changes:
- Added `handleSuggestionClick(suggestion, message)` dispatcher:
  - `Try again`:
    - resolves last user prompt from session history,
    - re-sends via `handleSendMessage(lastPrompt)`,
    - emits telemetry `async.retry_clicked`.
  - `Report issue`:
    - emits telemetry `async.report_issue_clicked`.
  - fallback:
    - emits `chat.suggestion_clicked`.
- Wired `onSuggestionClick={handleSuggestionClick}` to `ChatMessage`.

### 4) Execution error panel retry action

Updated:
- `frontend/client/src/components/chat-with-artifacts.tsx`

Changes:
- Added `handleRetryExecution()`:
  - resolves latest workflow message in current session,
  - re-invokes `handleRunWorkflow(...)` with workflow + steps,
  - emits telemetry `async.retry_clicked`.
- Added explicit retry CTA:
  - button label: `Try again`
  - test id: `button-execution-try-again`
- Added telemetry for execution-surface report CTA click via `ReportConfusionButton.onClick`:
  - emits `async.report_issue_clicked`.

## New E2E coverage

Added:
- `frontend/e2e/ux-async-error-cta.e2e.ts`

Case:
- First `/api/chat` call mocked to fail (503).
- Verifies explicit `button-async-try-again` appears.
- Clicks retry CTA.
- Verifies second `/api/chat` attempt succeeds and recovery response is shown.

## Validation results

### Lint
- No linter errors for all edited files.

### E2E
1. `e2e/ux-async-error-cta.e2e.ts` → PASS
2. `e2e/ux-offline-recovery.e2e.ts` → PASS
3. Release matrix strict gate:
   - `feedback-real-ui-strict.e2e.ts` PASS
   - `pm-user-stories-comprehensive.e2e.ts` PASS
   - Result: `SUCCESS`
   - Artifact: `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_113738.txt`

## Data-testid contract additions

- `button-async-try-again` (chat error surface)
- `button-execution-try-again` (execution error surface)

## Remaining follow-ups (optional hardening)

1. Add dedicated E2E for execution retry path with mocked `/api/workflows/execute` fail-then-recover sequence.
2. Add debounce/lock for repeated rapid retry clicks.
3. Add explicit success toast after retry dispatch for immediate affordance confirmation.

