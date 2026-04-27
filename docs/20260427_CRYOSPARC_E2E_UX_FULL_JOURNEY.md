# CryoSPARC Standard SPA — Full UX E2E Journey

**Date:** 2026-04-27  
**Status:** PASSING — 17/19 assertions, finalStatus=completed

---

## What Was Done

Implemented and validated a full end-to-end E2E test (`CE-1`) covering the entire
BioMate CryoSPARC Standard SPA workflow user journey:

1. User registration → home page
2. Natural language query with S3 movies path
3. CryoSPARC workflow card appearance
4. License key entry via credential UX (LicenseGate component)
5. Parameters panel (movies_path auto-populated from query)
6. QC settings (cryoem_spa_purified profile with thresholds)
7. Run button click (proper click, not force)
8. Real-time step monitoring: Phase A→RUNNING, step cards transitioning
9. Terminal state detection: completed
10. Download commands panel and output visualization

---

## Root Causes Fixed

### 1. `cryosparc_license` in required_params blocking Run button

The `cryosparc_license` parameter was appearing in the `required_params` array
with no default and no value, causing `hasUnfilledRequired=true` → Run button
disabled. Fixed by adding to `_NEXTFLOW_INTERNAL_PARAMS` in `ai_assistant.py`.

### 2. `_build_prereq_validation` ignoring `value` field

`movies_path` had `value='s3://...'` but `default=None`, so it was flagged as
"truly missing" → `canRun=false` → `handleExecute()` returned early without
running. Fixed: `truly_missing = [p for p in required_params if not p.get('default') and not p.get('value')]`.

### 3. `executionEngine: 'cryosparc'` hardcoded — poller calling wrong endpoint

The background poller in `routes.ts` always called `/api/cryosparc/status/{id}`
even when the run was launched via Nextflow internally (`executor='nextflow'`).
This endpoint returns 404, leaving the run stuck in 'running' forever.

**Fix (committed e5ea0e3cc):** Poller now checks `effectiveEngine`:
- `'nextflow'`: polls `/api/nextflow/status/{id}`, maps `succeeded→completed`
- `'cryosparc'`: polls `/api/cryosparc/status/{id}` (original behavior)

Also fixed the response to return `effectiveEngine` instead of hardcoded `'cryosparc'`.

### 4. Playwright global timeout overriding per-test timeout

`playwright.config.ts` had `timeout: 600_000` (10 min) which overrode the test's
`test.setTimeout(2_700_000)` (45 min). Fixed by setting global timeout to
`2_700_000`.

### 5. `_return_nextflow_match` missing `uploaded_datasets` parameter

NameError when calling `_return_nextflow_match` without the `uploaded_datasets`
parameter that referenced it. Fixed by adding to method signature.

---

## CE-1 Test Results (run8)

**File:** `frontend/e2e/cryoem-workflows-ux-e2e.e2e.ts`  
**Audit:** `frontend/e2e/screenshots/cryoem-ux/audit_1777277751111.json`

| Assertion | Result |
|-----------|--------|
| Registration and home page loaded | ✅ |
| AI returned response to CryoSPARC SPA query | ✅ |
| CryoSPARC workflow card appeared | ✅ |
| CryoSPARC license key saved via credential UX | ✅ green checkmark |
| Run controls panel visible | ✅ |
| Parameters panel visible | ✅ |
| movies_path populated from S3 query param | ✅ s3://biomate-cryo-data/empiar-10028/Micrographs |
| QC settings section visible | ✅ |
| QC profile selector visible | ✅ "cryoem spa purified" |
| Run button clicked | ✅ |
| Run execution started | ✅ status=running |
| Cold-start banner check | ✅ not shown |
| **Progress bar updated during run** | ✅ fill width changed |
| **Phase cards showed RUNNING status** | ✅ phases: A |
| **Step cards showed status transitions** | ✅ running=1 completed=6 |
| Per-step output files visible | ❌ expected — CryoSPARC runs don't expose step files |
| QC gate panel check | ✅ no gate triggered |
| **Run reached terminal state** | ✅ completed |
| **Download commands panel visible** | ✅ completion banner shown |
| Output attachments/files visible | ✅ output card rendered |
| CSV/table viewer rendered | ❌ expected — no CSV output from CryoSPARC |

**Total: 17/19 passed. finalStatus=completed.**

### Key Screenshots
- `CE1_01_home.png` — home page
- `CE1_02_after_query.png` — AI response with CryoSPARC workflow card
- `CE1_03_workflow_card.png` — workflow card with domain kicker
- `CE1_03b_credentials_saved.png` — green checkmark after license entry
- `CE1_04_params_panel.png` — params with movies_path pre-populated
- `CE1_05_qc_settings.png` — cryoem_spa_purified QC profile
- `CE1_06_after_execute.png` — run initiated
- `CE1_phase_A_running.png` — Phase A RUNNING (real-time update)
- `CE1_08_terminal_completed.png` — run completed
- `CE1_09_output_viz.png` — output visualization panel

---

## Architecture Notes

### CryoSPARC-via-Nextflow Execution Path

```
routes.ts POST /api/workflows/execute
  → GET /api/ai_assistant/license_requirements  (LicenseGate)
  → POST /api/users/credentials                 (store license in vault)
  → POST /api/cryosparc/execute
      → nextflow_executor.py execute_cryosparc()
          → start_instance() (CryoSPARC EC2: 54.159.243.71)
          → _stage_s3_movies_on_cryosparc()
          → execute_nextflow(cryosparc_standard_spa/main.nf)
          → returns {executor: 'nextflow', run_id: '...'}
  → storage.updateExecutionRun(executionEngine='nextflow', nextflowRunId=...)
  → csPollerTimer every 15s:
      GET /api/nextflow/status/{runId}
      succeeded → storage.updateExecutionRun(status='completed')
```

### Status Detection Chain

The run status reaches the UI through two paths (both operational after fix):

1. **Background poller** (`csPollerTimer`): polls Nextflow status endpoint every 15s,
   updates DB + in-memory cache when succeeded→completed.

2. **Status endpoint** (`/api/workflows/runs/:id/status`): checks `executionEngine='nextflow'`
   → fetches Nextflow status → promotes 'succeeded' to 'completed' in DB.

React's `useUnifiedExecution` polls this endpoint every 3s, updating the UI badge.

---

## Known Limitations

- **Step-level output files**: CryoSPARC-via-Nextflow runs don't expose per-step
  file outputs (the Nextflow processes only emit CryoSPARC project IDs, not files).
  The per-step output assertion will remain ❌ until CryoSPARC outputs are parsed
  from the CryoSPARC project on the EC2 instance.

- **Multi-GPU**: The current CryoSPARC EC2 instance (g6.2xlarge) has 1 GPU.
  True multi-GPU testing requires a g6.12xlarge or g6.48xlarge instance.
  `_get_lane_gpu_count()` fix is in place but hasn't been validated on real multi-GPU.

- **QC gate**: For EMPIAR-10028 beta-galactosidase, all 5 CryoSPARC QC thresholds
  pass (high-quality dataset), so the QC gate assertion is always "no gate triggered".

---

## Next Steps

1. Sync fixes to dev EC2: `scripts/sync_to_dev.sh`
2. Validate CryoSPARC E2E on dev environment (http://dev.biomate.ai)
3. CE-2 through CE-5 tests in the cryoem-workflows-ux-e2e.e2e.ts suite
4. Multi-GPU validation on g6.12xlarge instance
5. Step output file parsing from CryoSPARC project API
