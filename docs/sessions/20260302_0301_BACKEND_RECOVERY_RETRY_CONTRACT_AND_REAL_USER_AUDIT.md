# Backend Recovery Retry Contract + Real User Audit (2026-03-02 03:01)

## Objective
- Continue real-user system testing by fixing the prerequisite-recovery convergence gap.
- Ensure recovery path does not stop at "no match" and instead retries with bounded fallback logic until a runnable workflow contract is satisfied or best effort is returned.

## Root Cause Confirmed
- `frontend/server/galaxy-api-proxy.ts` used lightweight endpoint `/api/ai_assistant/search_nextflow_workflow` first.
- When that endpoint returned `success: false` (for example, `No matching workflows found`), proxy did **not** force deterministic fallback to `/api/ai_assistant/generate_workflow` in the same request path.
- This created recovery dead-ends in real UI runs.

## Code Changes

### File
- `frontend/server/galaxy-api-proxy.ts`

### What changed
1. Added runnable contract validation helper:
   - Accepts only responses with:
     - valid `nextflow_path`, or
     - `workflow_ga.steps` object with at least one step.
2. Added bounded trial strategy in `generateWorkflow()`:
   - Trial lightweight search first.
   - If not runnable, run fallback full generation trials.
   - For prerequisite-recovery intents, use enriched retry intents (bounded list).
3. Preserved existing behavior for normal intents while adding deterministic fallback for recovery path.

## Validation Commands
- `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=0`
- `rm -rf e2e/test-results && BIOMATE_URL=http://localhost:5310 npx playwright test e2e/pm-user-stories-comprehensive.e2e.ts --project chromium --retries=1`

## Validation Results

### 1) `complete-workflow.e2e.ts`
- **PASS**
- Key evidence:
  - execution run id captured: `b32c7659-4e2c-4fdb-a362-38dfec806072`
  - backend terminal status reached `completed`
  - output checks passed: visualizable + downloadable
  - proxy logs consistently showed `Workflow found via: template_reuse`

### 2) `pm-user-stories-comprehensive.e2e.ts`
- Functional assertions passed, but run marked **flaky** due known Playwright artifact ENOENT race on first attempt.
- Retry passed fully for US-003.
- This remains infrastructure noise, not a deterministic UX/backend functional failure.

## Remaining Risk
- Recovery path still selected Nextflow workflows represented with `steps: 0` in UI metadata (expected for Nextflow descriptors), while execution succeeded via Nextflow path.
- For stricter user trust, next hardening should validate not only "runnable contract" but also "output usefulness contract" (minimum expected report/output type per workflow class).

## Next Fix Slice
1. Add backend-side explicit recovery metadata with selected retry trial and reason (for auditability).
2. Add stricter acceptance criteria in E2E:
   - fail if execution reports completed but no concrete output artifact metadata is present.
3. Isolate Playwright artifact race by directing traces to per-test unique directory in this suite.

