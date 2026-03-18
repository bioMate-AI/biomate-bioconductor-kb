# PM User Stories and Comprehensive UI E2E Plan

Created: 2026-02-26 17:29
Owner: Product + QA
Scope: Real BioMate UI validation (no demo/mocked user behavior)

## Product User Stories

### US-001 Message Send Clarity
As a first-time user, I want a clear way to send a message so I can start analysis without guessing.

Acceptance criteria:
- Chat input is visible.
- Send affordance is visible.
- Keyboard helper text for Enter/Shift+Enter is visible.

### US-002 Waiting-State Confidence
As a user waiting for AI generation, I want immediate visible feedback so I know BioMate is working.

Acceptance criteria:
- A pending-response status appears immediately after submit.
- Pending status remains visible during assistant generation.
- Workflow response is eventually rendered with a workflow card.

### US-003 Execution Transparency
As a user executing a workflow, I want clear state and recency signals so I can trust progress.

Acceptance criteria:
- Execution state badge becomes visible (RUNNING/COMPLETED/FAILED/CANCELLED).
- Last-update timestamp is visible in execution area.
- Running hint is shown when logs are not yet available.

### US-004 Result Actionability
As a user after run starts/completes, I want result actions in one place so I can inspect or download output.

Acceptance criteria:
- At least one result-control surface is visible: View/Hide Results, Download All, Report confusion, or output state badge.
- Result controls remain interactive when shown.

## E2E Coverage Mapping

- `frontend/e2e/pm-user-stories-comprehensive.e2e.ts`
  - `US-001`: send affordance + keyboard helper
  - `US-002`: pending-response feedback + workflow card render
  - `US-003`: run execution state + last-update recency
  - `US-004`: result control/action surface visibility

- `frontend/e2e/feedback-regression.e2e.ts`
  - Feedback submission paths on real UI (inline thumbs, post-run survey)

- `frontend/e2e/feedback-branches-deterministic.e2e.ts`
  - Deterministic validation of confusion and download feedback payload branches

- `frontend/e2e/real-user-visual-evaluation.e2e.ts`
  - Human-observable end-to-end visual checkpoints + report artifact

## Comprehensive Local Run Command

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix
```

Matrix now includes:
- `feedback-regression.e2e.ts`
- `feedback-branches-deterministic.e2e.ts`
- `real-user-visual-evaluation.e2e.ts`
- `pm-user-stories-comprehensive.e2e.ts`

## Exit Criteria for "Real User Ready" (Current)

- All four suites pass on live UI endpoint.
- No blocking UX gap in send/wait/run/result visibility.
- Failure traces and rerun commands documented in `frontend/e2e/README_COMPREHENSIVE_TESTS.md`.
