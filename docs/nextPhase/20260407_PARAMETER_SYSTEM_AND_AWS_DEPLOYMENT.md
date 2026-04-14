# Parameter System + AWS Deployment Guide — 2026-04-07

## Part 1: Work completed this session

### 1.1 What was broken

When a user clicked **Browse** next to a Nextflow file parameter (e.g. `receptor`, `ligand`, `input_csv`), the `GalaxyDatasetBrowser` returned a bare **Galaxy dataset ID** — a UUID-like string such as `abc123def456`. Nextflow cannot use that. It needs either:

- An **absolute file path**: `/home/.../data/uploads/uuid.pdb`
- An **S3 URI**: `s3://bucket/key.pdb`
- An **HTTP/HTTPS/FTP URL** (Nextflow fetches these automatically with `--remote`)

As a result, every Nextflow workflow with file-type parameters was effectively broken — users could browse and select files but the param value written to the Nextflow config was a string that Nextflow silently rejected.

Additionally, the parameter UI had several secondary bugs:
- Output directory params (`format: directory-path` in JSON Schema) were opening the dataset browser instead of rendering as a plain text field
- Session-uploaded datasets were not shown in the "This session" tab of the browser (the `sessionDatasets` prop was never populated)
- Galaxy history datasets had no resolution path at all

### 1.2 What was fixed

#### Backend — `frontend/server/routes.ts`

**1. Upload handler stores `file_path`**

`POST /api/datasets/upload` now saves `file_path` (the absolute local path on disk) into `req.session.uploadedDatasets` alongside the existing fields. Previously this was returned in the HTTP response but not persisted in the session.

```ts
req.session.uploadedDatasets.push({
  ...existing fields...
  file_path: file.path,  // NEW — e.g. /home/.../data/uploads/uuid.pdb
});
```

**2. URL import handler stores `source_url`**

`POST /api/datasets/import-url` now saves `source_url` (the original HTTP/S3/FTP URL) in the session. Nextflow can fetch HTTP/S3 URLs directly, so the URL itself is a valid param value.

**3. New endpoint: `GET /api/datasets/session`**

Returns all session-uploaded datasets with their resolved paths:

```json
{
  "datasets": [
    {
      "id": "dataset-uuid",
      "galaxy_dataset_id": "galaxy-id",
      "name": "receptor.pdb",
      "file_type": "application/octet-stream",
      "file_size": 142380,
      "file_path": "/home/.../data/uploads/uuid.pdb",
      "source_url": null
    }
  ]
}
```

**4. New endpoint: `GET /api/galaxy/datasets/:id/resolve`**

Resolves a Galaxy history dataset ID to a local file path usable by Nextflow:
1. Checks session cache first (fast path)
2. Calls `getDatasetMetadata(id)` for extension + name
3. Streams `downloadDataset(id)` → writes to `data/uploads/{id}.{ext}`
4. Caches the local path in session
5. Returns `{ file_path, name }`

Subsequent calls for the same dataset skip the download and return immediately.

#### Backend — `backend/lib/galaxy/ai/ai_assistant.py`

**5. `directory-path` format → `string` type**

`_schema_type_to_param_type()` previously mapped `format: directory-path` to `file`, causing output directory params to open the dataset browser. Fixed:

```python
if fmt == 'file-path' or param_def.get('mimetype'):
    return 'file'
if fmt in ('directory-path', 'path'):
    return 'string'   # output dirs are plain text fields
```

#### Frontend — `nextflow-workflow-viewer.tsx`

**6. Viewer fetches session datasets on mount**

```ts
useEffect(() => {
  fetch('/api/datasets/session')
    .then(r => r.ok ? r.json() : { datasets: [] })
    .then(data => setSessionDatasets(data.datasets || []))
    .catch(() => {});
}, []);
```

**7. `GalaxyDatasetBrowser` receives real file paths**

`sessionDatasets` prop is now populated with `path` set to `file_path || source_url`. The existing `SessionTab` component already uses `ds.path` as the value when available (line 98), so session-uploaded files now return their local path, not a Galaxy ID.

**8. Async ID resolution in `onSelect`**

