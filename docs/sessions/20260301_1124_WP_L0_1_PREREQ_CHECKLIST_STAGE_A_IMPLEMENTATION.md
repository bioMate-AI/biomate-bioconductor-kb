# WP-L0-1 Prerequisite Checklist Stage-A Implementation (2026-03-01 11:24)

## Objective
- Implement prerequisite checklist surfacing in the existing workflow parameter panel.
- Respect DB-derived parameter semantics (`optional`, `defaultValue`) without inventing domain rules.
- Use Stage-A rollout: **surface checklist now** while preserving existing execution gating behavior.

## User Constraint Applied
- Parameters can be:
  - required and missing (must),
  - optional and unset,
  - required but defaulted.
- Classification must come from tool/db-backed metadata path, not assumptions.

## Changes Implemented

### 1) Added DB-aware checklist normalizer
- File: `frontend/client/src/lib/prereq-normalizer.ts`
- Uses:
  - `prerequisitesValidation.analysis.missingInputs`
  - `prerequisitesValidation.analysis.missingParameters`
  - `prerequisitesValidation.requirements.parameters` (`optional`, `defaultValue`)
- Classification:
  - required + no default + missing -> `missing` (hard in data model)
  - required + default available + missing -> `warning`
  - optional or suggested parameter -> `warning`
  - satisfied/defaulted -> `ok`

### 2) Checklist wired into existing workflow panel
- File: `frontend/client/src/components/chat-message.tsx`
  - builds `prereqChecklist` from message metadata and passes to viewer.
- File: `frontend/client/src/components/nextflow-workflow-viewer.tsx`
  - renders `Execution checklist` block in the parameter column.
  - added test ids:
    - `workflow-prereq-checklist`
    - `workflow-prereq-item-<id>`
  - added run-button test id:
    - `button-run-workflow-panel`

### 3) Stage-A rollout correction (important)
- Initial attempt to enforce checklist blocking immediately caused broad regressions in strict release suites.
- Updated to Stage-A behavior:
  - checklist is visible and informative,
  - existing run-gating policy remains authoritative,
  - no new hard block introduced yet from checklist-only signals.

## New E2E Coverage
- Added: `frontend/e2e/ux-prereq-checklist.e2e.ts`
- Cases:
  1. required missing input is surfaced in checklist
  2. required missing parameter with default -> warning + run allowed
  3. optional missing parameter -> warning + run allowed

## Validation

### Targeted checklist suite
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/ux-prereq-checklist.e2e.ts --project chromium --retries=0`
- Result:
  - **PASS** (3 passed)

### Strict release feedback gate
- Command:
  - `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`
- Result:
  - **SUCCESS**
  - `feedback-real-ui-strict.e2e.ts` PASS (flaky retry due Playwright artifact ENOENT race)
  - `pm-user-stories-comprehensive.e2e.ts` PASS
- Matrix artifact:
  - `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_112040.txt`

## Known Residual
- Existing known flaky artifact race remains (`ENOENT` in Playwright trace artifact path on first attempt) but auto-retry recovered.
- This does not change product behavior; it is a test infrastructure stability item already tracked.

## Next Step
- Proceed to WP-L0-2 (offline/disconnection UX), then WP-L0-3 (async/timeout standardization), while keeping release-gate matrix green after each step.
