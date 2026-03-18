# 2026-03-01 19:27 — Real User System Test Continuation

## What was tested in this continuation

After the previous audit, I continued real-user E2E validation with focus on two critical gaps:

1. `/api/chat` contract stability (`suggestions` field)
2. False-success workflow execution path (completed state with non-visualizable outputs)

## Actions taken

### A) Runtime deployment refresh

- Rebuilt and restarted frontend server on `:5310` to ensure latest code is active.

### B) `/api/chat` suggestions contract fix

- Added `suggestions` into successful and fallback `/api/chat` responses in:
  - `frontend/server/routes.ts`
- Re-tested with:
  - `e2e/real-api-integration.e2e.ts`
- Result:
  - API health check now sees `suggestions` in response keys.

### C) Prerequisite guard tightened to prevent false-success runs

- Updated workflow run gating in:
  - `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- Behavior change:
  - `Run Workflow` and low-confidence override button are disabled when checklist is not runnable (`!prereqChecklist.canRun`).
  - Execute handler now no-ops when prerequisites are unmet.

## Validation results

### 1) `real-api-integration + complete-workflow`

Command:
`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/real-api-integration.e2e.ts e2e/complete-workflow.e2e.ts --project chromium --retries=0`

Result:
- `real-api-integration`: 4/4 passed
- `complete-workflow`: failed

Failure reason:
- The test now hits a **prerequisite block** before execution:
  - Run button remains disabled even after follow-up user prompt asking for test/sample data.

Interpretation:
- This is safer than prior behavior (which allowed run → completed with empty outputs), but still reveals unresolved product gap:
  - assistant flow did not converge to a runnable state with valid inputs/datasets for this scenario.

### 2) `pm-user-stories-comprehensive`

Command:
`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/pm-user-stories-comprehensive.e2e.ts --project chromium --retries=0`

Result:
- US-001 pass
- US-002 pass
- US-003 fail

Failure reason:
- `Run Workflow` remains disabled after prerequisite-recovery prompt.
- This confirms the issue is reproducible across independent real-user style suites.

## Net effect vs previous state

Improved:
- `/api/chat` contract consistency restored (`suggestions` present).
- Unsafe false-success run path is blocked (no longer allowing "completed but unusable outputs" through this UI path).

Still failing real-user objective:
- The system often does not transition from "prerequisites unmet" to "runnable workflow with usable outputs" in the tested RNA-seq flow.

## Next highest-value fix target

Implement deterministic prerequisite recovery UX + backend handoff:

1. Add explicit assistant action when checklist blocks run:
   - "Prepare runnable demo data"
   - "Map existing datasets"
2. Persist chosen recovery action into execution context.
3. Re-generate workflow with that context until checklist becomes runnable (bounded retries).
4. Then rerun `complete-workflow` and `pm-user-stories` US-003.
