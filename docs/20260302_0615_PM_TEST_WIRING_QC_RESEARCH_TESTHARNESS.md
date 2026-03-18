# PM Test Wiring — QC, Research, Test Harness

**Date:** 2026-03-02  
**Owner:** Product + Engineering  
**Goal:** Establish release-friendly, repeatable validation gates for QC behavior, research routing quality, and model test harness wiring.

---

## Why This Wiring Exists

The repo has both deterministic tests and live-system tests. Without a clear wire, release readiness is ambiguous and test runs are inconsistent across sessions.

This wiring defines:
- a **quick gate** for day-to-day PR confidence,
- a **full gate** for pre-release validation,
- explicit **external dependency** requirements for live suites.

---

## Command Entry Points

From `frontend/`:

- Quick PM wire:
  - `npm run pm:wire:quick`
- Full PM wire:
  - `npm run pm:wire:full`
- Release strict wire:
  - `npm run pm:wire:release`
- Dependency preflight:
  - `npm run pm:wire:deps`

Script location:
- `frontend/scripts/run-pm-test-wire.sh`
- `backend/scripts/run_qc_regression_in_galaxy_backend.sh` (docker-backed backend QC helper)
- Report output:
  - `frontend/test-results/pm-wire-report.txt`
- CI workflow:
  - `.github/workflows/pm-test-wire.yml` (quick gate on PR/push, manual quick/full/release dispatch)

---

## Gate Matrix

| Gate | Scope | Command | Blocking |
|---|---|---|---|
| Type Safety | Frontend/server TS contracts | `npm run check` | Yes |
| QC Runtime | Polling/SSE/QC-adjacent execution state | `npm run test -- server/workflow-execution.test.ts client/src/hooks/useWorkflowExecution.test.ts shared/schema.test.ts` | Yes |
| Research Routing (offline) | Intent-to-action mapping | `npx tsx server/test-information-needs.ts` | Yes |
| Harness Wiring (live model) | LLM model comparison harness | `PM_WIRE_RUN_HARNESS=1 npx tsx server/model-test-harness.ts` | Conditional |
| Research E2E (live stack) | Real `/api/chat` flow + DB persistence checks | `npx tsx server/test-e2e-flexible-intents.ts` | Pre-release |
| Backend QC Regression | Python QC domain/edge behavior | `PM_WIRE_BACKEND_GATE_MODE=docker bash backend/scripts/run_qc_regression_in_galaxy_backend.sh` (invoked by PM wire in `full`) | Pre-release |

---

## Environment Expectations

### Quick wire (default)
- No external model key required
- No live backend stack required

### Full wire
- For harness:
  - `ANTHROPIC_API_KEY` required
  - `PM_WIRE_RUN_HARNESS=1`
- For research E2E:
  - `TEST_BASE_URL` set (default is not assumed reliable for CI)
  - frontend/backend/DB running
- For backend QC regression:
  - Preferred: Docker available (`PM_WIRE_BACKEND_GATE_MODE=docker`, default is `auto`)
  - Local fallback mode: `pytest` plus Python modules such as `pulsar` and `sqlalchemy`

---

## PM Release Policy

- **PR policy (minimum):** quick wire must pass.
- **Release candidate policy:** full wire must pass (or explicitly documented approved skips).
- **Release strict policy:** run `npm run pm:wire:release`; skipped gates fail the run.
- **Skip policy:** any skipped full-gate item must include:
  - reason,
  - owner,
  - follow-up date,
  - risk statement.

---

## Notes

- The harness and live E2E suites are intentionally not hard-blocking in quick mode because they depend on external services/secrets.
- This wiring is designed to minimize false negatives while preserving deterministic quality gates for frequent iteration.
