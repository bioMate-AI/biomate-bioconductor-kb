# 2026-03-01 19:33 — Real User System Test Iteration Log

## Goal of this iteration

Continue real-user system testing and move from "audit-only" to direct fixes on the failing workflow path:
- `/api/chat` consistency
- prerequisite recovery
- `complete-workflow` and PM US-003 convergence

## Implemented changes

1) `/api/chat` response contract
- Added `suggestions` in success/fallback response payload (`frontend/server/routes.ts`).

2) Safety gate for run action
- Kept prerequisite-run block in workflow viewer to avoid false-success execution with empty outputs.

3) New prerequisite recovery UX action
- Added checklist CTA button:
  - `data-testid="button-prereq-recovery"`
  - label: "Ask BioMate to prepare runnable demo inputs"
- Wired action through:
  - `nextflow-workflow-viewer.tsx`
  - `chat-message.tsx`
  - `chat-interface.tsx`
  - `chat-with-artifacts.tsx`
- CTA submits a deterministic assistant prompt via existing external prompt mechanism.

4) E2E updates
- `complete-workflow.e2e.ts`: if run is disabled, click recovery CTA (fallback to typed prompt), then re-check run.
- `pm-user-stories-comprehensive.e2e.ts` US-003: same recovery behavior before run click.

## Test outcomes in this iteration

### A. Critical API + complete workflow re-run
Command:
`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/real-api-integration.e2e.ts e2e/complete-workflow.e2e.ts --project chromium --retries=0`

Result:
- `real-api-integration`: passed
- `complete-workflow`: failed

Failure:
- run button remains disabled after prerequisite recovery.

### B. PM user stories re-run
Command:
`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/pm-user-stories-comprehensive.e2e.ts --project chromium --retries=0`

Result:
- US-001 pass
- US-002 pass
- US-003 fail

Failure:
- run button still disabled after recovery step.

## Current root blocker

The assistant-side recovery prompt does not reliably produce a workflow state where prerequisites become runnable (input requirement remains unmet).

In other words:
- UX now surfaces and requests recovery,
- but backend/workflow generation does not deterministically transition to executable state.

## Next fix target (required for true real-user pass)

Implement backend-level deterministic prerequisite recovery path (not just chat prompt):
- when recovery is requested, generate/map concrete runnable input context for that workflow class,
- then regenerate/patch workflow + validation until checklist is runnable (bounded retries),
- only then allow run.
