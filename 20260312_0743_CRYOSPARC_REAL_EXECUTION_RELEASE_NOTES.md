# CryoSPARC Real Execution — Release Notes
**Date**: 2026-03-12
**Branch**: `connection_formal`
**Status**: Implementation complete — ready for data staging and live E2E test

---

## Overview

BioMate now routes cryo-EM SPA queries to a **real CryoSPARC v5** instance instead of the previous
Nextflow simulation pipeline. When a user asks BioMate to process cryo-EM data, it:

1. Launches a GPU instance from a pre-baked AMI (~5-8 min cold start)
2. Submits real CryoSPARC jobs (import → motion correction → CTF estimation)
3. Streams live progress back to the chat UI
4. **Terminates** the instance when done (no idle cost)

---

## Background: Why This Change Was Needed

The existing `cryosparc_standard_spa/main.nf` pipeline was **entirely simulated** — all 23 processes
generated random data via embedded Python scripts. There was no real CryoSPARC execution anywhere in
the codebase. The `use_cryosparc` and `cryosparc_license` parameters in the Nextflow script were dead
code.

This release replaces simulation with real execution via the `cryosparc-tools` Python library.

---

## Architecture

```
User query
   │
   ▼
ai_assistant.py
   ├── Matches `cryosparc_standard_spa` workflow (DB id=1826, format=nextflow)
   ├── Detects num_movies > 1000 → sets pilot_run_suggested=True (new Reason 6)
   └── Returns workflow_type="nextflow", nextflow_path="...cryosparc_standard_spa/main.nf"
   │
   ▼
frontend routes.ts  POST /api/workflows/execute
   ├── Detects nextflow_path.includes("cryosparc")  ← NEW ROUTING BRANCH
   ├── Merges params from generated_parameters + inline_parameters + parameters
   └── Calls POST /api/cryosparc/execute on Galaxy backend
   │
   ▼
Galaxy backend  POST /api/cryosparc/execute  (nextflow_executor.py)
   └── Calls cryosparc_executor.execute_spa_pipeline() in background thread
   │
   ▼
cryosparc_executor.py
   ├── ensure_cryosparc_running()
   │     ├── aws ec2 run-instances --image-id ami-008607f719aaac1b0  (fresh instance)
   │     ├── Waits for instance running + 30s for SSH/CryoSPARC startup
   │     └── Updates CRYOSPARC_HOST with new public IP
   ├── CryoSPARC(host, port, email, password).test_connection()
   ├── cs.api.projects.create(title="biomate-{run_id[:8]}", parent_dir=...)
   ├── cs.create_workspace(project_uid, title="W1-spa")
   ├── import_movies job  → queue(lane="default") → wait for completion
   ├── patch_motion_correction_multi job → wait
   ├── patch_ctf_estimation_multi job → wait
   ├── progress 0→100% reported via callback
   └── After job: terminate instance (EBS auto-deleted, no idle cost)
   │
   ▼
Status polling  GET /api/cryosparc/status/{run_id}
   └── Returns {status, progress_percent, job_uids, project_uid, ...}
```

---

## New Files

### `backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py`
**Purpose**: Direct CryoSPARC v5 execution via `cryosparc-tools` Python library.

Key functions:

| Function | Description |
|---|---|
| `execute_spa_pipeline(run_id, params, user_id)` | Entrypoint — starts background thread |
| `ensure_cryosparc_running(cb)` | Launches EC2 from AMI if not running |
| `start_instance(wait=True)` | Launches fresh g6.2xlarge from AMI; records `_active_instance_id` |
| `stop_instance()` | **Terminates** (not stops) instance — no residual EBS cost |
| `get_run_status(run_id)` | Returns status dict compatible with Nextflow status format |
| `_execute_spa_pipeline_sync(run, cb)` | Synchronous pipeline: project → workspace → import → motion → CTF |
| `_wait_for_job(job, run, cb, target_pct, step_name)` | Polls job status with linear progress interpolation |

