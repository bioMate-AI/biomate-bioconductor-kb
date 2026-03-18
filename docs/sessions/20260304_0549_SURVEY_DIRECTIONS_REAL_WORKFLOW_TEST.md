# Survey Directions Real Workflow Test

Date: 2026-03-04
Scope: Execute real UI workflow runs for the four strategic directions from `business/BioMate_Research_Direction_Survey_20260303.md`

## Test Setup

- Server: `frontend` test-mode server on `http://localhost:5322`
- Command:
  - `BIOMATE_URL=http://localhost:5322 bash scripts/run-e2e-isolated.sh e2e/survey-directions-real.e2e.ts --project chromium --trace off --retries=0`
- Test file: `frontend/e2e/survey-directions-real.e2e.ts`
- Result artifact root: `frontend/e2e/test-results-isolated/20260303_233727`
- Aggregated Playwright report: `frontend/e2e/reports/results.json`

## Direction Coverage (Real UI, Non-mocked)

All four directions passed with live UI interaction:

1. Direction A - Drug Discovery
2. Direction B - RNA-seq Precision Medicine
3. Direction C - Cryo-EM Structures
4. Direction D - Single-cell Perturbation

## Validation Gates Used Per Direction

- Prompt submitted through chat UI.
- Workflow card rendered.
- Run action found and enabled (with prerequisite recovery prompt if needed).
- Workflow execution started from UI.
- Terminal cue observed (`COMPLETED`/`FAILED`/`CANCELLED` or results control visible).
- Output/results surface visible (download/results controls).

## Runtime Summary

- A (Drug Discovery): passed, ~128s
- B (RNA-seq Precision): passed, ~151s
- C (Cryo-EM): passed, ~170s
- D (Single-cell): passed, ~160s
- Total: ~10.2 minutes

## Notes

- This run validates end-to-end UI behavior across all survey directions, including execution actions and output/result surfaces.
- The suite intentionally tests real server behavior and does not intercept `/api/chat` or workflow execution APIs.