When the selected value looks like a bare Galaxy ID (no `/` or `://`), the viewer automatically calls the resolve endpoint before writing the param:

```ts
onSelect={async (value, name) => {
  let resolved = value;
  if (value && !value.includes('/') && !value.includes('://')) {
    const r = await fetch(`/api/galaxy/datasets/${encodeURIComponent(value)}/resolve`);
    if (r.ok) resolved = (await r.json()).file_path || value;
  }
  handleParamChange(browsingForParam.id, resolved);
}}
```

#### Session type — `frontend/server/types/session.d.ts`

`SessionData.uploadedDatasets` extended with `file_path?: string` and `source_url?: string`.

---

### 1.3 Other work completed this session (parameter system redesign)

See also: `docs/nextPhase/20260406_PARAMETER_SYSTEM_REDESIGN.md`

- **18 `nextflow_schema.json` files** generated for all drug discovery workflows under `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/`. Each schema encodes: required file inputs, `enum` selects with clinical justification, integer/float params with `minimum`/`maximum`, boolean toggles.
- **AI parameter pre-filling (Layer 2)**:
  - `_apply_parameter_hints()` — applies DB-driven `tool_knowledge` hints as `autoFilled: true` + rationale
  - `_infer_params_from_intent_llm()` — Haiku call that infers param values from user's natural language query (e.g. "37°C" → `temperature: 310`, "XP precision" → `docking_precision: "XP"`)
  - Both wired into `_return_nextflow_match` so every workflow response carries pre-filled suggestions

---

## Part 2: AWS deployment — required changes

### 2.1 The core problem: local paths don't work on AWS Batch

In development, the app server and Nextflow executor run on the same machine. `file_path` like `/home/yzhang/biomate/frontend/data/uploads/uuid.pdb` is readable by both.

On AWS:
- **App server** runs on ECS (container) or EC2
- **Nextflow executor** runs on **AWS Batch** (separate EC2 workers in a different VPC subnet)
- AWS Batch workers **cannot read the app server's local filesystem**

Every `file_path` param value that works locally will silently fail on AWS Batch.

**The fix**: uploaded files must go to **S3** first. Nextflow params must use `s3://` URIs.

### 2.2 File upload path — current vs AWS

| Step | Current (dev) | AWS (required) |
|------|--------------|----------------|
| User uploads file | multer saves to `data/uploads/uuid.ext` | multer saves to `data/uploads/uuid.ext` (temp) |
| After local save | nothing | upload to `s3://{UPLOAD_BUCKET}/uploads/{session_id}/uuid.ext` |
| Value stored in session | `file_path: /abs/local/path` | `file_path: s3://bucket/uploads/session/uuid.ext` |
| Nextflow param value | `/abs/local/path` | `s3://bucket/uploads/session/uuid.ext` |
| Batch worker access | reads local disk | reads from S3 (built-in Nextflow support) |

**Code change needed** in `routes.ts` upload handler — after multer saves locally, upload to S3 and update `file_path`:

```ts
// After local save in the upload handler:
if (process.env.AWS_UPLOAD_BUCKET) {
  const s3Key = `uploads/${req.session.id}/${datasetId}${path.extname(file.originalname)}`;
  await s3.putObject({
    Bucket: process.env.AWS_UPLOAD_BUCKET,
    Key: s3Key,
    Body: createReadStream(file.path),
  }).promise();
  const s3Uri = `s3://${process.env.AWS_UPLOAD_BUCKET}/${s3Key}`;
  // Use S3 URI as the file_path stored in session
  sessionEntry.file_path = s3Uri;
}
```

New env var required: `AWS_UPLOAD_BUCKET` (separate from the Nextflow work bucket).

### 2.3 Galaxy dataset resolve — local download vs S3

The `GET /api/galaxy/datasets/:id/resolve` endpoint currently downloads from Galaxy into `data/uploads/` and returns the local path. On AWS Batch, that local path is unreachable.

**Code change needed**: after downloading from Galaxy, upload to S3 and return S3 URI instead of local path.

```ts
if (process.env.AWS_UPLOAD_BUCKET) {
  const s3Key = `galaxy-downloads/${datasetId}${ext}`;
  await s3.putObject({ Bucket: ..., Key: s3Key, Body: fileContent }).promise();
  return res.json({ file_path: `s3://${process.env.AWS_UPLOAD_BUCKET}/${s3Key}`, name: ... });
}
```

### 2.4 URL-imported datasets

No code change needed. URLs (HTTP, HTTPS, S3) are already stored as `source_url` and Nextflow reads them natively. The only caveat: S3 URLs require the Batch execution role to have `s3:GetObject` on the source bucket.

### 2.5 Session storage — Redis

| | Dev | AWS |
|--|-----|-----|
| Redis | `localhost:6379` | ElastiCache (Redis Cluster mode off, single-AZ is fine unless HA needed) |
| `REDIS_URL` | `redis://localhost:6379` | `redis://{elasticache-endpoint}:6379` |