Parameters accepted by `execute_spa_pipeline`:

| Parameter | Default | Description |
|---|---|---|
| `movie_dir` | — | **Required** — path to EER/TIFF/MRC movies on CryoSPARC host |
| `pixel_size` | `1.0` | Å/pixel |
| `voltage` | `300` | kV |
| `cs` | `2.7` | Spherical aberration (mm) |
| `amplitude_contrast` | `0.1` | Fraction |
| `particle_diameter` | `180` | Å |
| `symmetry` | `C1` | Point group (e.g. D2, C3) |
| `num_movies` | — | Informational; triggers pilot run banner if >1000 |
| `total_dose` | `40.0` | e⁻/Å² |

### `frontend/e2e/cryoem-real-e2e.e2e.ts`
End-to-end Playwright test for the full cryo-EM user story.

**Dataset**: EMPIAR-10028 — E. coli β-galactosidase (7028 EER, 0.885 Å/px, D2, ~180 Å, 300 kV)
**Test timeout**: 10 minutes (AWS GPU cold start)

Test steps:
- **T0**: QC profiles API — verifies 5 cryo-EM profiles exist (`cryoem_spa_*`)
- **T1**: Page loads, login as `cryoem-e2e` test user
- **T2**: Sends EMPIAR-10028 query with all acquisition parameters
- **T3**: Workflow card appears; pilot run banner checked (`data-testid="pilot-run-banner"`)
- **T4**: QC Settings panel — expands, selects `cryoem_spa_standard` profile, adds `total_drift_angstrom=10` override
- **T5**: Clicks Execute; waits for workflow progress
- **T6**: Cold-start banner check (`data-testid="cold-start-banner"`) if AWS Batch mode
- **T7**: Polls for completion/failure/QC gate modal
- Screenshots saved to `frontend/e2e/screenshots/cryoem-e2e/`

### `docs/CRYOEM_E2E_USER_GUIDE.md`
User-facing step-by-step guide for Dr. Sarah Chen's EMPIAR-10028 workflow.

---

## Modified Files

### `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
**Change**: Added Reason 6 for pilot run suggestion — large cryo-EM dataset trigger.

```python
# Reason 6: Large cryo-EM dataset (num_movies > 1000)
_num_movies = None
for _pd in result.get('generated_parameters', []):
    for _key in ('num_movies', 'num_micrographs', 'movie_count'):
        if _key in _pd.get('parameters', {}):
            _num_movies = int(_pd['parameters'][_key])
# Fallback: parse "num_movies=7028" from raw message text
if _num_movies is None and request.message:
    _m = re.search(r'\bnum_movies\s*=\s*(\d+)', request.message, re.IGNORECASE)
    if _m:
        _num_movies = int(_m.group(1))
if _num_movies and _num_movies > 1000:
    pilot_reasons.append(
        f"Large cryo-EM dataset ({_num_movies:,} movies) — "
        f"pilot run on ~200 movies recommended before full processing"
    )
```

**Impact**: When a user specifies `num_movies=7028` (or similar) in their cryo-EM query, the
workflow viewer now shows the amber pilot run banner.

### `frontend/client/src/components/nextflow-workflow-viewer.tsx`
**Change**: Added pilot run banner to the `NextflowWorkflowViewer` component (previously only
`WorkflowArtifact` showed it).

```tsx
{workflowDefinition?.pilot_run_suggested && !isExecuting && (
  <div className="rounded-lg border border-amber-300 bg-amber-50 ..."
       data-testid="pilot-run-banner">
    <AlertTriangle ... />
    <div>
      <span className="font-semibold">Pilot run recommended</span>
      {workflowDefinition.pilot_message && (
        <span> — {workflowDefinition.pilot_message}</span>
      )}
    </div>
  </div>
)}
```

**Location**: Between `<ParameterGroup />` and the run controls.

### `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
**Change**: Added 2 new API routes at end of file.

