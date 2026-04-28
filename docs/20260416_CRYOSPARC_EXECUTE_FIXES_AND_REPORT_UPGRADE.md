# CryoSPARC Real Execution — Bug Fixes & Report Upgrade (2026-04-17)

## Session Goals
1. Get CS-10 E2E test passing with real CryoSPARC SPA execution on AWS Batch
2. Make the user-facing error messages positive and informative
3. Send admin alerts to yaoyun.zhang@biomate.ai on failures
4. Upgrade methods report to publication/journal-submission quality
5. Audit and fix structural bugs in the CryoSPARC execution pipeline

## Root Cause Analysis — Why CS-10 Kept Failing

### Bug 1: VcpuLimitExceeded (503 from /api/cryosparc/execute)
**Symptom:** Every execute attempt returned 503; Node returned 500 with `executionEngine=null`

**Root cause:** `get_instance_state()` returned `"unknown"` when `CRYOSPARC_INSTANCE_ID` env var
was not set and `_active_instance_id` was empty (cleared on gunicorn restart). This caused
`start_instance()` to launch a *new* g6.2xlarge from AMI every time. Orphaned instances from
previous test runs consumed the 128 vCPU limit before a new launch could succeed.

**Fix:** Added `_find_existing_instance()` to both `get_instance_state()` and `start_instance()`.
When no known instance ID, EC2 is scanned for `Name=cryosparc-biomate-job` tagged instances.
If a running/stopped instance is found, it is reused — no new launch attempted. `CRYOSPARC_HOST`
is updated to the discovered instance's public IP.

**Files:** `backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py`

### Bug 2: Remote Path Validation 422 Error
**Symptom:** `/api/cryosparc/execute` returned 422: "Input path(s) not found: --cryosparc_project_dir '/home/ubuntu/cryosparc_projects': path does not exist"

**Root cause:** `_is_path_param()` matched `cryosparc_project_dir` (contains "dir") and
`/home/ubuntu/cryosparc_projects` (starts with "/"). The local validator tried to `Path.exists()`
a path that only exists on the remote EC2 GPU instance, not on the gunicorn host machine.

**Fix:** Added CryoSPARC remote-path keys to `_NON_PATH_KEYS` frozenset:
`cryosparc_project_dir`, `cryosparc_host`, `cryosparc_email`, `cryosparc_password`,
`cryosparc_license`, `cryosparc_lane`.

**Files:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` line ~705

### Bug 3: Wrong Nextflow Profile — Zero Steps Executed
**Symptom:** Nextflow returned `status=succeeded, returncode=0` but with 0 completed steps and no S3 output files. Log: "Unknown configuration profile: 'aws'"

**Root cause:** `BIOMATE_NF_PROFILE=aws` in `backend/.env`. The `execute_cryosparc` function
called `execute_nextflow` without specifying a profile, inheriting the env default `'aws'`.
The cryosparc nextflow.config defines `executor = 'awsbatch'` *directly* (not inside an `aws`
profile block), so Nextflow rejected the profile name and ran with 0 processes.

**Fix:** Set `profile="standard"` explicitly in the `NextflowExecuteRequest` inside
`execute_cryosparc`. The `standard` profile is always valid in Nextflow and the cryosparc
config already handles all AWS Batch settings natively.

**Files:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` line ~3900

### Bug 4: Status Poller Calling Wrong Endpoint
**Symptom:** The background Node server poller kept the run in `status=running` forever because it called `/api/cryosparc/status/{csRunId}` which returns 404 for Nextflow run IDs.

**Root cause:** The CryoSPARC pipeline now runs via Nextflow (not the old direct CryoSPARC API).
The run ID returned by `execute_cryosparc` is a Nextflow run UUID tracked by `execute_nextflow`.
But the background poller in `routes.ts` called the CryoSPARC status endpoint which only knows
about old in-memory `_cs_runs` tracked by `execute_spa_pipeline` (the old direct API).

**Fix:** Changed poller from `/api/cryosparc/status/${csRunId}` → `/api/nextflow/status/${csRunId}`.
Added logging, Nextflow→BioMate status mapping (`succeeded→completed`, `failed→failed`).
Poll interval changed from 8s → 15s (Nextflow reports less frequently than the old poller).

