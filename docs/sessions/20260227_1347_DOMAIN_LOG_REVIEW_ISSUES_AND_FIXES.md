# Domain Log Review: Issues and Improvements (2026-02-27 13:47)

## What logs showed

From current matrix and case-based runs, the highest-impact product issues were:

1. Download path fragility when UI had an execution run ID instead of invocation ID.
2. Workflow-panel `Download All`/`View Results` controls were not consistently surfaced.
3. Pending cue identifier mismatch (`typing-indicator` present, but no `chat-response-pending` hook expected by tests/audits).
4. A legacy workflow artifact `Download` button was visible but not wired to any action.

## Evidence used

- `frontend/e2e/matrix-runs/feedback-matrix-run-20260227_083951/feedback-regression.console.log`
  - `Download controls debug: direct(v=false,e=false) all(v=false,e=false) icon(v=true,e=true)`
- `frontend/e2e/test-results/domain-case-performance.../error-context.md`
  - Workflow cards present with run controls and disabled download controls in some paths.
- `frontend/e2e/test-results/domain-case-performance.../domain-case-performance-report.json`
  - Domain cases pass functional cues; feedback and execution paths are exercised.

## Product fixes implemented

### 1) Download route now accepts execution run IDs (server-side functional fix)

- File: `frontend/server/routes.ts`
- Change: `/api/invocations/:id/download-all` now resolves:
  - direct invocation id, OR
  - execution run id -> `execution.galaxyInvocationId` -> invocation lookup.
- Effect: reduces false "Invocation not found" when frontend passes run-backed IDs.

### 2) Workflow panel action controls are always visible (clearer UX, less hidden state)

- File: `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- Change:
  - `View Results` and `Download All` render consistently.
  - Buttons are disabled with explanatory title when `invocationId` is not yet available.
  - Added `data-testid="button-download-all-workflow-panel"` for deterministic tracking.

### 3) Pending cue now has expected audit/test hook

- File: `frontend/client/src/components/typing-indicator.tsx`
- Change:
  - Root element test id changed to `chat-response-pending`.
- Effect:
  - Aligns UI pending indicator with log/test expectations and monitoring.

### 4) Legacy completion download action is now wired

- File: `frontend/client/src/components/workflow-artifact.tsx`
- Change:
  - Completion-panel `Download` button now opens `/api/invocations/{invocationId}/download-all`.
  - Disabled state now depends on both `invocationId` and `outputs`.

## Validation run after fixes

- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-regression.e2e.ts e2e/domain-case-performance.e2e.ts --project chromium`
- Outcome:
  - `feedback-regression`: passed
  - `domain-case-performance`: passed after one retry (flaky on feedback confirmation text once)

## Remaining issue to continue hardening

- Domain case suite had one flaky first-attempt check for `"Thanks for your feedback"` confirmation.
- Recommendation:
  - Make that assertion tolerant to either toast/dialog confirmation states, while keeping true UI feedback submission verification.

