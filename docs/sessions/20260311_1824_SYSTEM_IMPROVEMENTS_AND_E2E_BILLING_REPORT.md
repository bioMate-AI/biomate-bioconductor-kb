# BioMate System Improvements + E2E Audit Report
**Date:** 2026-03-11
**Time:** 18:24 UTC
**Author:** Claude Code session

---

## 1. System Improvements Made (2026-03-11 ~18:00 UTC)

### 1a. `classifyFileType()` fix — `frontend/server/routes.ts:7258`

**Problem:** `.pdb`, `.cif`, `.mrc`, `.h5ad`, `.loom` all returned `'binary'`, so
AlphaFold3/docking PDB outputs, cryo-EM density maps, and single-cell `.h5ad`
files were shown as unrendered file downloads instead of activating specialized viewers.

**Fix:** Extended return type and added three new extension groups:
| Extension(s) | New fileType | Viewer activated |
|---|---|---|
| `.pdb`, `.cif`, `.mmcif`, `.ent` | `'structure'` | `StructureViewer` (3Dmol.js) |
| `.mrc`, `.map`, `.ccp4`, `.rec` | `'density_map'` | `DensityMapViewer` (Canvas 2D) |
| `.h5ad`, `.loom` | `'singlecell'` | CellxGene launcher path |

Also updated `isVisualizable()` to return `true` for all new types + CSV/TSV/VCF/BED.

### 1b. Scientific rationale added to LLM generation path — `backend/lib/galaxy/ai/ai_assistant.py:2025`

**Problem:** Only the fast Nextflow search path (`search_nextflow_workflow`) returned
`scientific_rationale`. The LLM generation paths (Galaxy template reuse, medium
confidence adapt, low confidence tool-constrained) had no rationale.

**Fix:** Added rationale build before the final `return` in `generate_workflow_unified()`:
```python
_scientific_rationale = self._build_scientific_rationale(
    _nf_path, _wf_name, workflow_tools=_workflow_tools
)
return {
    ...
    'scientific_rationale': _scientific_rationale,
}
```

### 1c. Scientific rationale propagation fix — `frontend/client/src/components/chat-interface.tsx:339`

**Problem:** `workflowData = data.workflow?.workflow_ga || data.workflow` picked
the `workflow_ga` object, which didn't embed `scientific_rationale` for non-Nextflow
paths. The top-level `data.workflow.scientific_rationale` was silently dropped.

**Fix:** After picking `workflowData`, merge the rationale from the top-level:
```typescript
if (workflowData && data.workflow?.scientific_rationale && !workflowData.scientific_rationale) {
  workflowData = { ...workflowData, scientific_rationale: data.workflow.scientific_rationale };
}
```

---

## 2. E2E Test Run — 2026-03-11 18:08 UTC

**Command:**
```
npx playwright test e2e/drug-dev-viewers-audit.e2e.ts --reporter=line
```

**Duration:** 3 min 42 sec
**Result: 4/4 PASSED**

### Test authentication method
Each test registers a brand-new user account through the real UI:
- Navigates to `http://localhost:5000/register`
- Fills name, email (`e2e_drugdev_<timestamp>_<label>@biomate.test`), password
- Clicks Terms checkbox + Submit
- Gets authenticated as a real user session (JWT issued by `auth-service.ts`)
- No mocks — all AI responses are live Claude API calls

### Test results

| # | Scenario | Auth | AI Response | Key Assertions | Result |
|---|---|---|---|---|---|
| 1 | ADMET Toxicity Screening | Registered via UI | Live Claude | Drug safety content ✓, Workflow card ✓, **Rationale panel ✓** | PASS |
| 2 | Structure Prediction + Docking | Registered via UI | Live Claude | Structure/docking content ✓, Run button ✓, AlphaFold/docking mentioned ✓ | PASS |
| 3 | Non-Compartmental PK Analysis | Registered via UI | Live Claude | PK content ✓, Run button ✓, **Rationale panel ✓** | PASS |
| 4 | CSV Table Viewer (PK Execution) | Registered via UI | Live Claude | Workflow generated ✓, Run initiated ✓ | PASS |

---

## 3. Screenshots — 2026-03-11 13:04–13:08 UTC

**Location:** `frontend/e2e/screenshots/drug-dev/`

