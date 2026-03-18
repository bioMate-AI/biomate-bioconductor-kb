# Detailed UI Test Case Catalog and Paths (2026-03-05 06:42)

## Scope

This catalog documents the strict PM-facing UI test cases used for demo readiness, with:

- test case IDs,
- objective and acceptance criteria,
- exact test file path links,
- run commands,
- output/evidence paths.

All critical tests listed here were executed against:

- Base URL: `http://localhost:5406`
- Health endpoint: `/api/health` returned `status=ok` with Galaxy + AI available.

---

## A. Critical End-to-End User Journey

### TC-UI-001: Complete Workflow Journey (single-user strict path)

- **Test file:** [`frontend/e2e/complete-workflow.e2e.ts`](frontend/e2e/complete-workflow.e2e.ts)
- **Command:**
  - `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --reporter=list --workers=1`
- **Primary UI acceptance criteria:**
  1. Chat input is visible and accepts prompt.
  2. Workflow artifact card appears in chat.
  3. Run button becomes usable (or prerequisite recovery path succeeds and then run is usable).
  4. Execution progress is visible in UI.
  5. Execution reaches terminal completed state.
  6. Output is visible in UI and visualizable.
  7. Download affordance is present and enabled.
- **Latest result:** PASS
- **Evidence paths:**
  - Screenshots folder: [`frontend/e2e/screenshots/complete-workflow`](frontend/e2e/screenshots/complete-workflow)
  - Console logs (timestamped json) saved in that folder by test runtime.
  - Playwright run artifacts: [`frontend/e2e/test-results`](frontend/e2e/test-results)

---

## B. Real Domain Direction Coverage (UI-only)

### TC-UI-010: Direction A (Drug Discovery)

- **Test file:** [`frontend/e2e/survey-directions-real.e2e.ts`](frontend/e2e/survey-directions-real.e2e.ts)
- **Case label:** `A_drug_discovery`
- **Acceptance criteria:**
  - Prompt accepted, workflow surfaced, run action available, terminal cue visible, output action visible.
- **Latest result:** PASS

### TC-UI-011: Direction B (RNA-seq Precision Medicine)

- **Test file:** [`frontend/e2e/survey-directions-real.e2e.ts`](frontend/e2e/survey-directions-real.e2e.ts)
- **Case label:** `B_rnaseq_precision`
- **Acceptance criteria:** same gate as TC-UI-010.
- **Latest result:** PASS

### TC-UI-012: Direction C (Cryo-EM Structures)

- **Test file:** [`frontend/e2e/survey-directions-real.e2e.ts`](frontend/e2e/survey-directions-real.e2e.ts)
- **Case label:** `C_cryo_em`
- **Acceptance criteria:** same gate as TC-UI-010.
- **Latest result:** PASS

### TC-UI-013: Direction D (Single-cell Perturbation)

- **Test file:** [`frontend/e2e/survey-directions-real.e2e.ts`](frontend/e2e/survey-directions-real.e2e.ts)
- **Case label:** `D_single_cell`
- **Acceptance criteria:** same gate as TC-UI-010.
- **Latest result:** PASS

- **Run command used for all 4 above:**
  - `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/survey-directions-real.e2e.ts --project chromium --reporter=list --workers=1`
- **Evidence path:**
  - [`frontend/e2e/test-results`](frontend/e2e/test-results)

---

## C. Run Manager / Multi-Run UX Stability

### TC-UI-020: Run Manager Controls Render

- **Test file:** [`frontend/e2e/run-manager-multi-chat-scope.e2e.ts`](frontend/e2e/run-manager-multi-chat-scope.e2e.ts)
- **Acceptance criteria:**
  - Scope toggle, search, filter, and sort controls visible/usable.
- **Latest result:** PASS

### TC-UI-021: Run Switch Anchoring

- **Test file:** [`frontend/e2e/run-manager-switch-anchoring.e2e.ts`](frontend/e2e/run-manager-switch-anchoring.e2e.ts)
- **Acceptance criteria:**
  - Selecting runs updates focused run context and anchor state in chat.
- **Latest result:** PASS

### TC-UI-022: Scope Race Guard

- **Test file:** [`frontend/e2e/run-manager-scope-race-guard.e2e.ts`](frontend/e2e/run-manager-scope-race-guard.e2e.ts)
- **Acceptance criteria:**
  - Rapid scope changes do not leave stale list state; latest scope wins.
