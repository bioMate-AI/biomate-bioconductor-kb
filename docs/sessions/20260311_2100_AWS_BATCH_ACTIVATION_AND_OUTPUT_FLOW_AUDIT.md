# AWS Batch Activation + Output Flow Audit
**Date:** 2026-03-11
**Session objective:** Switch from local mock execution to real AWS Batch; wire billing to production ElastiCache Redis; audit the full intermediate-progress and final-output retrieval flow.

---

## 1. Changes Made This Session

### 1.1 `backend/.env` — Production config

| Variable | Before | After | Why |
|---|---|---|---|
| `REDIS_URL` | `redis://localhost:6379` | `redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379` | Write billing costs to production ElastiCache, not dev container |
| `BILLING_DEV_MODE` | `true` | `false` | Enable real billing enforcement |
| `NEXTFLOW_USE_AWS` | *(absent)* | `true` | Route all workflow runs to AWS Batch |
| `AWS_BATCH_QUEUE` | *(absent)* | `biomate-nextflow-queue` | Correct production queue (was defaulting to `galaxy-cloud-queue`) |
| `AWS_S3_BUCKET` | *(absent)* | `biomate-nextflow-work` | Correct production bucket (was defaulting to `galaxy-cloud-data-1760241377`) |
| `AWS_DEFAULT_REGION` | *(absent)* | `us-west-2` | Batch queue is in us-west-2 |

### 1.2 `nextflow_executor.py` — Mock-mode guard for awsbatch

**File:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
**Function:** `_check_pipeline_constraints()` (line ~399)

**Problem:** Nothing prevented `mock_mode=true` from being passed to a real AWS Batch job. A mock run on Batch would spin up EC2 instances, run pure-Python simulations (producing synthetic data, not real results), and incur billing — wasted spend with no scientific value.

**Fix added:**
```python
if executor == "awsbatch":
    if params.get("mock_mode", False):
        log.warning(
            "[Nextflow] mock_mode=true override: forcing mock_mode=false for "
            "awsbatch executor — real container images will run on Batch."
        )
        params["mock_mode"] = False
    return None  # skip local constraint checks for cloud executor
```

Mutates `params` in-place before the CryoSPARC/ARM checks so every downstream path (config gen, command build) sees `mock_mode=False`.

### 1.3 Galaxy worker reloaded

```
kill -HUP 1523740  # gunicorn master
# New worker: 1915246 (spawned immediately)
# Galaxy toolbox initialization: ~13 minutes
```

---

## 2. Intermediate Progress Flow (AWS Batch)

**Question:** Where does progress come from during a running batch job?

### Answer: Nextflow HEAD process running on the Galaxy EC2 machine

When `NEXTFLOW_USE_AWS=true`:
1. The Nextflow **head process** (the `nextflow run ...` JVM) runs **locally on the Galaxy EC2 instance** (172.31.8.116 / 35.89.57.94)
2. The head process submits task containers to AWS Batch and polls their status via the AWS Batch API
3. The head process writes `workflow-trace.txt` **locally** on that EC2 machine
4. `_start_qc_monitor()` in `nextflow_executor.py` polls that local trace file every 5 seconds
5. Task-level progress (completed/running/failed counts, %) flows back to the frontend via SSE

**Progress data path:**
```
AWS Batch (EC2 compute nodes)
  → report status back to Nextflow head (via Batch API polling)
  → Nextflow head writes workflow-trace.txt (LOCAL on Galaxy EC2)
  → _start_qc_monitor() polls trace file every 5s
  → SSE inject → /internal/sse-inject → frontend EventSource
  → Chat panel shows live progress bar + QC gate events
```

**Log tailing:** `GET /api/nextflow/status/{run_id}` returns the last 20 lines of the Nextflow head process log (also local on Galaxy EC2).

**NO EventBridge for progress** — EventBridge only triggers the billing Lambda on RUNNING/SUCCEEDED/FAILED job state changes, not for workflow-level progress.

---

## 3. Intermediate Work Files (AWS Batch)

**Where task working directories live:**

- **S3:** `s3://biomate-nextflow-work/nextflow/work/`
- Each Batch task gets its own S3 prefix under this path
- Nextflow injects `nxf_s3_upload()` into every task script to sync outputs back to S3
- These are scratch/intermediate files — staging inputs from S3 + writing outputs back

The local `work_dir` created at `/tmp/nextflow_runs/{run_id}/work/` is used only for the Nextflow head process's own working directory (config, session cache), NOT for task execution files.

---

## 4. Final Output Files (AWS Batch)

**Where published results land:**

- **S3:** `s3://biomate-nextflow-work/{user-specified-outdir}/` or the default outdir returned by `_resolve_outdir()`
- Nextflow `publishDir` directives in the `.nf` files copy task outputs to this S3 path
- The manifest file `workflow_outputs.json` is written to `{outdir}/workflow_outputs.json`

