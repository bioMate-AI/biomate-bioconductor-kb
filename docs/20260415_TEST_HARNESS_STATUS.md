# Test Harness — Current Status
*Date: 2026-04-15 | Branch: integration/next-phase*

---

## Overview

BioMate's test harness is a Playwright E2E suite running against the live server (no mocks). The CLAUDE.md rule prohibits `page.route()` interception, MSW, nock, or stub responses. All tests exercise real backend responses.

---

## Test Suites and Pass Rates

| Suite | File | Tests (from code) | Last Reported Pass |
|-------|------|-------------------|--------------------|
| Full Workflow E2E | `e2e/full-workflow-e2e.e2e.ts` | 8 (inside `test.describe`) | 8/8 (2026-04-15) |
| Workflow Controls | `e2e/workflow-controls-comprehensive.e2e.ts` | **10** (WC-1…WC-10) | 9/9 (2026-04-08) — WC-10 added after last report; is a schema + live run test, not pure meta-test |
| Drug Discovery Pilot | `e2e/pilot-study-e2e.e2e.ts` | 9 (inside `test.describe`) | 9/9 (2026-04-12) |
| Germline / Genomics | `e2e/germline-complete-e2e.e2e.ts` | **7** (GC-1…GC-7) | Prior doc says 8/8 — GC-8 (step-level rerun) was removed from this file; exists only in audit JSON artifacts |
| Cryo-EM | `e2e/cryoem-stepwise-and-output.e2e.ts` | 5 (`test(` at top level) | 5/5 (2026-04-15) |
| UX Suite | various `e2e/ux-*.e2e.ts` | multiple files | 9/9 (2026-04-09) |
| UX-7 Param Autofill | `e2e/ux-param-autofill.e2e.ts` | 3 | 3/3 (2026-04-09) |

**Note — discrepancies vs. prior docs:**
- WC suite has **10 tests** in code (WC-10 added: audit schema validation), but the last session doc reported 9/9. WC-10 has not been confirmed passing.
- Germline code shows **7** `test.describe` blocks but memory doc says 8/8 — count may differ from number of `test()` calls inside each block.
- Pass rates above are from documentation, **not from a live test run**. No test was re-run during this session.

---

## Workflow Controls Suite (WC-1 through WC-9)

Covers the full execution control surface:

| Test | What It Covers |
|------|---------------|
| WC-1 | All viewer buttons: Confirm & Run, Cancel, Rerun, Run Step, Download commands panel |
| WC-2 | Cancel → aborts run → status becomes cancelled/failed |
| WC-3 | Full-run Rerun (`button-restart-workflow-panel`) → `/rerun` POST → same runId in-place |
| WC-4 | Per-step PhaseCard: ≥2 cards, enabled Run Step buttons, step hint text, step-level rerun |
| WC-5 | Output files API 200, download commands API 200, `download_commands` field present |
| WC-6 | `step-file` endpoint reachable; HTML iframe rendered for HTML outputs |
| WC-7 | Two runs with different `max_spots`, compare endpoint 200, `parameterDifferences` present |
| WC-8 | `duration_s`/`started_at`/`completed_at` in `nextflowStatus`; `run-metrics-strip` visible |
| WC-9 | Audit record completeness: timing + billing fields, per-test JSON written to disk |

---

## Audit JSON Output

Every suite run writes `e2e/screenshots/workflow-controls/audit_<ISO>.json`:

```json
{
  "suiteId": "workflow-controls-comprehensive",
  "totalTests": 9,
  "passed": 9,
  "failed": 0,
  "totalWallTimeSec": 588,
  "runs": [
    {
      "testId": "WC-1",
      "runId": "d4eaa0f2-...",
      "finalStatus": "failed",
      "nfDurationS": 26,
      "assertions": [{ "name": "workflow-card-visible", "passed": true }, ...]
    }
  ]
}
```

`llmCostUsd` is null in dev (Lago billing requires staging/prod). Null = "not configured", not zero.

---

## Infrastructure Requirements

The full E2E suite requires:
1. **Frontend server** running: `USE_POLLING=true npx tsx server/index.ts` (port 5000)
2. **Python backend** running (Flask, port 5001)
3. **E2E_TEST_TOKEN** set in environment — bypasses all rate limiters via `X-E2E-Test-Token` header
4. **Real AWS Batch** — long-running tests (GC-2, DD-2) need real Nextflow execution; mocks not allowed

Rate limiter bypass is implemented in `frontend/server/rate-limit.ts`: all limiters check `isE2EBypass(req)` and skip when the token header matches `E2E_TEST_TOKEN`.

---

## Known Gaps and Soft-Assertion Failures

| Item | Severity | Notes |
|------|----------|-------|
| WC-7 `compare-has-parameterDifferences` | P2 | Stored `workflowDefinition` snapshot captured before param update; both runs store max_spots=50 instead of different values. Root cause: snapshot comes from chat message artifact state, not Python backend at execute time. |
| CS-5 stale page after 15-min run | P2 | No auto-refresh on run completion; phase card statuses not updated |
| CS-4 LLM non-determinism | P3 | Topic extraction varies between runs; CryoEM E2E sometimes fails on assertion |
| `llmCostUsd` null in dev | P3 | Requires Lago billing setup (staging/prod only) |

---

## Key Code Locations (verified)

- E2E directory: `frontend/e2e/` (98 test files)
- Rate limiter bypass: `frontend/server/rate-limit.ts` (`isE2EBypass`, `E2E_TEST_TOKEN`)
- Timing persistence: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` lines 2316–2355 (writes `timing.json`), lines 1506–1524 (updates on completion) ✅
- Status route timing fields: `frontend/server/routes.ts` (`metrics.runtime` populated from `nextflowStatus`)
- Run metrics strip: `frontend/client/src/components/nextflow-workflow-viewer.tsx` lines 2023–2035 ✅
- QC audit download: `frontend/server/routes.ts` line 3505 ✅
- Methods report: `frontend/server/routes.ts` line 3530 ✅
- PILOT_ACCOUNT_EMAILS: `frontend/server/routes.ts` lines 3866–3890, 6641–6643 ✅
- Compare endpoint: `frontend/server/storage.ts` (`compareExecutionRuns`)
- Retry loop: `backend/lib/galaxy/ai/galaxy_workflow_generator.py` lines 642–680 ✅ (already implemented — see Auto-Loop doc)

---

## CLAUDE.md Testing Rule

> **NEVER mock API calls in E2E tests.** All E2E tests run against the live server with real backend responses. No `page.route()` interception, no `msw`, no `nock`, no stub responses.

Unit tests may mock only external third-party services (AWS, Stripe) where real calls are impractical.

---

## Priority Actions

1. Fix WC-7 `parameterDifferences` (P2): capture params from Python response at execute time, not from artifact snapshot
2. Fix CS-5: implement auto-refresh / SSE notification on run completion for cryo-EM viewer
3. Add `llmCostUsd` to dev environment audit records (mock Lago or use test billing endpoint)