```python
POST /api/cryosparc/execute
    Body: { parameters: {...}, user_id?: string, history_id?: string }
    Returns: { success, run_id, invocation_id, executor, message }

GET /api/cryosparc/status/{run_id}
    Returns: { run_id, status, progress_percent, job_uids, project_uid, executor, ... }
```

Both routes lazy-import `cryosparc_executor` — if `cryosparc-tools` is not installed the
endpoint returns 503 instead of crashing the Galaxy worker.

### `frontend/server/routes.ts`
Three changes:

**1. CryoSPARC execution routing** (in `POST /api/workflows/execute`):

```typescript
const isCryoSPARC = (request.workflowDefinition.nextflow_path || '').includes('cryosparc') &&
  request.workflowDefinition.workflow_type === 'nextflow';

if (isCryoSPARC) {
  // Merge params from all sources: generated_parameters[] + inline_parameters + parameters
  const genParams = {};
  for (const entry of (request.workflowDefinition.generated_parameters || [])) {
    Object.assign(genParams, entry?.parameters || {});
  }
  const allParams = { ...genParams, ...inlineParams, ...rawParams };

  // Call /api/cryosparc/execute on Galaxy backend
  const csResponse = await fetch('.../api/cryosparc/execute', { body: JSON.stringify({
    parameters: allParams, history_id, user_id
  })});
  // Store executionEngine: 'cryosparc' on ExecutionRun for status routing
}
```

**2. Status routing fix** (in `GET /api/invocations/:id/nextflow/status`):

```typescript
const isCryoSPARCRun = executionRun?.execution?.executionEngine === 'cryosparc';
const statusUrl = isCryoSPARCRun
  ? `.../api/cryosparc/status/${invocation.galaxyInvocationId}`
  : `.../api/nextflow/status/${invocation.galaxyInvocationId}`;
```

**3. New proxy route**: `GET /api/cryosparc/status/:runId` → proxies to Galaxy backend.

### `backend/.env`
```
# CryoSPARC Real Execution
CRYOSPARC_HOST=100.54.207.255       # will be updated dynamically by executor on each launch
CRYOSPARC_PORT=30000
CRYOSPARC_EMAIL=admin@biomate.ai
CRYOSPARC_PASSWORD=BioMate2026!
CRYOSPARC_LICENSE=f312a30e-63fc-11f0-8e36-e3c932851287
CRYOSPARC_PROJECT_DIR=/home/ubuntu/cryosparc_projects
CRYOSPARC_SSH_KEY=/home/yzhang/.ssh/cryosparc-benchmark.pem
CRYOSPARC_SSH_USER=ubuntu
# No persistent instance — launch from AMI, terminate after job
# CRYOSPARC_INSTANCE_ID=  (cleared — instance terminated 2026-03-12)
CRYOSPARC_AMI_ID=ami-008607f719aaac1b0
CRYOSPARC_INSTANCE_REGION=us-east-1
CRYOSPARC_INSTANCE_TYPE=g6.2xlarge
# AUTO_STOP_AFTER_MINUTES=5  (default; set to 0 to disable auto-terminate)
```

---

## Infrastructure

### EC2 Instance (on-demand, launched per job)
| Property | Value |
|---|---|
| AMI | `ami-008607f719aaac1b0` (us-east-1) |
| Instance type | `g6.2xlarge` (NVIDIA L4 24 GB VRAM, 8 vCPU, 32 GB RAM) |
| Security group | `sg-015137721b5fabddb` (cryosparc-sg) — ports 22, 30000 open |
| SSH key | `cryosparc-benchmark` / `~/.ssh/cryosparc-benchmark.pem` |
| EBS on launch | 200 GB gp3, `DeleteOnTermination=True` |
| Tags | `Name=cryosparc-biomate-job`, `Project=biomate`, `AutoTerminate=true` |

