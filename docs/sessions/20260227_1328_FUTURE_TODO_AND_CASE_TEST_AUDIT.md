# Future TODO + Case-Based UI Test Audit (2026-02-27 13:28)

## Future TODO (Kept for later)

- Keep `Download All` workflow-panel hardening as a future item:
  - Goal: remove optionality from regression Step 7 by making workflow-panel `Download All` reliably available/enabled in real runs.
  - Current state: message action-bar `Download outputs` icon path is stable and validated in regression matrix.

## Current Log Review Highlights

- Latest matrix (`frontend/e2e/matrix-runs/feedback-matrix-run-20260227_083951`) confirms:
  - feedback-regression passed with download icon fallback and download outcome prompt submission.
  - deterministic branches passed with all expected feedback payload types.
  - real-user visual evaluation passed.
  - PM user stories passed with iconized response/workflow/download actions visible.
- Existing evidence indicates UX feedback and execution cues are working, but domain diversity was limited (mostly RNA-seq QC prompts).

## New Case-Based UI Performance Tests Added

- New suite: `frontend/e2e/domain-case-performance.e2e.ts`
- Includes real UI domain cases:
  - `DTC-02`: WES QC prompt (tumor-normal BAM context)
  - `DTC-04`: RNA-seq differential expression prompt (DESeq2 context)
  - `DTC-08`: feedback edge path (thumbs-down + reason + submit)
- Metrics captured into test attachment:
  - `pendingCueMs`, `responseMs`, workflow/run visibility, execution-state visibility, domain-signal match.

## New Test Run Result

- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/domain-case-performance.e2e.ts --project chromium`
- Result:
  - `1 passed (3.7m)`
- Captured report:
  - `frontend/e2e/test-results/domain-case-performance.e2-7a2a8-ecific-UI-performance-cases-chromium/domain-case-performance-report.json`
- Key metrics:
  - `DTC-02`: pending cue 12 ms, response 71.4 s
  - `DTC-04`: pending cue 8 ms, response 71.9 s
  - Both domain cases: workflow visible, run visible, execution cue visible, domain signal matched.