Session data (uploaded datasets, Galaxy history ID) is stored in Redis. Multi-instance ECS requires shared session store — this is already the architecture (`RedisStore` is used). Just point `REDIS_URL` at ElastiCache.

### 2.6 PostgreSQL — user database

| | Dev | AWS |
|--|-----|-----|
| DB | `localhost:5432` | RDS PostgreSQL (db.t4g.medium minimum; db.r7g.large for production) |
| `DATABASE_URL` | `postgresql://biomate:...@localhost:5432/biomate_dev` | `postgresql://biomate:{pwd}@{rds-endpoint}:5432/biomate` |

Run `npm run db:push` (Drizzle migrations) against the RDS instance on first deploy.

### 2.7 Galaxy server

| | Dev | AWS |
|--|-----|-----|
| Galaxy | `localhost:8081` | EC2 instance (m6i.xlarge minimum) or dedicated Galaxy CloudLaunch |
| `GALAXY_URL` | `http://localhost:8081` | `http://{galaxy-ec2-private-ip}:8081` (keep in private subnet) |
| `GALAXY_API_KEY` | dev key | provisioned per-user key (already implemented via `provisionGalaxyUser`) |

Galaxy is stateful (stores datasets, histories) — it should **not** be containerized without persistent EBS/EFS for its database and file store.

### 2.8 Nextflow executor — already AWS-ready

`NEXTFLOW_USE_AWS=true` is already set in `backend/.env`. The executor:
- Submits to `AWS_BATCH_QUEUE`
- Uses `AWS_S3_BUCKET` as the Nextflow work dir (`-w s3://...`)
- Sets `params.outdir = s3://...` for outputs

No code change needed here. The only gap is file param values (see §2.2).

### 2.9 SQLite tool knowledge DB

The `DATABASE_PATH=./galaxy_ai_tools.db` SQLite file contains the tool knowledge index (use cases, parameter hints) and workflow FTS index. 

**Recommendation**: keep on the instance/container but build into the Docker image or copy from S3 on startup. It's read-only at runtime. Do not migrate to RDS — it's a read-only knowledge base, not transactional user data.

```dockerfile
# In Dockerfile (backend)
COPY galaxy_ai_tools.db /app/galaxy_ai_tools.db
ENV DATABASE_PATH=/app/galaxy_ai_tools.db
```

Or on ECS, mount from S3 via `aws s3 cp s3://{bucket}/galaxy_ai_tools.db /app/` in the container entrypoint.

### 2.10 Anthropic API key

`ANTHROPIC_API_KEY` is currently a real key in `frontend/.env`. On AWS:
- Store in **AWS Secrets Manager** or **Parameter Store** (SecureString)
- Inject into ECS task definition as an environment variable via `secrets:` field
- Never commit to source or bake into the Docker image

### 2.11 `data/uploads/` directory on ECS

ECS containers are ephemeral. The `data/uploads/` dir used by multer for temporary local storage must either:

**Option A (simpler)**: Mount an **EFS volume** at `/app/data/uploads`. All ECS tasks share the same filesystem. Works for single-region deployments.

**Option B (recommended)**: Use multer's memory storage (`storage: multer.memoryStorage()`) and upload directly to S3 without touching disk. The local file is only needed for:
  1. Galaxy upload (which streams from `file.path`)
  2. The local file_path value

