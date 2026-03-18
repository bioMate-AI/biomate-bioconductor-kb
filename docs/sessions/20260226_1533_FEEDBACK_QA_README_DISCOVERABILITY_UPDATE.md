# 2026-02-26 15:33 Progress: Feedback QA README Discoverability Update

## Scope completed

Added documentation so the team can quickly find and run the new UX feedback regression pipeline locally and understand the linked CI workflow.

## Documentation updated

- File: `frontend/e2e/README_COMPREHENSIVE_TESTS.md`

## New section added

### `Run UX Feedback Regression Matrix`

Includes command:
- `BIOMATE_URL=http://localhost:5000 npm run e2e:feedback:matrix`

Documents included suites:
- `feedback-regression.e2e.ts`
- `feedback-branches-deterministic.e2e.ts`

Links CI context:
- Workflow name: `UX Feedback Regression CI`
- Workflow file: `.github/workflows/feedback-e2e-matrix.yml`
- Trigger model: path-filtered PR/push + manual dispatch

## Outcome

The new feedback QA pipeline is now discoverable in existing E2E docs, reducing onboarding friction and making local/CI usage explicit.