### AMI Contents (`ami-008607f719aaac1b0`)
- Ubuntu 22.04 (Deep Learning AMI base)
- NVIDIA drivers + CUDA
- CryoSPARC v5 master + worker (lane `default`, GPU 0)
- Java 21, Nextflow 25.10.4
- cryosparc-tools 5.0.2 (`pip install cryosparc-tools`)
- Admin user: `admin@biomate.ai` / `BioMate2026!`
- License: `f312a30e-63fc-11f0-8e36-e3c932851287`
- User-data on launch: `cryosparcm start` (auto-starts master + worker)

### Cost Model

| State | Cost |
|---|---|
| No active job | ~$2/month (AMI snapshot storage only) |
| Launching (cold start) | $0.98/hr for ~5-8 min = ~$0.08 per launch |
| Running jobs | $0.98/hr (g6.2xlarge on-demand) |
| After job (terminated) | $0 |

**Previous cost (stopped instance)**: ~$42/month idle (EBS $40 + AMI $2).
**Saving**: ~$40/month.

### Why TERMINATE not STOP
Stopped EC2 instances still pay for attached EBS volumes. At 200 GB × $0.08/GB/month = $16/month,
even a "stopped" instance wastes money when idle. Since the AMI preserves the full CryoSPARC setup,
launching from AMI is equivalent to restarting a stopped instance but cheaper:

| Action | Idle cost | Startup time |
|---|---|---|
| Stop + restart | $16/month (200 GB EBS) | ~2 min |
| Terminate + relaunch from AMI | $0 | ~5-8 min |

For a workload that runs infrequently (cryo-EM jobs are hours-long, not seconds), the extra 3-6
minutes of cold start is acceptable.

---

## Data Requirements

Before running a real pipeline, EMPIAR-10028 movies must be staged on the CryoSPARC instance:

```bash
# Option A: Download from EMPIAR FTP (slow, ~7028 EER files)
# Connect to instance after launch, then:
wget -r -np "https://ftp.ebi.ac.uk/empiar/world_availability/10028/data/Movies/" \
     -P /home/ubuntu/empiar-10028/

# Option B: Stage from S3 (fast, if pre-uploaded)
aws s3 sync s3://biomate-cryo-data/empiar-10028/ /home/ubuntu/empiar-10028/
```

Then pass `movie_dir=/home/ubuntu/empiar-10028` as a workflow parameter.

For the pilot run (recommended first), use a subset of ~200 movies to verify the pipeline before
committing to the full 7028-movie dataset.

---

## CryoSPARC Pipeline Steps (Phase 1)

| Step | CryoSPARC Job Type | Progress | Output |
|---|---|---|---|
| 1. Import movies | `import_movies` | 0 → 20% | `imported_movies` dataset |
| 2. Motion correction | `patch_motion_correction_multi` | 20 → 50% | `micrographs` dataset |
| 3. CTF estimation | `patch_ctf_estimation_multi` | 50 → 70% | `micrographs_ctf` dataset |

Phase 2 (future): particle picking (blob + template), 2D classification, ab initio, homogeneous
refinement, FSC, local refinement, sharpening.

---

## QC Integration

CryoSPARC real execution currently does **not** fire QC gates (motion drift thresholds, CTF fit
quality) because the `qc_trace_monitor.py` reads log files written by the Nextflow mock pipeline
(`.log`, `*_motion.txt`). CryoSPARC stores its own metrics internally in MongoDB, not as log files.

**Future work**: Read CryoSPARC job output datasets after each step and compare against QC thresholds:
- `mean_df_A` from CTF job → compare against `fit_quality` gate
- `motion_correction_meanmot` → compare against `total_drift_angstrom` gate

---

## How to Run the E2E Test

### Prerequisites
1. BioMate frontend running: `cd frontend && npm run dev`
2. Galaxy backend running: `cd backend && ./run.sh`
3. EMPIAR-10028 data staged at `/home/ubuntu/empiar-10028/` on CryoSPARC instance
4. `CRYOSPARC_AMI_ID` set in `backend/.env`

