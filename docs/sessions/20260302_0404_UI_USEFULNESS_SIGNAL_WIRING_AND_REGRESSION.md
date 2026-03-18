# UI Usefulness Signal Wiring and Regression (2026-03-02 04:04)

## Scope
- Continue from backend usefulness contract work by surfacing status-level usefulness directly in workflow UI.
- Keep real-user flow stable and rerun critical E2E.

## Changes

### 1) Hook status mapping
- File: `frontend/client/src/hooks/useUnifiedExecution.ts`
- Added `usefulness` to run-status response typing and attached it to `currentRun.execution.nextflowStatus.usefulness` during polling updates.

### 2) Message -> viewer prop wiring
- File: `frontend/client/src/components/chat-message.tsx`
- Passed `currentExecutionRun.execution.nextflowStatus.usefulness` into `NextflowWorkflowViewer`.

### 3) Viewer UX state for non-useful completion
- File: `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- Added `usefulness` prop.
- Added `completedButNotUseful` derived state:
  - `status === "completed" && usefulness.meetsContract === false`
- Added visible alert block with counts:
  - total outputs
  - visualizable count
  - downloadable count
- Added recovery CTA button:
  - `data-testid="button-usefulness-recovery"`
  - triggers existing prerequisite recovery request flow.
- Added telemetry emission on recovery CTA click with `category: "usefulness_contract"`.

## Validation

### Build/lint
- `npm run build` passed.
- `ReadLints` returned no errors for modified files.

### Regression E2E
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=0`
- Result: **PASS**
- Confirms no regression in complete real-user workflow path after UI usefulness wiring.

## Outcome
- Users now have explicit, actionable UI feedback when a run is technically completed but does not meet usefulness expectations.
- Existing recovery action is reused, keeping behavior aligned with current prereq-recovery UX model.

