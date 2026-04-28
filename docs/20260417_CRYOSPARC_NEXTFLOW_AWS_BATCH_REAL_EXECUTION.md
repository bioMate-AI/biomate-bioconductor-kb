# CryoSPARC Real Execution — Nextflow + AWS Batch Architecture (2026-04-17)

## Goal
Replace the fully-mocked CryoSPARC SPA pipeline with real computation:
- **AWS Batch** orchestrates pipeline steps (parallel containers)
- **CryoSPARC EC2 GPU instance** (g6.12xlarge, 4× NVIDIA L4) performs all GPU compute
- End-to-end validated by CS-10 Playwright test against real EMPIAR-10028 data

## Previous State (Mocked)
`main.nf` generated random fake `.cs` files and `.mrc` maps — no real CryoSPARC API calls.
CS-1 through CS-5 tests passed by checking that fake files appeared in the UI.
The mocked outputs were useless for validating intermediate output visualization or download.

## New Architecture: Two-Layer Parallelism

```
User query → AI routes to CryoSPARC SPA → routes.ts → /api/cryosparc/execute
     ↓
[Backend] execute_cryosparc():
  1. start_instance(wait=True)  → EC2 g6.12xlarge with CryoSPARC pre-installed
  2. execute_nextflow(cryosparc_standard_spa/main.nf)
     ↓
[AWS Batch] Nextflow orchestrator spawns containers:
  - INIT_CRYOSPARC_PROJECT: create project + workspace, import movies → cs_init.json
  - PATCH_MOTION_CORRECTION_BATCH: submit MC jobs via cryosparc-tools, poll to done
  - PATCH_CTF_ESTIMATION_BATCH: same pattern
  - BLOB_PICKER_BATCH, CLASSIFY_2D_R1/R2_BATCH: parallel batches
  - AB_INITIO_BATCH, HOMO_REFINEMENT_BATCH: multi-class ab initio
  - NON_UNIFORM_REFINEMENT, LOCAL_CTF_REFINEMENT, SHARPEN: final steps
     ↓
[CryoSPARC EC2] GPU compute for all jobs (4× L4 used concurrently)
  - Multiple Batch containers submit/poll CryoSPARC jobs simultaneously
  - GPU queue inside CryoSPARC serializes GPU compute per job
  - Net effect: CPU prep runs in parallel, GPU jobs queue on the 4-GPU node
```

## Key Changes

### ECR Image: `biomate/cryosparc-nf:latest`
- **Dockerfile**: `backend/docker/cryosparc-nf/Dockerfile`
- Base: `python:3.11-slim`
- Packages: `cryosparc-tools`, `boto3`, `numpy`, AWS CLI v2
- No GPU required — containers only submit/poll CryoSPARC API
- ECR: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryosparc-nf:latest`

### `main.nf` — Real CryoSPARC API Calls
- Added `CS_IMAGE` and `CS_HELPER` Groovy defs:
  - `cs_connect(license, host, port, email, password)` — creates `CryoSPARC` client
  - `submit_and_wait(cs, proj_uid, ws_uid, job_type, connections, params, lane, timeout)` — submits job and polls until terminal (14400s timeout per job)
- **`INIT_CRYOSPARC_PROJECT`** process: creates project + workspace, submits `import_movies` job, outputs `cs_init.json` with `{project_uid, workspace_uid, import_job_uid, num_movies}`
- All downstream processes read `cs_init.json` for UID chaining
- All GPU jobs use `num_gpu=4` (matches g6.12xlarge)
- All containers: 2 CPU, 4 GB RAM on `biomate-nextflow-queue`

### `nextflow.config`
- `container = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryosparc-nf:latest'`
- All processes: `cpus=2`, `memory='4 GB'`, `queue='biomate-nextflow-queue'`
- `queueSize=20`, `submitRateLimit='10/1min'`, `pollInterval='30 sec'`

### Backend: `nextflow_executor.py`
- `execute_cryosparc()`: starts EC2 via `cs_exec.start_instance(wait=True)`, builds `nf_params` with CryoSPARC connection info + user acquisition params, calls `execute_nextflow()`, returns `{executor: "nextflow", execution_engine: "cryosparc", run_id: nf_run_id}`
- `GET /api/cryosparc/gpu_metrics`: SSH into EC2, runs `nvidia-smi`, returns per-GPU utilization

### Backend: `cryosparc_executor.py`
- Default instance type: `g6.12xlarge` (4× NVIDIA L4 GPUs)
- `_gpu_count_for_instance()`: maps instance type → GPU count
- `user_data` startup script: calls `cryosparcw update --gpus 0,1,2,3` to register all 4 GPUs
- `ensure_cryosparc_running()`: 900s timeout, SSH diagnostics every 30s
- EBS volume: 500 GB (CryoSPARC snapshot requires ≥500 GB)