- **Latest result:** PASS

### TC-UI-023: Refresh + Sort Stability

- **Test file:** [`frontend/e2e/run-manager-refresh-sort-stability.e2e.ts`](frontend/e2e/run-manager-refresh-sort-stability.e2e.ts)
- **Acceptance criteria:**
  - Ordering remains semantically stable through refresh/scope/sort changes.
- **Latest result:** PASS

### TC-UI-024: Large Set Visibility Cap

- **Test file:** [`frontend/e2e/run-manager-large-set-visibility-cap.e2e.ts`](frontend/e2e/run-manager-large-set-visibility-cap.e2e.ts)
- **Acceptance criteria:**
  - Bucket counts remain correct with dense data; visible card cap behavior is consistent.
- **Latest result:** PASS

### TC-UI-025: Limit/Offset Stress

- **Test file:** [`frontend/e2e/run-manager-limit-offset-stress.e2e.ts`](frontend/e2e/run-manager-limit-offset-stress.e2e.ts)
- **Acceptance criteria:**
  - Under rapid scope toggles, final UI state is stable and API requests include expected paging params.
- **Latest result:** PASS

- **Run command used for TC-UI-020..025:**
  - `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/run-manager-multi-chat-scope.e2e.ts e2e/run-manager-switch-anchoring.e2e.ts e2e/run-manager-scope-race-guard.e2e.ts e2e/run-manager-refresh-sort-stability.e2e.ts e2e/run-manager-large-set-visibility-cap.e2e.ts e2e/run-manager-limit-offset-stress.e2e.ts --project chromium --reporter=list --workers=1`
- **Evidence path:**
  - [`frontend/e2e/test-results`](frontend/e2e/test-results)

---

## D. Confusion Telemetry UI-Path Checks (supporting UX reliability)

### TC-UI-030: Output Dead-End Signal

- **Test file:** [`frontend/e2e/run-confusion-signals.e2e.ts`](frontend/e2e/run-confusion-signals.e2e.ts)
- **Acceptance criteria:**
  - When run completes without artifact readiness, correct confusion signal is emitted.
- **Latest result:** PASS

### TC-UI-031: Retry Without Progress Signal

- **Test file:** [`frontend/e2e/run-confusion-signals.e2e.ts`](frontend/e2e/run-confusion-signals.e2e.ts)
- **Acceptance criteria:**
  - Repeated retries without progress trigger the expected confusion signal.
- **Latest result:** PASS

### TC-UI-032: Multi-Run Lineage Signal Scope

- **Test file:** [`frontend/e2e/run-confusion-lineage-multi-run.e2e.ts`](frontend/e2e/run-confusion-lineage-multi-run.e2e.ts)
- **Acceptance criteria:**
  - Confusion signal payload contains expected lineage fields (`rootRunId`, `parentRunId`) when switching runs.
- **Latest result:** PASS

- **Run command used:**
  - `BIOMATE_URL=http://localhost:5406 npx playwright test e2e/run-confusion-signals.e2e.ts e2e/run-confusion-lineage-multi-run.e2e.ts --project chromium --reporter=list --workers=1`
- **Evidence path:**
  - [`frontend/e2e/test-results`](frontend/e2e/test-results)

---

## E. Supporting Backend Triage Validation (non-UI, operational)

### TC-OPS-001: Confusion Aggregation Unit Test

- **Test file:** [`frontend/server/telemetry-service.test.ts`](frontend/server/telemetry-service.test.ts)
- **Command:**
  - `npm run test -- server/telemetry-service.test.ts`
- **Acceptance criteria:**
  - Grouping by lineage root/fallback, signal counts, and limits behave as expected.
- **Latest result:** PASS

### TC-OPS-002: Confusion Triage Endpoint Manual Validation

- **Service file:** [`frontend/server/telemetry-service.ts`](frontend/server/telemetry-service.ts)
- **Route file:** [`frontend/server/routes.ts`](frontend/server/routes.ts)
- **Endpoint:** `GET /api/telemetry/confusion-triage`
- **Acceptance criteria:**
  - Returns grouped confusion clusters with expected schema.
- **Latest result:** PASS (manual insertion + query verification)

---

## Consolidated Status (latest strict run window)

- **Total strict UI cases listed above (A+B+C+D):** 14
- **Passed in latest execution cycle:** 14
- **Failed:** 0

This catalog is intended to be used as the PM-facing test inventory and handoff index for demo/day-of verification.
