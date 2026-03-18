# 2026-03-01 19:09 — Real User System Test Audit

## Scope

Executed broad UI-first E2E suites against `http://localhost:5310` to simulate real-user behavior across:
- workflow generation/execution,
- run management and multitask UX,
- confidence gates,
- feedback and result actions.

## Test runs

### Run A — Broad real-user suite (PASS)

Command:

`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/pm-user-stories-comprehensive.e2e.ts e2e/feedback-real-ui-strict.e2e.ts e2e/realistic-user-flow.e2e.ts e2e/real-user-visual-evaluation.e2e.ts e2e/domain-case-performance.e2e.ts e2e/low-confidence-override.e2e.ts e2e/ux-run-manager-panel.e2e.ts e2e/ux-background-assist-panel.e2e.ts --project chromium --retries=0`

Result:
- 13 passed (10.6m)

Coverage highlights:
- Real multi-turn workflow dialogue and execution attempts
- Low-confidence block + override
- Run manager + background assist interactions
- Domain-case performance path

### Run B — Real API / execution stress suite (PARTIAL FAIL)

Command:

`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/real-api-integration.e2e.ts e2e/real-workflow-execution.e2e.ts e2e/complete-workflow.e2e.ts --project chromium --retries=0`

Result:
- 4 passed, 2 failed

## Follow-up validation (same session)

### Run C — Targeted re-check of `/api/chat` API suite (PARTIAL FAIL)

Command:

`BIOMATE_URL=http://localhost:5310 npx playwright test e2e/real-api-integration.e2e.ts --project chromium --retries=0`

Result:
- 3 passed, 1 failed
- `Backend API Health` still fails for missing `suggestions` key in `/api/chat` response.

Note:
- A backend patch was applied in `frontend/server/routes.ts` to always include `suggestions`.
- The active server at `:5310` appears to still be serving pre-patch behavior during this run (likely stale process/build), so runtime verification is still pending after restart/redeploy.

## Findings (ordered by severity)

### 1) Critical user-value failure: run can complete with no visualizable outputs

Failed suite:
- `e2e/complete-workflow.e2e.ts`

Observed behavior:
- UI reached terminal `COMPLETED`
- Download action was visible
- Output panel still showed `No outputs generated yet`
- Visualization requirement failed (`outputVisualizable=false`)

Real-user impact:
- User sees success state without usable, visualized results.
- This violates the practical completion standard (execution + visualizable + downloadable output).

Correlated UI snapshot evidence:
- Execution checklist showed **Input data missing**
- same card showed **100% COMPLETED**
- Output Results still empty.

Interpretation:
- Current flow can produce "completed" UX even when prerequisites/data completeness would not support meaningful outputs.

### 2) API contract drift on `/api/chat` health test (`suggestions` missing)

Failed suite:
- `e2e/real-api-integration.e2e.ts` (`Backend API Health`)

Observed behavior:
- Response returned `response`, `workflow`, `metadata`, etc.
- `suggestions` field absent, causing assertion failure.

Real-user impact:
- Lower direct UX impact than Finding #1, but indicates contract inconsistency for clients relying on suggestion chips.

Status:
- Code-level fix applied, runtime still failing until refreshed backend process picks up changes.

### 3) Runtime reliability signal: 429 rate-limit during real workflow execution path

Observed in logs from:
- `e2e/real-workflow-execution.e2e.ts`

Observed behavior:
- Console captured `429 (Too Many Requests)`
- In same scenario, no run button found and invocation count remained 0.

Real-user impact:
- Intermittent inability to execute workflows under realistic conversational usage.
- Can present as "assistant responded but workflow not runnable."

## Immediate recommendations

1. **Prioritize output-integrity gate over cosmetic pass criteria**
   - Do not report execution as complete-success in UX when output collection is empty for output-producing workflows.
   - Surface clear terminal substate: `completed_no_outputs` with guided recovery actions.

2. **Enforce data-readiness guard before execute**
   - If required input datasets are missing, block run action with explicit CTA instead of allowing execution path that yields empty outputs.

3. **Stabilize `/api/chat` response contract**
   - Return `suggestions` consistently (empty array allowed) to avoid UI and test drift.

4. **Add rate-limit aware UX fallback**
   - For 429, show deterministic retry guidance and backoff in UI, with session-preserving retry.

## Next execution plan

- Reproduce Finding #1 in focused isolation (`complete-workflow.e2e.ts`) after each fix.
- Add explicit assertion suite for:
  - `COMPLETED` + non-empty output payload + at least one visual artifact.
- Add contract test for `/api/chat` ensuring `suggestions` always present.