With memory storage, stream `req.file.buffer` to both Galaxy and S3. Return the S3 URI as `file_path`.

### 2.12 JWT and session secrets

| Secret | Dev value | AWS requirement |
|--------|-----------|----------------|
| `JWT_SECRET` | `a1b2c3...` | 256-bit random, stored in Secrets Manager |
| `SESSION_SECRET` | not set (warning logged) | 256-bit random, stored in Secrets Manager |
| `BILLING_INTERNAL_KEY` | hardcoded | Secrets Manager |

### 2.13 Complete AWS environment variable diff

Variables that need to change value (not necessarily new variables):

```bash
# Database
DATABASE_URL=postgresql://biomate:{pwd}@{rds-endpoint}.{region}.rds.amazonaws.com:5432/biomate

# Cache/Sessions
REDIS_URL=redis://{elasticache-endpoint}.{region}.cache.amazonaws.com:6379

# Galaxy
GALAXY_URL=http://{galaxy-private-ip}:8081
GALAXY_API_URL=http://{galaxy-private-ip}:8081

# File uploads (NEW)
AWS_UPLOAD_BUCKET=biomate-user-uploads  # separate from nextflow work bucket

# Nextflow (already set)
NEXTFLOW_USE_AWS=true
AWS_BATCH_QUEUE=biomate-nextflow-queue
AWS_S3_BUCKET=biomate-nextflow-work
AWS_DEFAULT_REGION=us-west-2

# App
NODE_ENV=production
APP_URL=https://app.biomate.ai
PORT=5000

# Secrets (rotate all dev values)
JWT_SECRET={256-bit-random}
SESSION_SECRET={256-bit-random}
ANTHROPIC_API_KEY={from-secrets-manager}
STRIPE_SECRET_KEY={from-secrets-manager}
```

### 2.14 Required code changes summary for AWS

| File | Change | Why |
|------|--------|-----|
| `frontend/server/routes.ts` | After local upload, if `AWS_UPLOAD_BUCKET` set: upload to S3 and use S3 URI as `file_path` | Nextflow Batch workers can't read app server filesystem |
| `frontend/server/routes.ts` | Galaxy dataset resolve: if `AWS_UPLOAD_BUCKET` set: upload download to S3, return S3 URI | Same reason |
| `frontend/server/routes.ts` | Consider multer memory storage to avoid EFS dependency | Simpler containerization |
| `backend/.env` (ECS) | All secrets from Secrets Manager, DB/Redis/Galaxy pointing at managed services | Production hardening |
| Docker/ECS task def | Mount EFS at `data/uploads/` OR switch to memory storage + S3 | Ephemeral container storage |

### 2.15 Infrastructure checklist for AWS launch

- [ ] RDS PostgreSQL provisioned, `npm run db:push` applied
- [ ] ElastiCache Redis provisioned, `REDIS_URL` updated
- [ ] EC2 Galaxy instance running, private IP noted, per-user provisioning tested
- [ ] S3 bucket `biomate-user-uploads` created (lifecycle: delete objects > 7 days)
- [ ] S3 bucket `biomate-nextflow-work` created (lifecycle: delete objects > 30 days)
- [ ] S3 bucket `biomate-structure-db` populated (AlphaFold human proteome, one-time build)
- [ ] AWS Batch: compute environment + job queue `biomate-nextflow-queue` created
- [ ] ECS cluster + service + task definition for app server
- [ ] ECS task IAM role: `s3:GetObject/PutObject` on upload + work buckets; `batch:SubmitJob`
- [ ] ALB + ACM certificate for `app.biomate.ai`
- [ ] Secrets Manager entries for all secrets
- [ ] Upload handler S3 bridge code (§2.2) implemented and tested
- [ ] Galaxy dataset resolve S3 bridge code (§2.3) implemented and tested
- [ ] `SESSION_SECRET` set (currently unset — warning logged in dev)
- [ ] LAGO billing URL updated from `localhost:3010` to production Lago instance
- [ ] CryoSPARC SSH key distributed to ECS task via Secrets Manager