### Run the test
```bash
cd frontend
npx playwright test e2e/cryoem-real-e2e.e2e.ts --headed --reporter=html
```

### Expected timeline
- T0 (QC profiles): < 5s
- T1 (page load): < 10s
- T2 (AI response): 30-60s
- T3 (workflow card + pilot banner): immediate
- T4 (QC settings): immediate
- T5 (click Execute): triggers EC2 launch
- Cold start: 5-8 min (instance boot + CryoSPARC start)
- Import movies (100 demo files): ~5-10 min
- Motion correction: ~10-30 min (depends on movie count)
- CTF estimation: ~5-10 min
- T7 (completion): 30-60 min total for pilot run

Screenshots saved to `frontend/e2e/screenshots/cryoem-e2e/`.

---

## Limitations / Known Issues

1. **No QC gate firing with real CryoSPARC**: The `qc_trace_monitor` reads Nextflow log files; it
   does not read CryoSPARC's internal MongoDB metrics. QC gates (drift, CTF, anisotropy) will not
   fire during real execution until Phase 2 QC integration is done.

2. **movie_dir must be pre-staged**: The executor requires `movie_dir` to be set and the movies to
   exist on the CryoSPARC instance before the job is submitted. There is currently no automated
   data staging from S3 to the instance.

3. **Single concurrent job**: Only one CryoSPARC job can run at a time on the single GPU instance.
   Concurrent requests will queue but may fail if the first job hasn't finished setting up.

4. **CRYOSPARC_HOST is stale after restart**: The `.env` file has `CRYOSPARC_HOST=100.54.207.255`
   which was the old stopped instance's IP. On fresh launch, the executor dynamically updates the
   module-level `CRYOSPARC_HOST` variable with the new instance's IP. This is in-process only —
   the `.env` file is not updated. This is correct behavior.

5. **Phase 1 only**: The real pipeline stops after CTF estimation (3 of 23 steps). Particle picking,
   classification, and refinement are not yet implemented in `cryosparc_executor.py`.

---

## Dependencies

### Python (backend)
```
cryosparc-tools==5.0.2   # pip install cryosparc-tools
boto3                     # already present (AWS Batch)
```

Install on the Galaxy backend server:
```bash
pip install cryosparc-tools==5.0.2
```

### AWS Permissions
The IAM role/user running BioMate needs:
```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:RunInstances",
    "ec2:DescribeInstances",
    "ec2:TerminateInstances",
    "ec2:StartInstances",
    "ec2:StopInstances"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "ec2:Region": "us-east-1"
    }
  }
}
```

---

## Release Checklist

- [x] `cryosparc_executor.py` — core executor with EC2 lifecycle management
- [x] `nextflow_executor.py` — `POST /api/cryosparc/execute` and `GET /api/cryosparc/status/{run_id}` routes
- [x] `routes.ts` — CryoSPARC routing branch + status proxy
- [x] `ai_assistant.py` — Reason 6 pilot trigger (num_movies > 1000)
- [x] `nextflow-workflow-viewer.tsx` — pilot run banner for Nextflow workflows
- [x] `cryoem-real-e2e.e2e.ts` — Playwright E2E test
- [x] `docs/CRYOEM_E2E_USER_GUIDE.md` — user guide
- [x] EC2 instance terminated (saving ~$40/month)
- [x] AMI `ami-008607f719aaac1b0` preserved (~$2/month)
- [ ] `pip install cryosparc-tools==5.0.2` on Galaxy backend server
- [ ] Stage EMPIAR-10028 data to S3 (`s3://biomate-cryo-data/empiar-10028/`)
- [ ] Run full E2E test with pilot subset (~200 movies)
- [ ] Phase 2: particle picking + classification + refinement in `cryosparc_executor.py`
- [ ] Phase 2: QC gate integration (read CryoSPARC job outputs, compare against thresholds)
