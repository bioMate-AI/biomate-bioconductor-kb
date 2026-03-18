# S3 Input/Output Gap — Findings & Implementation Plan
**Date:** 2026-03-11 23:26 UTC
**Context:** AWS Batch is now the execution target. Both input files (user data) and output files (workflow results) can live in S3. The current code handles neither correctly.

---

## Findings

### Gap 1 — S3 inputs bypass validation and don't trigger Batch routing
**File:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

`_is_path_param()` explicitly skips `s3://` values → they pass through `_validate_input_paths()` with zero checking.
`_validate_s3_url()` is called only for `outdir` (line 1016), never for input params.
The auto-upgrade to `awsbatch` only fires when `outdir` starts with `s3://` (line 1012). If `input=s3://...` but `outdir` is local, executor stays `local` — local Nextflow cannot reliably stage from S3.

Failure mode: job submits to Batch, EC2 instance spins up, Nextflow tries to stage a missing or inaccessible S3 input → FAILED 5 minutes later with opaque error.

### Gap 2 — S3 outputs not retrievable by frontend
**File:** `frontend/server/routes.ts` — `addRuntimeArtifactOutputs()`, download endpoint

`createReadStream(localPath)` is used for all output downloads. When `outdir` is `s3://...`, Nextflow publishes there and no local copy exists. `fs.stat("s3://...")` fails → outputs silently absent from UI.

### Gap 3 — Frontend upload → workflow param wiring missing
**File:** `frontend/server/routes.ts` — presigned upload endpoints (`POST /api/s3/upload/init`)

Presigned PUT upload stores files at `users/{userId}/{filename}` in S3 and returns the key. Nothing injects that key back into `params.input` (or `params.reads`, `params.movies_path`, etc.) before `/api/nextflow/execute` is called. User uploads a FASTQ → key sits unused in S3 → workflow runs with no input.

### Gap 4 — Mixed s3:// inputs + local outdir on awsbatch is broken
If any input is `s3://` and outdir stays local (e.g., `/tmp/nextflow_runs/.../output`), Nextflow's `publishDir` tries to copy from Batch containers' S3 workDir to a local path that the containers cannot reach. Must ensure outdir is also S3 when inputs are S3.

---

## Implementation Plan

### Stream A — Backend (Python, `nextflow_executor.py`)

#### A1: Validate S3 input paths pre-flight
In `_validate_input_paths()`, after the local-path loop, add:
```python
for key, value in params.items():
    if key == "outdir":
        continue
    if isinstance(value, str) and value.startswith("s3://"):
        _validate_s3_url(value)   # head_object check — fast, <100ms
```
Fail fast with 422 if bucket unreachable or object missing (boto3 `head_object`).

#### A2: Auto-upgrade executor when any input is S3
In the execute endpoint, after the existing `is_s3` outdir check, add:
```python
s3_inputs = [v for v in params.values() if isinstance(v, str) and v.startswith("s3://") and v != params.get("outdir","")]
has_s3_input = bool(s3_inputs)

if has_s3_input and not compute.get("executor"):
    compute["executor"] = "awsbatch"
    log.info("[Nextflow] S3 input detected — auto-selecting AWS Batch executor")
```

#### A3: Auto-set S3 outdir when inputs are S3 but outdir is local
```python
if has_s3_input and not is_s3:
    # Derive bucket from first S3 input; put outputs alongside inputs
    s3_bucket_from_input = s3_inputs[0].split("/")[2]
    effective_outdir = f"s3://{s3_bucket_from_input}/nextflow/outputs/{run_id}"
    is_s3 = True
    compute["s3_bucket"] = s3_bucket_from_input
    log.info(f"[Nextflow] Auto-setting S3 outdir: {effective_outdir}")
    params["outdir"] = effective_outdir
```

### Stream B — Backend (Python) — S3 output retrieval

#### B1: S3 output lister after job completion
After job status transitions to `succeeded`, in `_stream_logs()` callback:
```python
if is_s3_outdir:
    s3_files = _list_s3_output_files(outdir)   # boto3 list_objects_v2
    with _runs_lock:
        _runs[run_id]["s3_output_files"] = s3_files
```

`_list_s3_output_files(s3_uri)` → returns list of `{key, size, name, extension}`.

#### B2: Status endpoint returns S3 file list
`GET /api/nextflow/status/{run_id}` response adds:
```json
"s3_output_files": [
  {"key": "s3://biomate-nextflow-work/nextflow/outputs/abc/results.vcf", "name": "results.vcf", "size": 12345}
]
```

#### B3: Presigned download endpoint
New route: `GET /api/nextflow/outputs/download?key=s3://...&run_id=...`

```python
import boto3
s3 = boto3.client("s3", region_name="us-west-2")
# Verify key belongs to this run's outdir (auth guard)
url = s3.generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": key}, ExpiresIn=900)
return RedirectResponse(url)   # 302 → browser fetches directly from S3
```

### Stream C — Frontend (TypeScript, `routes.ts`)

#### C1: Wire S3 output files to the download UI
In `addRuntimeArtifactOutputs()`, if `nextflowStatus.s3_output_files` exists:
```typescript
for (const f of nextflowStatus.s3_output_files) {
  await storage.addOutput({
    invocationId,
    name: f.name,
    extension: f.extension,
    size: f.size,
    fileType: inferFileType(f.name),
    metadata: { s3Key: f.key, source: "nextflow_s3_output" }
  })
}
```

In the download endpoint:
```typescript
if (output.metadata?.s3Key) {
  const url = await fetch(`/api/nextflow/outputs/download?key=${encodeURIComponent(output.metadata.s3Key)}`)
  return res.redirect(url)
}
```

#### C2: Upload → param injection API
New route: `POST /api/workflow/resolve-inputs`

Request: `{ workflowPath: string, uploadedFiles: Array<{s3Key: string, originalName: string}> }`
Response: `{ params: Record<string, string> }` — maps S3 keys to the correct param names

Implementation: read the workflow's `main.nf`, parse `params.input`, `params.reads`, `params.movies_path` etc. from param declarations. Match uploaded files to params by file extension + param name heuristics. Return `{ "input": "s3://bucket/users/abc/reads.fastq.gz" }`.

#### C3: Upload flow in `chat-interface.tsx`
After file upload completes:
1. Call `POST /api/workflow/resolve-inputs` with the S3 key + current workflow path
2. Merge returned params into the pending workflow's parameter set
3. Update the pending review viewer to show the resolved input paths

---

## Execution Order

**Do first (unblocks real Batch runs):**
1. A1 — S3 input validation (30 min)
2. A2 — auto-upgrade executor (20 min)
3. A3 — auto-set S3 outdir (20 min)
4. B1/B2 — S3 output lister + status endpoint (45 min)
5. B3 — presigned download endpoint (30 min)
6. C1 — wire S3 outputs to download UI (30 min)

**Do second (completes upload flow):**
7. C2 — resolve-inputs API (45 min)
8. C3 — upload → param injection in chat-interface (45 min)

---

## Verification Criteria

| Check | Expected |
|---|---|
| Pass `input=s3://biomate-nextflow-work/missing.fastq` | 422 error before job starts: "S3 object not found" |
| Pass `input=s3://...` with no outdir | executor auto-set to `awsbatch`; outdir auto-set to `s3://...` |
| Real Batch job completes | `GET /api/nextflow/status/{run_id}` returns `s3_output_files` array |
| Click download on S3 output | 302 redirect to presigned URL; file downloads in browser |
| Upload FASTQ, click "Confirm & Run" | `params.input` = S3 key of uploaded file |