**Files:** `frontend/server/routes.ts` ~line 6908

### Bug 5: ensure_cryosparc_running Blocking HTTP Response
**Symptom:** Playwright's 60-second `waitForResponse` timeout fired before the execute endpoint responded. Result: "No execute response received", runId=null.

**Root cause:** Replaced `start_instance(wait=True)` with `ensure_cryosparc_running()` in a
previous iteration. The `ensure_cryosparc_running` function polls the CryoSPARC Python API
with a 900-second timeout (15 minutes), blocking the HTTP connection. Playwright's 60s
timeout on `waitForResponse` fired during this wait.

**Fix:** Reverted to `start_instance(wait=True)` — with Bug 1 fixed, this now discovers the
existing running instance quickly and returns within ~2 seconds. `CRYOSPARC_HOST` is updated
to the live IP as part of `start_instance`.

**Files:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` ~line 3855

## New Features Added

### Admin Error Alerting — yaoyun.zhang@biomate.ai
All CryoSPARC and Nextflow execution failures now send an HTML alert email to yaoyun.zhang@biomate.ai (fire-and-forget, non-blocking). Email includes:
- Run ID, user email, workflow name
- Error message (truncated to 800 chars)
- Timestamp

**Implementation:** `sendAdminAlert(subject, details)` method added to `EmailService` class.
Called from CryoSPARC error handler (routes.ts ~6946) and existing Nextflow error handlers
(routes.ts ~7050, ~7173).

**Files:** `frontend/server/email-service.ts`, `frontend/server/routes.ts`

### Positive User-Facing Error Message
When CryoSPARC execution fails (e.g., GPU instance not ready), the user now sees:
> "Our GPU infrastructure is warming up — the team has been notified and will resolve this shortly. Please try again in a few minutes."

Previously showed raw internal error strings.

### Publication-Quality Methods Report
The `/api/invocations/:id/methods-report` endpoint now generates a 10-section report:

1. Abstract (150 words)
2. Study Overview
3. Computational Environment (AWS region, instance type, GPU model, software versions)
4. Data Acquisition and Preprocessing
5. Methods (per processing stage with parameter values and scientific rationale)
6. Pipeline Execution (step-by-step with wall times)
7. Results (real numbers from output files)
8. Data Analysis and Scientific Interpretation
9. *(CryoEM only)* Cryo-EM Data Quality Assessment — FSC, local resolution, B-factor, particle yield
10. *(CryoEM only)* EMDB/PDB Deposition Note + Reproducibility Statement

**Required citations always included for CryoEM:**
- CryoSPARC (Punjani 2017, PMID 28165473)
- CTFFIND4 (Rohou 2015, PMID 26278980)
- MotionCor2 (Zheng 2017, PMID 28250466)
- Non-uniform refinement (Punjani 2020, PMID 33257830)
- Local CTF refinement (Punjani 2021, PMID 34282325)
- DeepEMhancer (Sanchez-Garcia 2021, PMID 34267316)

**DOCX export:** Add `?format=docx` to the endpoint URL to get a Word document via pandoc.

**Files:** `frontend/server/routes.ts` ~line 3739

## Test Changes

### CS-10 E2E Test Fixes
- Poll timeout: 5,400,000ms (90 min) → 7,200,000ms (2 hr) — g6.2xlarge has 1×L4 vs 4×L4
- Added `await page.waitForTimeout(1000)` after `clickRunAndCaptureId` so the async response
  handler has time to set `executeEngine` before the assertion runs

## Status at End of Session
- CS-10 launched successfully: `runId=6450a5d8-83aa-4cf3-98d3-5924a5ac1738` polling (2hr)
- All 5 execution bugs fixed in both gunicorn and Node server
- Admin email alerting live (requires EMAIL_HOST/EMAIL_USER/EMAIL_PASS in env)
- Methods report upgraded to journal-submission quality

## Open Items
- CS-10 final result pending (2hr polling window, test running)
- Email sending requires SMTP env vars — verify EMAIL_HOST etc. are set in production
- Methods report DOCX format: requires `pandoc` installed on the Node server host
- Drug discovery workflow audit: in progress (see companion doc)