**outdir auto-detection logic (nextflow_executor.py line ~1010):**
```python
if params.get("outdir", "").startswith("s3://"):
    compute["executor"] = "awsbatch"   # auto-select Batch when outdir is S3
    effective_outdir = params["outdir"]
else:
    effective_outdir = "/tmp/nextflow_runs/{run_id}/output"  # local fallback
```

---

## 5. ⚠️ Critical Gap: Output Retrieval Does Not Work for S3 Paths

**This is the most important finding from this audit.**

### Current retrieval code (frontend/server/routes.ts ~line 4420)

```typescript
// addRuntimeArtifactOutputs() stores outputs like:
await storage.addOutput({
  metadata: { localPath: artifactPath }  // e.g., "/tmp/nextflow_runs/.../output/results.vcf"
})

// Download endpoint:
const localPath = output.metadata.localPath
const fileStream = createReadStream(localPath)   // ← ONLY WORKS FOR LOCAL PATHS
fileStream.pipe(res)
```

### The gap

When `executor == "awsbatch"`, `outdir` is `s3://biomate-nextflow-work/...`. The `addRuntimeArtifactOutputs()` function tries to `fs.stat()` an S3 URL as if it were a local path → **fails silently → no outputs listed in UI**.

Similarly, `manifest_path = outdir / "workflow_outputs.json"` at `/api/nextflow/invocations/{id}/manifest` tries to read an S3 key as a local file → **404 or ENOENT**.

### What needs to be built (next sprint)

1. **S3 output lister**: After job completion, call `aws s3 ls s3://{outdir}/` to enumerate output files
2. **Presigned download URLs for outputs**: Generate temporary presigned GET URLs (15-min expiry) instead of `createReadStream()` for S3-backed files
3. **Manifest fetch from S3**: `aws s3 cp s3://{outdir}/workflow_outputs.json /tmp/...` or use AWS SDK `GetObject`
4. **Frontend transparent**: Frontend already handles URLs — just needs the download endpoint to redirect to presigned URL for S3 outputs

This is a **blocking gap for real AWS Batch end-to-end output retrieval**. The job runs and billing records correctly; the output files are in S3; but the frontend cannot yet display or download them.

---

## 6. Billing Flow (Complete, Working)

**What works today:**

```
AWS Batch job state change (RUNNING / SUCCEEDED / FAILED)
  → EventBridge rule: biomate-batch-job-state-change
  → Lambda: batch_event_handler.py
  → Reads job metadata from Batch API (vCPUs × hours, memory)
  → Writes to ElastiCache Redis:
       cost:{user_id}:month:2026-03:total          ← cumulative monthly
       billing:batch:job:{job_id}                   ← per-job record
       billing:run:{run_id}:compute_usd             ← per-run cost
  → Frontend: GET /api/billing/usage → reads from Redis → shows in UI
```

With `REDIS_URL` now pointing to ElastiCache and `BILLING_DEV_MODE=false`, this flow is fully live for any batch job triggered from today.

---

## 7. Full Execution Flow Summary (AWS Batch, After This Session)

```
User types query in chat
  ↓
AI selects correct workflow (e.g., pharmacology/docking_autodock_vina)
  ↓
"AWAITING REVIEW" badge — user clicks "Confirm & Run"
  ↓
POST /api/nextflow/execute  {params, executor: "awsbatch"}
  ↓ mock_mode override: false  ←  NEW GUARD
  ↓ generate biomate_executor_override.config with queue=biomate-nextflow-queue
  ↓
nextflow run .../docking/main.nf -profile awsbatch ...
  (head process on Galaxy EC2)
  ↓
Batch submits containers:
  - ALPHAFOLD3 (GPU g4dn.xlarge)
  - AUTODOCK_VINA (CPU c5.2xlarge)
  Work files: s3://biomate-nextflow-work/nextflow/work/
  ↓
Progress: trace file → SSE → chat panel live updates
  ↓
Job SUCCEEDED:
  Published outputs → s3://biomate-nextflow-work/{outdir}/
  EventBridge → Lambda → Redis cost record          ← billing live
  ↓
⚠ Output retrieval: NOT YET WORKING for S3 paths
  (outputs in S3 but frontend expects local paths)
```

---

## 8. Next Steps

| Priority | Task | Complexity |
|---|---|---|
| P0 | S3 output lister + presigned download URLs | Medium (1 day) |
| P0 | Manifest fetch from S3 (`GetObject`) | Small (2 hours) |
| P1 | E2E test: real Batch job → billing cost appears in Redis | Medium |
| P2 | E2E test fix: `localStorage.clear()` in `registerAndGoHome()` to prevent execution panel bleed-through | Small (30 min) |
| P3 | Verify ElastiCache connectivity from Galaxy EC2 (check security group 6379 allow) | Small |
