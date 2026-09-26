# On-Prem Simulation Test Results — 2026-09-26

## Context

Simulated a real customer on-prem single-node BioMate deployment on:
- Instance: `i-0d39e0fe269a69864` (`biomate-onprem-sim`, `35.92.8.10`, t3.xlarge, Ubuntu 22.04)
- LLM: Qianwen/DashScope (`GALAXY_AI_LLM_PROVIDER=openai_compatible`, model `qwen-max`)
- Branch tested: `fix/onprem-llm-compatibility`

## Full 9-Step Journey Test Results

All 9 steps GREEN on final run with image `sha-97f38f24b169`:

| Step | Description | Status |
|------|-------------|--------|
| 1 | Login (register + auth token) | ✅ |
| 2 | Create project | ✅ |
| 3 | Qianwen tool call (research_query fires) | ✅ |
| 4 | Qianwen → ADMET workflow routing (`workflow_ready`) | ✅ |
| 5 | Workflow search + execute accepted | ✅ |
| 6 | Workflow completed (~10s) | ✅ |
| 7 | Output files listed (5 files from local filesystem) | ✅ |
| 8 | MinIO bucket verified | ✅ |
| 9 | AI findings generated via Qianwen | ✅ |

## Security Verification Results (sha-85728dc568b3)

| Check | Expected | Actual | Pass |
|-------|----------|--------|------|
| Cancel without token | 401 | 401 | ✅ |
| Cancel with token, bad ID | 404 | 404 | ✅ |
| Execute without token | 401 | 401 | ✅ |
| Rerun without token | 401 | 401 | ✅ |
| Chat sessions API (`/api/sessions`) | 200 | 200 (4 sessions) | ✅ |
| License status (demo key) | valid=true | valid=false (Galaxy not restarted) | ⚠️ config |

## Bugs Found and Fixed

### Bug 1 — Output files returning 0 for local (non-S3) runs
- **Root cause**: `integration/next-phase` routes.ts only called Galaxy's `/api/nextflow/status/{id}` which returns `s3_output_files` (empty for local runs). Missing second call to `/api/nextflow/runs/{id}/output_files`.
- **Fix**: Added fallback in `routes.ts` `/api/workflows/runs/:id/output_files` handler to call `GET /api/nextflow/runs/{id}/output_files` from Galaxy when S3 files are empty. Added `/api/galaxy-proxy/…` route to proxy local file downloads through the Node server.
- **Commit**: `64765fb44`

### Bug 2 — Fresh-install crash: Docker CLI not installed in backend image
- **Root cause**: Backend Docker image (`biomate-galaxy`) didn't have Docker CLI installed.
- **Fix**: Added `docker-ce-cli` installation to backend Dockerfile.
- **Commit**: `64765fb44`

### Bug 3 — Fresh-install crash: `nf-work` dir missing permissions
- **Root cause**: `install.sh` never created `/app/nf-work`. Docker creates bind-mount dirs as root; Galaxy (uid=1000) can't write.
- **Fix**: Added step to `install.sh`: `mkdir -p $NEXTFLOW_WORK_DIR && chmod 777 $NEXTFLOW_WORK_DIR` before `docker compose up`.
- **Commit**: `fda22c82f`

