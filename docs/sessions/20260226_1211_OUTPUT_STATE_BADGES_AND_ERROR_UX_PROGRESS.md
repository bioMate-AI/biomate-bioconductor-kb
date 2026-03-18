# 2026-02-26 12:11 Progress: Output State Badges + Error UX Guidance

## Scope Completed

Implemented two pending PM-priority UX improvements:

1. Result-state badges in output panel.
2. Timeout/error UX with explicit reason, retry guidance, and escalation path.

## Implemented Changes

### 1) Output panel result-state badges
- File: `frontend/client/src/components/chat-output-attachments.tsx`
- Added `StatusBadge` display near the `Outputs` header with `data-testid="output-result-state-badge"`.
- States now shown:
  - `No outputs yet` (pending)
  - `Outputs found` (success)
  - `Partial outputs` (warning)
- State logic uses execution status plus output availability:
  - Partial: failed/cancelled or running with some outputs
  - Outputs found: terminal completed with outputs
  - No outputs yet: otherwise

### 2) Execution timeout/error guidance panel
- File: `frontend/client/src/components/chat-with-artifacts.tsx`
- Added structured guidance helper:
  - Detects timeout-like errors (`timeout`, `timed out`, `deadline exceeded`, `etimedout`)
  - Returns tailored messaging:
    - Title (`Execution timed out` vs `Execution failed`)
    - Reason
    - Retry guidance
    - Escalation path
- Replaced simple single-line error bar with a richer error panel containing:
  - Reason
  - Retry guidance
  - Escalation path
  - Inline `ReportConfusionButton` for immediate contextual escalation
- `ReportConfusionButton` context includes:
  - `executionStatus`
  - `errorMessage`
  - `workflowName`
  - IDs (`runId`, `sessionId`, `invocationId`, `workflowId`)

## Validation

### Build
- Command: `cd frontend && npm run build`
- Result: **PASS**

### Lint diagnostics
- Edited files checked with IDE diagnostics
- Result: **No linter errors**

### Feedback regression E2E
- Command: `cd frontend && BIOMATE_URL=http://localhost:5310 npx playwright test feedback-regression.e2e.ts`
- Result: **PASS**
- Observed:
  - Inline thumbs feedback: passed
  - Post-run survey: passed
  - Download outcome prompt: skip-safe when no downloadable output present

## Outcome

Users now see immediate, explicit output state signals and clearer failure handling guidance, reducing ambiguity and improving next-step clarity when runs do not succeed cleanly.
