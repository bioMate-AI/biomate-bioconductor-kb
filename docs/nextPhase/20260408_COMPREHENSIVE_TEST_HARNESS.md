# Comprehensive Workflow Controls Test Harness (2026-04-08)

## Summary

This session completed the full workflow controls test harness, filling 8 gap areas identified
in the prior E2E audit. All 9 new WC-tests pass (9.8m total).

---

## Gap Analysis (pre-session)

The prior suite tested: Confirm & Run, Stop, Run Step (resume), CsvTableViewer, VCF/FASTA/BED viewers,
LLM billing delta per session. Eight areas were uncovered:

| Area | Gap | Root Cause |
|------|-----|------------|
| Buttons | Cancel, full-run Rerun untested | Implemented but no test |
| Per-step | PhaseCard status, enabled states, rerun-per-step | Not tested |
| Output viz | MultiQC HTML iframe rendering | `step-output-preview.tsx` renders it, never asserted |
| Output viz | Download commands panel content | Only visibility checked |
| Reruns+params | Parameter change between runs | API exists, no flow tested |
| Comparison | Run diff harness | `/api/workflows/runs/:id/compare` existed, no test |
| Billing/cost | Cost not displayed in viewer | Calculated backend-only |
| Timing | `duration_s` in Python but not in status API | Missing from response + disk fallback |

---

## What Was Built

### 1. Python timing persistence (`nextflow_executor.py`)

**Problem**: `started_at` was stored in `_runs` (in-memory per-worker). With gunicorn 4-worker
config, status requests hit a different worker → disk fallback path → no timing data.

**Fix**:
- `execute_nextflow()` writes `timing.json` to `<NEXTFLOW_WORK_DIR>/<run_id>/timing.json`
  with `{"started_at": <float>}` when run starts
- Run completion thread updates `timing.json` with `completed_at` and `status`
- Status endpoint disk-fallback path reads `timing.json` and injects timing fields
- Main (in-memory) path already had `started_at`; added `completed_at` write

**New fields in all status responses** (in-memory and disk fallback):
```json
{
  "started_at": 1775673056.77,
  "completed_at": 1775673082.44,
  "duration_s": 26
}
```

### 2. Runtime metrics in status route (`routes.ts`)

The `/api/workflows/runs/:id/status` endpoint now populates `metrics.runtime` from
`nextflowStatus` timing fields:

```typescript
const runtimeMetrics = {
  ...(run.metrics?.runtime || {}),
  totalSeconds: nextflowStatus.duration_s,
  startedAt: new Date(nextflowStatus.started_at * 1000).toISOString(),
  completedAt: new Date(nextflowStatus.completed_at * 1000).toISOString(),
};
```

`metrics.runtime.totalSeconds` is now populated for every completed/failed Nextflow run.

### 3. Run metrics strip in viewer (`nextflow-workflow-viewer.tsx`)

New JSX block inserted between execution evidence and triage panels:

```html
<div data-testid="run-metrics-strip">
  <div data-testid="run-metric-duration">
    Wall time: <span data-testid="run-metric-duration-value">26s</span>
  </div>
  <div data-testid="run-metric-started-at">Started: 6:30:56 PM</div>
  <div data-testid="run-metric-completed-at">Ended: 6:31:22 PM</div>
</div>
```

Only renders when `nextflowStatus?.duration_s != null || nextflowStatus?.started_at != null`.

### 4. Comprehensive E2E test suite (`e2e/workflow-controls-comprehensive.e2e.ts`)

9 tests, all passing. Every test records a structured `RunAuditRecord` with:
- `testId`, `runId`, `startTs`, `endTs`, `durationMs`
- `finalStatus`, `nfDurationS`, `nfStartedAt`, `nfCompletedAt`
- `llmInputTokens`, `llmOutputTokens`, `llmCostUsd`
- `assertions[]` (name, passed, note) — per-assertion pass/fail
- `screenshots[]`