| File | Size | Timestamp | Description |
|---|---|---|---|
| `01_admet_initial.png` | 120 KB | 13:04 | ADMET — initial chat screen (new user session) |
| `02_admet_response.png` | 160 KB | 13:05 | ADMET — AI response with drug safety content |
| `03_admet_workflow_card.png` | 160 KB | 13:05 | ADMET — workflow card rendered |
| `04_admet_rationale_expanded.png` | **238 KB** | 13:05 | **ADMET — rationale panel expanded (FIXED)** |
| `05_docking_initial.png` | 120 KB | 13:06 | Docking — initial screen |
| `06_docking_response.png` | 138 KB | 13:06 | Docking — AlphaFold3 + Vina workflow response |
| `07_docking_workflow_card.png` | 138 KB | 13:06 | Docking — workflow card with Run button |
| `09_nca_initial.png` | 120 KB | 13:06 | PK/NCA — initial screen |
| `10_nca_response.png` | 157 KB | 13:07 | PK/NCA — PKNCA workflow generated |
| `11_nca_workflow_card.png` | 157 KB | 13:07 | PK/NCA — workflow card |
| `12_nca_rationale_expanded.png` | **203 KB** | 13:07 | **PK/NCA — rationale panel expanded (FIXED)** |
| `13_csv_initial.png` | 120 KB | 13:07 | CSV viewer — initial screen |
| `14_csv_workflow_generated.png` | 177 KB | 13:08 | CSV viewer — workflow generated |
| `15_csv_running.png` | 195 KB | 13:08 | CSV viewer — workflow running |

Screenshots `04_admet_rationale_expanded.png` and `12_nca_rationale_expanded.png` are the
key proof that the scientific rationale panel fix works end-to-end.

---

## 4. Billing / Cost Data

Costs are recorded per chat session in the `telemetry_events` table
(`postgresql://localhost:5432/biomate_dev`), event type `cost.chat.estimated`,
using heuristic token counting.

### Cost by day (last 14 days)

| Date | Chat Sessions | Avg Cost/Session | Total Cost | Input Tokens | Output Tokens |
|---|---|---|---|---|---|
| 2026-03-11 | 5 | $0.004833 | $0.024165 | 144 | 3,396 |
| 2026-03-10 | 1 | $0.001883 | $0.001883 | 6 | 265 |
| 2026-03-09 | 2 | $0.005690 | $0.011381 | 58 | 1,612 |
| 2026-03-06 | 1 | $0.002295 | $0.002295 | 6 | 326 |
| 2026-03-05 | 50 | $0.004954 | $0.247712 | 1,982 | 34,316 |
| 2026-03-04 | 51 | $0.004080 | $0.208069 | 1,859 | 28,558 |
| **Total** | **110** | — | **$0.495505** | **4,055** | **68,473** |

### Today's cost events (2026-03-11, detail)

| Timestamp UTC | Cost USD | Input Tokens | Output Tokens | Model |
|---|---|---|---|---|
| 02:46:32 | $0.004327 | 24 | 609 | claude-sonnet-4-6 |
| 02:51:24 | $0.003659 | 9 | 525 | claude-sonnet-4-6 |
| 03:36:28 | $0.005211 | 37 | 727 | claude-sonnet-4-6 |
| 03:37:19 | $0.005785 | 37 | 812 | claude-sonnet-4-6 |
| 03:38:12 | $0.005184 | 37 | 723 | claude-sonnet-4-6 |
| **Total today** | **$0.024167** | **144** | **3,396** | — |

> Note: The E2E test run at 18:08 UTC made AI calls through the chat API, but they
> were logged as `query_sent` and `workflow.generated` events rather than
> `cost.chat.estimated` — the cost estimator only fires when the full response
> pipeline completes through the `/api/chat/stream` route with a valid user session.

### Platform activity today (2026-03-11) — all telemetry events

| Event | Count |
|---|---|
| api_request | 4,361 |
| page_viewed | 666 |
| query_sent | 283 |
| workflow.generated | 156 |
| workflow.run_clicked | 102 |
| workflow_failed | 39 |
| workflow_completed | 26 |
| cost.chat.estimated | 5 |
| ai_assistant_error | 5 |

### Error rate SLA (7-day window)

| Metric | Value | Target | Status |
|---|---|---|---|
| 5xx error rate | 0.18% | < 1% | ✓ OK |
| Timeout rate | 0% | < 0.5% | ✓ OK |
| Total requests | 14,702 | — | — |
| AI errors | 5 | — | — |

---

## 5. Where to find artifacts

| Artifact | Path |
|---|---|
| Screenshots (today's run) | `frontend/e2e/screenshots/drug-dev/` |
| Audit JSON | `frontend/e2e/screenshots/drug-dev/audit_2026-03-11T18-08-35-924Z.json` |
| Playwright videos | `frontend/e2e/test-results/` |
| Billing DB | `postgresql://localhost:5432/biomate_dev` → `telemetry_events` |
| Error rate API | `GET http://localhost:5000/api/admin/error-rates` |
