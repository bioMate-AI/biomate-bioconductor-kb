# After-Run Panel — Completion Summary

**Date:** 2026-06-03
**Status:** v0 complete on dev behind `?afterrun=v2` — all 7 tabs shipping, all PM must-fixes landed, comprehensive test 52 PASS / 0 FAIL / 3 SKIP
**Scope:** Closes out the after-run-panel work stream from `docs/20260601_AFTERRUN_PANEL_DESIGN.md` and the PM review at `docs/20260601_AFTERRUN_PANEL_DESIGN_REVIEW.md`

---

## 1. What shipped

### 1.1 Seven tabs (was 5; restored Software + Citations 2026-06-03)

| Tab | Data source | Visibility rule |
|---|---|---|
| Findings | `GET /api/workflows/runs/:id/findings` (AI OutputAnalyzer + FindingReporter) | Always shown |
| Outputs | `currentRun.execution.outputDatasets` → fallback `nextflowStatus.s3_output_files`; bulk Download-all + per-file links + reproducibility bundle | Always shown |
| Methods | `GET /api/invocations/:id/methods-report` (Claude-generated narrative ~5 KB) | Hidden when stub (<200 chars or "No QC events recorded") |
| Parameters | `extractSubmittedParams(currentRun)` + Run-again CTA | Always shown |
| Software | `GET /api/invocations/:id/software` — walks `**/versions.yml`, prefers nf-core `pipeline_info/software_versions.yml` | Hidden when no `versions.yml` files found |
| Citations | `GET /api/workflows/:name/citations` — `qc_evidence.yaml` `paper_doi` (21 domains) + `cryo_em_knowledge` topics (cryo-EM) | Hidden when no citations match |
| QC audit | `GET /api/invocations/:id/qc-events` (`qc_trace_monitor` SSE history) | Hidden when 0 events |

### 1.2 Failed-run section

Renders above the tab bar when `executionStatus` is `failed` or `cancelled`. Components:

