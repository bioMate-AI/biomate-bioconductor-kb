# Evidence-First UI E2E Test Plan (Revised)

Created: 2026-02-26 23:33
Goal: Verify real BioMate quality with complete, inspectable evidence (not only PASS/FAIL)

## 1) Required Evidence Per Run

Every matrix run must produce:
- Run metadata (`timestamp`, `branch`, `commit`, `durations`, guard hashes)
- Full matrix console log (ordered execution process)
- Per-test console log (step-by-step chat/action narrative)
- Per-test Playwright JSON report (test-level timing, stdout/stderr, attachments)
- Per-test copied attachments manifest (`trace`, `video`, `screenshots`, custom JSON evidence)

## 2) Key Quality Dimensions and Checks

### A. Chat Interaction Details
- Prompt text sent is captured.
- Waiting behavior captured (pending/typing cue visible).
- Assistant response event timing captured.
- Evidence source: per-test console + JSON report stdout.

### B. Workflow Details
- Workflow card appears and is identifiable.
- Workflow execution actions visible (`Run`, result controls).
- Execution state transitions observed (`RUNNING/COMPLETED/FAILED/CANCELLED`).
- Evidence source: JSON report + screenshot/video/trace.

### C. Parameters
- Parameter panel visible and reachable in workflow UI.
- If parameter edits are performed, changed values are logged.
- Evidence source: PM suite + trace replay.

### D. Execution Process
- Ordered execution steps with durations for each suite.
- Terminal status observability and recency cue checks.
- Evidence source: matrix metadata + per-test console logs.

### E. Output and Reports
- Output state surface visible (`output-result-state-badge` or equivalent result controls).
- Download/visualization pathways validated or explicitly skipped with reason.
- Evidence source: feedback regression logs + visual evaluation report JSON.

### F. Feedback and UX
- Inline feedback submission path validated.
- Post-run survey validated.
- Confusion/download branch logic validated in deterministic suite.
- Evidence source: feedback suites + per-test reports.

## 3) Suite-to-Requirement Mapping

- `feedback-regression.e2e.ts`
  - Chat prompt, inline feedback, run workflow, post-run survey, optional download outcome path.
- `feedback-branches-deterministic.e2e.ts`
  - Deterministic confusion/download branches and payload behavior.
- `real-user-visual-evaluation.e2e.ts`
  - Human-observable flow with screenshot/video/trace + attached JSON evaluation report.
- `pm-user-stories-comprehensive.e2e.ts`
  - PM acceptance coverage: send clarity, waiting-state confidence, execution transparency/actionability.

## 4) Run Procedure

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL=http://localhost:5310 bash scripts/run-feedback-e2e-matrix.sh
```

Guardrails active:
- Single-run lock (blocks concurrent matrix jobs)
- Required-file preflight
- Critical-file drift detection during run
- Persistent artifact capture outside Playwright report overwrite path

## 5) Evidence Review Procedure

1. Open run metadata:
   - `frontend/e2e/matrix-runs/feedback-matrix-run-<timestamp>.txt`
2. Open matrix timeline:
   - `.../matrix-console.log`
3. For each suite:
   - `.../<suite>.console.log`
   - `.../<suite>.results.json`
   - `.../<suite>.artifacts/attachments-manifest.json`
4. For deep UI replay:
   - open copied `trace.zip` via `npx playwright show-trace <trace.zip>`
5. For visual confirmation:
   - inspect copied `video.webm` and `test-finished-1.png`

## 6) Exit Criteria

A run is accepted only if:
- All suites pass.
- All required artifact files exist.
- No guard violation was triggered.
- No critical check was skipped without explicit documented reason.
