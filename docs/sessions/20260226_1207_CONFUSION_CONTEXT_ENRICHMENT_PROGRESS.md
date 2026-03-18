# 2026-02-26 12:07 Progress: Confusion Context Enrichment

## Scope

Continued PM-priority UX instrumentation work by auto-populating richer context for confusion reports.

## Implemented

### 1) Nextflow workflow viewer now sends richer confusion context
- File: `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- Added optional prop:
  - `errorMessage?: string`
- `ReportConfusionButton` now includes:
  - `sessionId`
  - `workflowId`
  - `invocationId`
  - `runId`
  - context payload fields:
    - `executionStatus`
    - `errorMessage`
    - `workflowName`
    - `progress`
    - `showResults`

### 2) Output attachments confusion reports now include execution metadata
- File: `frontend/client/src/components/chat-output-attachments.tsx`
- Added optional props:
  - `executionStatus?: string`
  - `errorMessage?: string`
- `ReportConfusionButton` context now includes:
  - `outputCount`
  - `executionStatus`
  - `errorMessage`
  - `hasVisualizations`
  - `hasTables`

### 3) Upstream wiring from message context
- File: `frontend/client/src/components/chat-message.tsx`
- For `NextflowWorkflowViewer`, now passes:
  - `workflowId`
  - `errorMessage` from `currentExecutionRun?.execution?.errorMessage`
- For direct `ChatOutputAttachments`, now passes:
  - `executionStatus` from `currentExecutionRun?.execution?.status`
  - `errorMessage` from `currentExecutionRun?.execution?.errorMessage`

## Validation

### Build
- Command: `cd frontend && npm run build`
- Result: **PASS**

### Lint diagnostics
- Checked edited files with IDE diagnostics
- Result: **No linter errors**

### Regression E2E
- Command: `cd frontend && BIOMATE_URL=http://localhost:5310 npx playwright test feedback-regression.e2e.ts`
- Result: **PASS**
- Observed:
  - Inline feedback flow passed
  - Post-run survey flow passed
  - Download outcome prompt skipped due to no downloadable output in this run

## Outcome

Confusion reports are now materially more actionable for triage, with execution state and error context automatically attached at both workflow-level and output-level report entry points.