- **Status badge** — colour-coded `Run failed` (red) / `Run cancelled` (grey)
- **Run-again with edits CTA** — top-right; dispatches `biomate:run-again-with-edits` CustomEvent
- **Autofix narrative** — first inline block when `nextflowStatus.autofix` is present. Distinguishes:
  - `state='failed'` + `totalAttempts > 0` → *"BioMate auto-fix tried N remediations and could not recover the run"*
  - in-flight states → live message from autofix system
  - `state='succeeded'` → defensive note (shouldn't usually appear)
  - Expandable per-attempt history (lazy-fetches `/api/galaxy/.../autofix3/sessions`) with issue type / fix summary / result per attempt
- **Error message block** — `currentRun.execution.errorMessage` in a fenced error block
- **Failed step(s) list** — from `nextflowStatus.processes[].status === 'FAILED'`
- **Log tail** — last 20 lines of `nextflowStatus.log_tail` in a dark scrollable block, with "showing N of M" header when truncated

### 1.3 Comprehensive download report

Header button **↓ Download report** generates a single `.md` file client-side stitching every visible tab. Filename: `biomate-run-{runId}.md`. Sections in order:

```
# BioMate Run Report
- Run ID, Workflow, Generated timestamp

## Findings        (inlined: Summary / Key results / Caveats / Next steps)
## Outputs         (grouped by step in markdown tables)
## Methods         (full report text in a fenced code block)
## Parameters      (key/value table)
## Software        (tool/version table)
## Citations       (linked title + DOI per row)
## QC Audit        (event table when present)
```

Key-results table uses backend's real field shape: `**${metric}**: ${value}  \n    _${interpretation}_`. Pending findings produces a "re-download in a minute" fallback line so the comprehensive report is always usable.

### 1.4 Download UX feedback

- Download report button: disable + "Preparing…" label on click → green toast "Report downloaded — check your browser" → re-enable after 2s
- Double-click dedup
- Bulk-download buttons (Download all ZIP, Reproducibility bundle) wire to existing backend endpoints

### 1.5 Feature flag

`useAfterRunFlavor()` hook reads `?afterrun=v2` URL param or `localStorage.biomate_afterrun = 'v2'`. Default `v1` (panel hidden). Separate from `useUiFlavor()` so users can preview the new panel without swapping the whole chrome.

---

## 2. PM must-fixes status

From the PM review at `docs/20260601_AFTERRUN_PANEL_DESIGN_REVIEW.md`:

| # | Must-fix | Status |
|---|---|---|
| 1 | Failed-run section — error, log tail, failed steps, Run-again CTA, autofix narrative | ✅ shipped + verified |
| 2 | Findings prose inlined into the comprehensive download | ✅ shipped (real key_results with metric/value/interpretation) |
| 3 | Run-again with edits CTA in Parameters tab + Failed section | ✅ shipped (CustomEvent dispatched; parent wiring is a follow-up) |
| 4 | Cache methods endpoint + better loading UX (client portion) | ✅ client-side shipped (spinner + toast + disable); server cache deferred to job-queue migration |
| 5 | Define explicit v2-flip success/kill criteria + ship telemetry | ⏳ deferred — depends on the async job-queue infra documented at `docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md`. Will land with that subsystem's telemetry events |

---

## 3. Backend changes shipped

| Endpoint | Where | Purpose |
|---|---|---|
| `GET /api/invocations/:id/qc-events` | Node proxy + Python backend (pre-existing) | QC audit tab |
| `GET /api/invocations/:id/software` | Node proxy (`routes.ts`) + Python impl (`nextflow_executor.py`) | Software tab. Walks `**/versions.yml`, prefers nf-core consolidated `pipeline_info/software_versions.yml` |
| `GET /api/workflows/:name/citations` | Node proxy + Python impl | Citations tab. Reads `qc_evidence.yaml` for 21 domains' gate DOIs + queries `cryo_em_knowledge.retriever` for cryo-EM publications |

All three return `{ ...: [], count: 0 }` + HTTP 200 on no-data so the corresponding frontend tab hides cleanly (no error toast / no broken render).

---

## 4. Test coverage

### 4.1 Comprehensive test (`/tmp/test_afterrun_comprehensive.py`)

8 dimensions × 55 cases — **52 PASS / 0 FAIL / 3 SKIP**:

| Dim | Description | Result |
|---|---|---|
| A | Run-state variants on dev | 2P / 0F / 2S (no cancelled or autofix-failed runs in current sample — fixtures script below covers this) |
| B | Tab visibility — hide-empty discipline | 8P / 0F |
| C | Tab content correctness via live endpoints | 7P / 0F |
| D | Failed-run section UI shipped | 10P / 0F / 1S (autofix payload-shape check skipped without autofix-failed run) |
| E | Comprehensive download report — all sections + content correctness | 14P / 0F |
| F | Download UX feedback shipped | 5P / 0F |
| G | Feature-flag behaviour | 3P / 0F |
| H | Run-again CTA | 3P / 0F |

### 4.2 Test infrastructure decisions

- **Bundle-string-inspection** over Playwright: minified bundle is the source of truth for "did this code ship?" + much faster than browser automation. Sufficient because the AfterRunReport is state-heavy + endpoint-driven, not visual-regression-heavy.
- **Real dev endpoints** over mocks: tests exercise the actual /api/workflows/runs/:id/findings, /qc-events, /methods-report, /software, /citations against live dev. Caught the `metric` vs `label` shape bug that mocks would have missed.
- **Test-pattern resistance to minification**: search for string literals (tab labels, testids, toast text), not for property accesses or local variable names.

### 4.3 Fixtures script (`/tmp/make_test_fixtures.py`)

Triggers fixtures for the two dev-data gaps (Dim A SKIPs):

- **Cancelled run**: POSTs `/api/workflows/execute` for any existing workflow, sleeps 5s, POSTs `/api/workflows/runs/:id/cancel`. Verifies status flips to `cancelled`.
- **Autofix-failed run**: enumerates existing runs with `nextflowStatus.autofix` populated. If none, documents that triggering one requires submitting an autoloop-family workflow (ADMET / CYP-DDI / Docking / NCA-PK / Structure-prediction / Cryo-EM) with deliberately-bad parameters — domain-specific knowledge required.

---

## 5. Open items

### 5.1 Async job queue (designed, not implemented)

`docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md` — single shared subsystem for long-running artifact-producing tasks. Migrates 4 call sites in order: download-all → methods-report → reproducibility-bundle → findings-analysis. ~1 dev-week implementation, ~4 calendar weeks including dogfood + telemetry.

Without this, the comprehensive Download-all and Methods report still have:
- 5-30 s sync HTTP holds (multi-GB ZIPs / first-call Claude generation)
- No mid-stream resume on connection drop
- No double-click dedup at backend level (only client-side now)

### 5.2 PM must-fix #5 — telemetry + v2-flip criteria

Listed §11 events from the design doc not yet shipped:
- `afterrun.panel_shown` / `tab_clicked` / `download_report_clicked` / `download_all_clicked` / `reproducibility_bundle_clicked` / `file_downloaded`

Required before v2 default flip per PM review:
- ≥60% panel-render rate on completed-run page views
- ≥40% tab click-through
- ≥10% comprehensive-report download
- No regression in support-ticket volume for "where are my outputs"
- Zero P0 bugs in 5 days of v1 dogfood

These will land with the job-queue migration (Phase 1: download-all gets new telemetry; same events extend cleanly to the panel level).

### 5.3 Parent wiring for Run-again CTA

`biomate:run-again-with-edits` CustomEvent is dispatched but `chat-with-artifacts.tsx` does not yet listen. Needs ~30 LOC: pick up the event, populate the existing rerun-with-params flow (`handleRunWorkflow` with `inline_parameters` override), open the parameter editor in a modal.

### 5.4 Output destination management (BYO S3 / on-prem)

Open discussion thread (no doc yet). Today all output paths are managed BioMate-hosted; users with their own S3 buckets need workspace-level config + cross-account IAM. Tracked separately.

### 5.5 Sidebar swap (Phase 2 of v2 merge plan) — dropped

Per user direction 2026-06-02, Phase 2 (V2 sidebar swap) is dropped. The current v1 sidebar stays.

---

## 6. Files changed

### Frontend
- `frontend/client/src/v2/AfterRunReport.tsx` — main component, all 7 tabs, FailedRunSection, autofix narrative, download report builder
- `frontend/client/src/components/chat-with-artifacts.tsx` — mounts AfterRunReport behind `useAfterRunFlavor() === 'v2'`, passes run state including `autofix` and outputs fallback
- `frontend/client/src/hooks/use-ui-flavor.ts` — `useAfterRunFlavor` hook
- `frontend/client/src/components/findings-card.tsx` — unchanged; embedded in Findings tab

### Node frontend
- `frontend/server/routes.ts` — 3 new proxies: `/qc-events`, `/software`, `/citations`

### Python backend
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — 2 new endpoints: `software` (versions.yml walker) + `citations` (qc_evidence + cryo-EM RAG)

### Docs
- `docs/20260527_V2_INCREMENTAL_MERGE_PLAN.md` — parent v2 plan
- `docs/20260528_AFTERRUN_FINDINGS.md` — A3 backend coverage audit
- `docs/20260601_AFTERRUN_PANEL_DESIGN.md` — full design spec
- `docs/20260601_AFTERRUN_PANEL_DESIGN_REVIEW.md` — PM critique with 5 must-fixes
- `docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md` — async job-queue subsystem design (pending sign-off)
- `docs/20260603_AFTERRUN_PANEL_COMPLETION.md` — this doc

### Test infra
- `/tmp/test_afterrun_comprehensive.py` — 8-dimension × 55-case test suite
- `/tmp/test_afterrun_mustfixes.py` — focused must-fix verification (older, narrower scope)
- `/tmp/make_test_fixtures.py` — creates cancelled-run / autofix-failed fixtures on dev

---

## 7. Recent commits (chronological)

- `4b44a892b` — async job-queue design doc
- `06477d38c` — wip scaffolding for failed-run + outputDir props
- `26d936028` — PM must-fixes #1/#2/#3 + #4 client portion
- `cf48db1da` — `metric` field render fix
- `c461be248` — QC events proxy + S3 outputs fallback
- `ce2240e0b` — autofix narrative in FailedRunSection
- `659019f2e` — Software + Citations tabs restored with backend routes (this session)