### Bug 4 — AI findings returning 503 with non-Anthropic LLMs
- **Root cause**: `/api/workflows/runs/:id/ai/analyze` checked `process.env.ANTHROPIC_API_KEY` at entry and returned 503 if missing.
- **Fix**: Removed the ANTHROPIC_API_KEY early guard. `llmGenerate()` routes to any provider.
- **Commit**: `be742fab0` (PR #247)

### Bug 5 — Background findings task hardcoded to Gemini
- **Root cause**: Background findings analysis task called `callGeminiFlash()` unconditionally.
- **Fix**: Detect configured provider; use `llmGenerate()` when Gemini is not the sole configured LLM.
- **Commit**: `be742fab0` (PR #247)

### Bug 6 — Status endpoint missing auth (`authenticateToken`)
- **Root cause**: `GET /api/workflows/runs/:id/status` used no auth middleware — anyone could poll any run.
- **Fix**: Added `authenticateToken` middleware.
- **Commit**: `9dd864818`

### Bug 7 — Failed-run findings stuck in "pending" forever
- **Root cause 1**: No status check before triggering background analysis.
- **Root cause 2**: Checked `run.status` (undefined) instead of `run.execution?.status`.
- **Fix**: Added status guard; return static `{status:'error'}` response immediately for failed runs.
- **Commit**: `97f38f24b`

### Bug 8 — Cancel/rerun/execute endpoints missing auth (SECURITY)
- **Root cause**: All three used `optionalAuth` — unauthenticated users could cancel any run, rerun any workflow, and execute arbitrary workflows.
- **Fix**: Changed to `authenticateToken` + added userId ownership check on cancel/rerun.
- **Commit**: `77e0de074`
- **Verified**: All three return 401 without token on deployed instance.

### Bug 9 — Browser-uploaded files not staged for Nextflow on on-prem
- **Root cause**: `stageLocalFilesForBatch()` returned early when `NEXTFLOW_USE_AWS=false`, leaving uploaded files inaccessible to Galaxy.
- **Fix (frontend)**: Detect `S3_ENDPOINT_URL` (MinIO); create path-style MinIO client and upload files to `biomate-data` bucket.
- **Fix (backend)**: `_generate_executor_config()` now generates a minimal nextflow.config with MinIO aws.client settings when local executor + S3_ENDPOINT_URL is set, so Nextflow can stage `s3://` inputs.
- **Commit**: `112ba23c3`

### Bug 10 — `.env.onprem.example` duplicate `NEXTFLOW_WORK_DIR` and wrong default license key
- **Root cause 1**: Two `NEXTFLOW_WORK_DIR` entries (line 106: `/tmp/biomate-nf-work`, line 121: `/app/nf-work`).
- **Root cause 2**: `BIOMATE_LICENSE_KEY` set to placeholder `BMOP-XXXX-...` causing fresh installs to show `valid:false`.
- **Fix**: Removed duplicate entry; set `BMOP-DEMO-DEMO-DEMO-DEMO` as default.
- **Commit**: `85728dc56`

### Bug 11 — `install.sh` admin creation uses `require('./server/db.ts')` (broken in production)
- **Root cause**: Production image has no `.ts` files — TypeScript is compiled to `/app/dist/`. The admin creation silently failed for all users.
- **Fix**: Replaced with API-based flow: `POST /api/auth/register` → `POST /api/auth/verify-email` → psql UPDATE to `subscription_tier='admin'`.
- **Commit**: `15c3237d1`

## Known Issues (Not Blocking)

- **Workflow search routing**: Searching for "ADMET prediction small molecule toxicity" returns wrong workflow via search API. Chat routing (via `workflow_ready`) works correctly. DB scoring fix is a separate issue.
- **File upload test**: MinIO staging fix (Bug 9) not yet E2E-verified — needs a workflow that accepts a file input to confirm staging → Nextflow read → success.
- **License on sim instance**: Galaxy container needs restart with `BIOMATE_LICENSE_KEY=BMOP-DEMO-DEMO-DEMO-DEMO` to verify the license fix. This requires updating the `.env` on the instance.

## Deployment Artifacts

| Artifact | Value |
|----------|-------|
| Frontend image (security + MinIO) | `sha-85728dc568b3` |
| Branch | `fix/onprem-llm-compatibility` |
| PR open | #248 → `integration/next-phase` (waiting for merge) |

## Commits in this PR

| SHA | Change |
|-----|--------|
| `64765fb44` | Fresh-install bugs: output files, Docker CLI, compose volumes |
| `be742fab0` | LLM provider: remove Anthropic guard, replace Gemini hardcode |
| `9dd864818` | Auth on status endpoint |
| `97f38f24b` | Failed-run findings: execution.status fix |
| `77e0de074` | Security: auth on cancel/rerun/execute |
| `112ba23c3` | MinIO file staging for on-prem |
| `85728dc56` | Env example: demo license key, remove duplicate NEXTFLOW_WORK_DIR |
| `fda22c82f` | install.sh: create nf-work dir before docker compose up |
| `15c3237d1` | install.sh: fix admin creation (API-based, not require .ts) |