### Frontend: `routes.ts`
- `GET /api/cryosparc/gpu_metrics` proxy endpoint
- `hasCryoSPARCInstance = !!(CRYOSPARC_INSTANCE_ID || CRYOSPARC_AMI_ID)` — both set via `start_backend.sh`

## Bug Fixed: Param Parser First-Occurrence Deduplication

`_parse_nextflow_params()` in `ai_assistant.py` scanned all `params.X = ...` lines in main.nf.
For `particle_box_size`, the parser was picking up the *second* assignment inside the workflow block:
```groovy
params.particle_box_size = estimate_box_size(...)  # line 1882
```
...instead of the correct top-level default `params.particle_box_size = null` (line 80).

This caused the UI to show `estimate_box_size(` as the param's default value, which the
Confirm & Run button's validation rejected → button stayed disabled → CS-10 test aborted.

**Fix**: Added `seen_names: set` — first occurrence wins. Applied to `ai_assistant.py:2145`.

## Environment Variables Required (Node server)
The Node server must be started with these vars from `start_backend.sh`:
```
CRYOSPARC_AMI_ID=ami-008607f719aaac1b0
CRYOSPARC_HOST=100.54.207.255
CRYOSPARC_PORT=30000
CRYOSPARC_EMAIL=admin@biomate.ai
CRYOSPARC_PASSWORD=BioMate2026!
CRYOSPARC_INSTANCE_TYPE=g6.12xlarge
CRYOSPARC_PROJECT_DIR=/home/ubuntu/cryosparc_projects
CRYOSPARC_SSH_KEY=/home/yzhang/.ssh/cryosparc-benchmark.pem
```

## CS-10 E2E Test

Test: `e2e/cryoem-stepwise-and-output.e2e.ts::CS-10`
Dataset: EMPIAR-10028 (β-galactosidase), 5 movies from `s3://biomate-cryo-data/empiar-10028/Micrographs/00[1-5]_movie.mrcs`
Parameters: `pixel_size=1.77`, `symmetry=D2`, `particle_diameter_angstroms=120`, `voltage=300`
Timeout: 2 hours (EC2 cold start ~10 min, 5-movie SPA ~30-60 min)

Assertions:
- Workflow card appears with CryoSPARC SPA
- Execute returns `executionEngine=cryosparc` and a valid `runId`
- Run polls to `completed` (not failed)
- ≥4 phase cards present with correct statuses
- Output files include `.cs`, `.mrc`, `.png` extensions
- Findings card appears with summary text
- Methods report HTTP 200
- Wall time metric shows in run metrics strip

## Additional Bugs Fixed During CS-10

### `runnableWorkflow: false` for CryoSPARC workflows (routes.ts)
`runnableWorkflow` check only allowed: `workflow_ga`, `nextflow_path`, `workflow_type=chain`, `chain_name`.
CryoSPARC responses have `workflow_type=cryosparc` — none of the above. Added `workflow_type === "cryosparc"` to the check.
Without this fix, the drug-development quality guard ran and appended drug discovery boilerplate to all CryoSPARC responses, and `runnableWorkflow: false` meant the workflow card never appeared.

### `cryosparc_password` visible as required field in UI (ai_assistant.py)
The param `params.cryosparc_password = null` in main.nf was treated as required (null, not in `_OPTIONAL_NULL_PARAMS`).
Fix: added infrastructure params to `_NEXTFLOW_INTERNAL_PARAMS` so they never appear in the UI form:
`cryosparc_password`, `cryosparc_email`, `cryosparc_host`, `cryosparc_port`, `cryosparc_project_dir`, `cryosparc_lane`,
plus parallelism internals (`micrograph_batch_size`, `particle_batch_size`, `num_gpu`, etc.)

### Null-string defaults in UI (ai_assistant.py)
Optional null params (`dose_per_frame`, `particle_box_size`, `gain_ref`) were getting `default="null"` (string).
UI showed "null" as the input value, which the "already filled" check in `fillRequiredParams` let through.
Fix: `default_str = None if (is_required or val_raw == "null") else val_raw.strip("'\"")` — all null params get Python None.

### First-occurrence wins for params (ai_assistant.py)
Regex `params.\w+ = ...` was matching ALL assignments, including re-assignments inside workflow body blocks.
`params.particle_box_size = estimate_box_size(...)` on line 1882 overrode the correct `null` default from line 80.
Fix: `seen_names` set — first declaration wins.

### Catch-all param filler in E2E test (cryoem-stepwise-and-output.e2e.ts)
Added fallback loop in `fillRequiredParams` that fills any visible text/number input still showing empty or "null",
using type-appropriate placeholder values (S3 path for path fields, license key, email, etc.).

## Status (2026-04-17)
- ECR image built and pushed ✓
- main.nf real API calls implemented ✓
- nextflow.config updated ✓
- execute_cryosparc routes through Nextflow ✓
- All 5 param parser / UI bugs fixed ✓
- CS-10 test: **in progress** (EC2 cold start + Nextflow submission pending)