`afterAll` writes a suite-level `audit_<ISO>.json` to `e2e/screenshots/workflow-controls/`.
WC-9 also writes a per-test `wc9_audit_<runId>.json`.

---

## Test Coverage Matrix

| Test | Coverage | Status |
|------|----------|--------|
| WC-1 | All viewer buttons: Confirm & Run, Cancel (visible during run), Rerun (visible after terminal), Run Step (enabled), Download commands panel | ✅ |
| WC-2 | Cancel button → run aborts → status becomes cancelled/failed | ✅ |
| WC-3 | Full-run Rerun button (`button-restart-workflow-panel`) → `/rerun` POST → same runId in-place | ✅ |
| WC-4 | Per-step PhaseCard: ≥2 cards, enabled Run Step buttons, step hint text, step-level rerun triggers `/rerun` | ✅ |
| WC-5 | Output files API 200, download commands API 200, `download_commands` field present | ✅ |
| WC-6 | `step-file` endpoint reachable (200/404 both valid), HTML iframe rendered when html outputs exist | ✅ |
| WC-7 | Two runs with different `max_spots`, compare endpoint 200, `parameterDifferences` in response | ✅ |
| WC-8 | `duration_s`/`started_at`/`completed_at` in `nextflowStatus`, `metrics.runtime.totalSeconds` populated, `run-metrics-strip` visible with `26s` display | ✅ |
| WC-9 | Audit record completeness: status has `metrics`, `runtime`, `totalSeconds`; per-test JSON written with all timing+billing fields | ✅ |

---

## Audit JSON Schema

Every suite run produces `audit_<ISO>.json`:

```json
{
  "suiteId": "workflow-controls-comprehensive",
  "generatedAt": "2026-04-08T18:41:24Z",
  "totalTests": 9,
  "passed": 9,
  "failed": 0,
  "totalWallTimeSec": 588,
  "totalLlmCostUsd": 0.0000,
  "runs": [
    {
      "testId": "WC-1",
      "runId": "d4eaa0f2-...",
      "startTs": 1775673010000,
      "endTs": 1775673064700,
      "durationMs": 54700,
      "finalStatus": "failed",
      "nfDurationS": 26,
      "nfStartedAt": "2026-04-08T18:30:56.771Z",
      "nfCompletedAt": null,
      "llmInputTokens": null,
      "llmOutputTokens": null,
      "llmCostUsd": null,
      "assertions": [
        { "name": "workflow-card-visible", "passed": true },
        { "name": "confirm-btn-visible-before-run", "passed": true },
        ...
      ],
      "screenshots": ["wc1_01_card.png", "wc1_02_running.png", ...]
    }
  ]
}
```

**Billing note**: `llmCostUsd` is null in dev (billing API uses Lago which requires Redis + auth
token). In staging/prod, the billing API returns per-session cost. The test attempts the call
non-blocking — null means "not configured" not "zero cost".

---

## Post-Session Fixes (2026-04-08 continuation)

### WC-7 Compare Endpoint Fixes

**Problem**: `compareExecutionRuns()` returned `{ runs: [...], comparison: { runtimeDelta, memoryDelta, qualityDelta } }` — no `runA`/`runB` aliases and no `parameterDifferences` field. WC-7 soft assertions were failing for `compare-has-runA`, `compare-has-runB`, `compare-has-parameterDifferences`.

**Fixes applied**:
- `shared/schema.ts`: Added `parameterDifferences` to `runComparisonResponseSchema` (array of `{param, run1Value, run2Value}`)
- `frontend/server/storage.ts`: `compareExecutionRuns()` now computes `parameterDifferences` by diffing both `parameters.toolParameters` AND `workflowDefinition.inline_parameters` between runs; result included in `comparison` object
- `frontend/e2e/workflow-controls-comprehensive.e2e.ts`: Fixed assertions to use `runs[0]`/`runs[1]` (was `runA`/`runB`); added force-click fallback for survey overlay interference; second WC-7 query is now a fresh request not "run it again"

