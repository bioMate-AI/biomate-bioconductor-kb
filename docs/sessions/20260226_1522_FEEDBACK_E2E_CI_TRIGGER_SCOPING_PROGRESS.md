# 2026-02-26 15:22 Progress: Feedback E2E CI Trigger Scoping

## Scope completed

Updated the feedback E2E CI workflow to run automatically on relevant code changes while avoiding unrelated trigger noise.

## Workflow updated

- File: `.github/workflows/feedback-e2e-matrix.yml`

## Trigger changes

### Added `pull_request` trigger with path filters
Runs feedback matrix only when files affecting feedback UX, telemetry, E2E, or CI runner wiring are modified.

### Added `push` trigger (main/master) with same path filters
Ensures merged changes still run the targeted feedback matrix check on primary branches.

### Kept `workflow_dispatch`
Manual trigger remains available for ad hoc verification.

## Path filter coverage includes

- Feedback UI components under `frontend/client/src/components/feedback/**`
- Related chat/output components and dashboard pages
- Feedback/telemetry libs and backend routes/services
- Shared schema and Playwright config
- Matrix runner script and package scripts
- The workflow file itself

## Outcome

Feedback CI checks now run automatically where they provide value, with reduced noise/cost for unrelated repository changes.
