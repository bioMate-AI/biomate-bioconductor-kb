# Run Manager Session Wiring and Switch E2E

Timestamp: 2026-03-01 13:00

## Why this follow-up was needed

After introducing the Run Manager panel, we still had two practical gaps:

1. Run listing was not explicitly scoped by `chatSessionId` in the query path.
2. No dedicated E2E existed for Run Manager quick-switch behavior.

This update closes both.

## Backend/session contract updates

### 1) Create execution run payload now carries session linkage

File:
- `frontend/shared/schema.ts`

Updated `createExecutionRunRequestSchema`:
- `chatSessionId?: string`
- `projectId?: string`

This formalizes session-level linkage in the run creation request contract.

### 2) Storage now persists and filters by `chatSessionId`

File:
- `frontend/server/storage.ts`

Changes:
- `createExecutionRun` now stores `request.chatSessionId` into `ExecutionRun.chatSessionId`.
- `getExecutionRuns(...)` signature extended with optional `chatSessionId`.
- Added filter branch in `getExecutionRuns` for `chatSessionId`.

### 3) Runs API supports session filter

File:
- `frontend/server/routes.ts`

Updated:
- `GET /api/workflows/runs` now accepts `chatSessionId` query param.
- Passes it through to storage filter.

## Frontend wiring updates

### 1) Execute workflow now includes current chat session ID

File:
- `frontend/client/src/components/chat-with-artifacts.tsx`

Change:
- `executeWorkflow(...)` now sends `chatSessionId: currentChatSession?.id`.

### 2) Run Manager fetch now requests session-scoped runs

File:
- `frontend/client/src/components/chat-with-artifacts.tsx`

Change:
- run list fetch now builds query params and includes:
  - `limit=50`
  - `chatSessionId=<current session id>` when available.

## New dedicated E2E

Added:
- `frontend/e2e/ux-run-manager-panel.e2e.ts`

Coverage:
- opens Run Manager panel
- verifies all 4 buckets rendered
- verifies run items are listed
- clicks a run item to trigger quick-switch (`loadRun`)
- verifies selected run item gets active styling (`border-primary`)

## Validation and evidence

### Lint
- No lint errors in all modified files.

### Build
- `npm run build` passed.

### E2E
- `ux-run-manager-panel.e2e.ts` PASS
- `ux-autofix-gate.e2e.ts` PASS
- release matrix strict gate PASS:
  - `feedback-real-ui-strict.e2e.ts` PASS
  - `pm-user-stories-comprehensive.e2e.ts` PASS
- matrix artifact:
  - `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_125328.txt`

## Clarification on “why this was missing”

Galaxy-Nextflow and BioMate backend already had multi-run execution/tracking primitives.
What was missing in main chat UX was:
- first-class session-scoped run discovery wiring,
- explicit quick-switch user affordance with dedicated test coverage.

This update completes that wiring path.

## Remaining next step (optional but recommended)

Add proactive “background task suggestions” while run is active (Claude-like prompt):
- e.g., “Workflow is running — I can validate outputs schema, draft report outline, or prepare next workflow.”
- This is a UX behavior layer, separate from run manager/state wiring.