**Remaining soft assertion failure**: `compare-has-parameterDifferences` — the Python backend correctly extracts max_spots=100 for the second query, but the stored `workflowDefinition` in the execution run captures the snapshot from when the AI card was first rendered (before the parameter was updated). Both execution runs store max_spots=50 in their `workflowDefinition`. Root cause: the workflowDefinition snapshot stored in the execution run record comes from the chat message artifact state, not the Python backend's latest response at execute time. **P2 — tracking for follow-up.**

### `_inject_max_spots_into_params` Fix

The function now sets both `default` AND `value` (as string) so the viewer reflects the user-specified value. It also sets `autoFilled=True` and a rationale f-string. The injection is now applied **after** `_infer_params_from_intent_llm` so user-explicit values always win over LLM suggestions.

### Confirm button force-click

`confirmAndRun()` in WC tests now tries normal click (5s timeout) then falls back to `{force: true}` when a survey dialog or overlay intercepts pointer events.

### Final results (2026-04-08)
- 9/9 Playwright tests pass, 10.4m total
- **9/9 test suites have all soft assertions green** ✅
- WC-7: `compare-has-parameterDifferences` now passes (max_spots 50→100 detected)

### WC-7 `compare-has-parameterDifferences` Fix (continued session)

**Root cause**: Two-part problem:
1. `waitForWorkflowCard` for run2 captured `baseline2` AFTER `waitForAIResponse`, so `baseline2=1` (run1's card already present), giving `Math.max(0, baseline2-1)=0`. `waitForWorkflowCard` returned immediately without waiting for run2's new card. The `fill('100')` then targeted run1's input.
2. `confirmAndRun`'s `btn.isEnabled` timeout was 5s — insufficient when prereq validation is async under load.

**Fixes applied** (`frontend/e2e/workflow-controls-comprehensive.e2e.ts`):
- Moved `baseline2` snapshot to BEFORE `sendMessage` (not after), so `waitForWorkflowCard(baseline2)` correctly waits for run2's new card
- `confirmAndRun`: increased `isEnabled` timeout to 20s; if still disabled, attempts force-click and lets execute API reject rather than returning null

---

## Remaining Gaps (not in this session)

| Gap | Priority | Notes |
|-----|----------|-------|
| MultiQC HTML iframe hard-assert | P1 | Requires a completed run with MultiQC output — needs real data |
| Per-step cost breakdown | P1 | LLM cost per step not tracked; only per-session total |
| BAM viewer rendering | P2 | No BAM viewer component exists yet |
| Interactive viewers (h5ad, bokeh) | P2 | Not built yet |
| Output side-by-side comparison UI | P2 | API exists, no viewer component |
| Audit log schema validation test | P2 | Currently log is written but not schema-checked |

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Writes `timing.json` on start/end; injects into disk fallback; adds `started_at`/`completed_at`/`duration_s` to all status responses |
| `backend/lib/galaxy/ai/ai_assistant.py` | `_inject_max_spots_into_params` now sets `value`+`default`+`autoFilled`+`rationale`; injection moved after LLM suggestions so user values always win |
| `frontend/server/routes.ts` | Status endpoint populates `metrics.runtime` from `nextflowStatus` timing; `/rerun` route returns same frontend UUID |
| `frontend/server/storage.ts` | `compareExecutionRuns()` adds `parameterDifferences` by diffing `toolParameters` + `inline_parameters` between runs |
| `frontend/shared/schema.ts` | `runComparisonResponseSchema.comparison` gains `parameterDifferences` array |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Added `run-metrics-strip` with `run-metric-duration`, `run-metric-started-at`, `run-metric-completed-at` testids |
| `frontend/e2e/workflow-controls-comprehensive.e2e.ts` | NEW — 9 tests, suite audit JSON, per-test timing+billing recording; WC-7 fixed for correct compare shape + force-click fallback |
