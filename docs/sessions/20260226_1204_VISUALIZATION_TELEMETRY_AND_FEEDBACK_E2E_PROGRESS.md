# 2026-02-26 12:04 Progress: Visualization Telemetry + Feedback E2E

## Scope Completed

Implemented the next PM-priority items for UX observability and regression protection:

1. Added `output.visualization_opened` instrumentation for real user visualization actions.
2. Added a dedicated feedback regression E2E test for inline feedback and post-run survey, with optional download outcome flow.

## Code Changes

### 1) Visualization telemetry event typing
- File: `frontend/client/src/lib/ux-telemetry.ts`
- Added event name:
  - `output.visualization_opened`

### 2) Visualization interaction instrumentation
- File: `frontend/client/src/components/chat-output-attachments.tsx`
- Added `emitUxEvent('output.visualization_opened', ...)` for:
  - Image output: `Open Full Size` (`action: open_full_size`)
  - Image output: inline expand via Eye button (`action: expand_inline`)
  - Interactive output: `Open in New Tab` (`action: open_new_tab`)
  - Interactive output: inline expand via Eye button (`action: expand_inline`)
- Payload includes:
  - `outputId`, `outputName`, `fileType`, `invocationId`, `action`

- File: `frontend/client/src/components/viewers/interactive-tool-launcher.tsx`
- Added `invocationId` prop and telemetry on interactive tool launch open:
  - `action: open_interactive_tool`
  - Includes `toolId`, `toolName`, `invocationId`

## Feedback Regression E2E Test

### New test
- File: `frontend/e2e/feedback-regression.e2e.ts`

### Test coverage
1. **Mandatory:** Inline thumbs feedback submit
   - Click thumbs-up
   - Assert confirmation text: `Thanks for your feedback`
2. **Mandatory:** Post-run micro survey submit
   - Wait for survey dialog after run terminal state
   - Answer Yes/Yes/Yes
   - Submit and assert dialog closes
3. **Optional:** Download outcome prompt
   - If download button is available and enabled, click and assert prompt flow
   - If no downloadable output is available, emit explicit SKIP log without failing test

### Testability updates
- `frontend/client/src/components/feedback/inline-feedback-widget.tsx`
  - Added `data-testid`: `inline-feedback-widget`, `inline-feedback-thumbs-up`, `inline-feedback-thumbs-down`
- `frontend/client/src/components/feedback/post-run-micro-survey.tsx`
  - Added `data-testid`: `post-run-survey-dialog`
- `frontend/client/src/components/feedback/download-outcome-prompt.tsx`
  - Added `data-testid`: `download-outcome-prompt-dialog`

## Verification Results

### Build
- Command: `cd frontend && npm run build`
- Result: **PASS**

### Lint diagnostics for edited files
- Result: **No linter errors found**

### E2E
- Command: `cd frontend && BIOMATE_URL=http://localhost:5310 npx playwright test feedback-regression.e2e.ts`
- Result: **PASS**
- Runtime: ~1.2 min
- Key output:
  - Inline feedback flow: passed
  - Post-run survey flow: passed
  - Download outcome flow: skipped due to no downloadable output in this run

## Notes

- This milestone closes the explicit PM item for `output.visualization_opened` instrumentation.
- Feedback flow regression now has dedicated UI coverage for mandatory user feedback actions.
