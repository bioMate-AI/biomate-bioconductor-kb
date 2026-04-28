# BioMate Platform — Infrastructure & Information Flow

**Date:** 2026-04-22  
**Branch:** integration/next-phase  
**Audience:** Engineers, DevOps, On-call

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Infrastructure Map](#2-infrastructure-map)
3. [User Journey & Information Flow](#3-user-journey--information-flow)
4. [Frontend Architecture](#4-frontend-architecture)
5. [Node.js Server Layer](#5-nodejs-server-layer)
6. [Galaxy Python Backend](#6-galaxy-python-backend)
7. [Nextflow Executor Internals](#7-nextflow-executor-internals)
8. [AWS Batch & CryoSPARC Execution](#8-aws-batch--cryosparc-execution)
9. [Billing & Cost Tracking](#9-billing--cost-tracking)
10. [Logging & Monitoring](#10-logging--monitoring)
11. [Alerting & What to Monitor](#11-alerting--what-to-monitor)
12. [Incident Runbook](#12-incident-runbook)
13. [Draw.io Diagrams (XML)](#13-drawio-diagrams-xml)

---

## 1. System Overview

BioMate is an AI-driven bioinformatics platform where users describe experiments in natural language and the system routes them to the correct pipeline, launches it on cloud infrastructure, and streams live results back.

### What the User Sees

```
┌─────────────────────────────────────────────────────────┐
│  Chat panel (left)          │  Workflow panel (right)   │
│                             │                           │
│  User: "Run SPA on my       │  [Phase A] Motion Corr ✔ │
│   20 EMPIAR movies"         │  [Phase B] CTF Est     ✔ │
│                             │  [Phase C] 2D Class    ✔ │
│  AI: "I'll run CryoSPARC    │  [Phase D] Ab Initio   ⏳│
│   Standard SPA. Starting    │  [Phase E] Refinement  ─ │
│   now..."                   │                           │
│                             │  Progress: 80%  ETA: 45m │
│                             │  [Download outputs]       │
└─────────────────────────────────────────────────────────┘
```

### What the Tech Sees

```
EC2 (Galaxy container) → Nextflow process → AWS Batch jobs → CryoSPARC EC2
     gunicorn:8080           /tmp/nf/          GPU queues       3.88.225.107
     port 8081 external      work_dir/
```

---

## 2. Infrastructure Map

### Services & Their Locations

| Service | Host | Port | Notes |
|---------|------|------|-------|
| Frontend (Node.js + Vite) | EC2 `52.42.49.175` | 5000 | Express + React |
| Galaxy backend (gunicorn) | Docker `28af3ce133ca` on same EC2 | 8080 (internal), 8081 (host) | Python FastAPI |
| CryoSPARC instance | EC2 `3.88.225.107` | 30000 | us-east-1, L4 GPU |
| AWS Batch (CPU queue) | `biomate-nextflow-queue` | — | us-west-2 |
| AWS Batch (GPU queue) | `galaxy-cloud-queue-gpu` | — | us-west-2 |
| S3 work dir | `s3://biomate-nextflow-work` | — | us-west-2 |
| S3 outputs | `s3://biomate-nextflow-work/nextflow/outputs/` | — | |
| Lago (billing metering) | EC2 `35.86.137.71` | 3000 | us-west-2 |
| Java billing service | EC2 `35.86.137.71` | 8080 | us-west-2 |
| Redis (billing cache) | `biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com` | 6379 | ElastiCache |
| PostgreSQL (app DB) | local in Docker | 5432 | chat sessions, users |

### Network Topology

```
Internet
    │
    ▼
EC2 52.42.49.175  (us-west-2a, i-06696b0d91f4346e0)
├── :5000  Node.js (public)
├── :8081  Galaxy gunicorn (public — only curl from host, not internet)
│
└── Docker: biomate-galaxy-dev (28af3ce133ca)
    ├── :8080 gunicorn (mapped → host:8081)
    └── /tmp/nextflow_runs/<run_id>/work/   ← Nextflow CWD + cache

AWS Batch (us-west-2)
├── biomate-nextflow-queue       (CPU: m6i.xlarge)
└── galaxy-cloud-queue-gpu       (GPU: g4dn, g5, L4 instances)

CryoSPARC EC2 (us-east-1, 3.88.225.107)
└── :30000 CryoSPARC web UI + API
    └── /home/ubuntu/biomate_movies/  ← raw movie files

S3 (us-west-2)
└── biomate-nextflow-work/
    ├── nextflow/work/<user>/<run_id>/   ← Nextflow task work dirs (cache)
    └── nextflow/outputs/<user>/<run_id>/  ← final outputs
```

---

## 3. User Journey & Information Flow

### Full Request Lifecycle (CryoSPARC SPA Example)

```
User types message
       │
       ▼
[Browser] POST /api/biomate/chat  →  SSE stream opens
       │
       ▼
[Node.js routes.ts]
  authenticateToken (JWT)
  checkBillingQuota
  → galaxy-assistant.ts::streamChat()
       │
       ▼
[Node.js galaxy-assistant.ts]
  Phase 0: Gemini Flash intent classifier
    → detects "cryo-EM SPA" intent
  Phase 1: Workflow search
    → POST /api/ai_assistant/search_ranked (Galaxy proxy)
    → BGE dense retrieval + FTS on 2,455 workflows
    → returns top-5 candidates
  Phase 2: Claude Sonnet 4.6 generation
    → system prompt: domain knowledge + tool context
    → memory injection: past episodes + corrections
    → streams tokens back to client via SSE
    → emits workflow_ga JSON artifact in message
       │
       ▼
[Browser] Receives SSE tokens, renders chat bubble
  → workflow artifact detected in message.metadata
  → right panel auto-opens
  → WorkflowViewer renders with params pre-filled
       │
User clicks "Run"
       │
       ▼
[Browser] POST /api/workflows/execute
  {workflowPath, parameters, chatSessionId, invocationId}
       │
       ▼
[Node.js routes.ts] /api/workflows/execute
  → detect execution engine (nextflow / galaxy)
  → POST http://localhost:8081/api/nextflow/execute
       │
       ▼
[Galaxy nextflow_executor.py] execute_nextflow()
  1. Resolve .nf path  →  /app/biomni_workflows/...main.nf
  2. Inject env vars: CRYOSPARC_HOST, CRYOSPARC_LICENSE, AWS creds
  3. Copy .nextflow/ cache if resume_from_run_id set
  4. Build Nextflow CLI:
       nextflow run main.nf -profile awsbatch -resume \
         -w s3://biomate-nextflow-work/nextflow/work/<user>/<run_id>/
  5. Popen(cmd, start_new_session=True)  ← detached from gunicorn
  6. Register in _runs[run_id]
  7. Return {run_id, status: "running"}
       │
       ▼
[Galaxy background thread] _stream_logs()
  tails Nextflow stdout → strips ANSI
  writes to _runs[run_id]['log_tail']  (last 100 lines)
  on exit: writes completed_at, returncode to timing.json
       │
       ▼
[AWS Batch] receives job submissions from Nextflow
  CPU tasks  → biomate-nextflow-queue
  GPU tasks  → galaxy-cloud-queue-gpu
  Each task:
    pulls ECR container image
    mounts S3 work dir via s3fs or aws s3 cp
    runs .command.sh
    uploads outputs + .exitcode to S3
    Nextflow polls until SUCCEEDED/FAILED
       │
       ▼
[CryoSPARC tasks] (SPA pipeline)
  Batch container uses cryosparc-tools Python SDK
  Authenticates: CryoSPARC(license=..., host=..., base_port=30000)
  Creates/runs jobs: import_movies, patch_motion, class_2D, homo_abinit, ...
  Outputs written to CryoSPARC project on 3.88.225.107
       │
       ▼
[Browser] polls GET /api/workflows/runs/:id  every 10s
  Node.js → GET http://localhost:8081/api/nextflow/status/<run_id>
  Galaxy reads _runs dict OR timing.json (post-restart)
  Returns: {status, completedTasks, totalTasks, progressPercent, processes[], log_tail[]}
  WorkflowViewer updates phase cards, progress bar, logs
       │
       ▼
[On completion] Galaxy executor:
  lists S3 outputs → generates presigned URLs (1hr expiry)
  writes billing event → Lago
  tags S3 objects with run_id/user_id
[Browser] shows download buttons, findings card
```

---

## 4. Frontend Architecture

### Key Files

| File | Purpose |
|------|---------|
| `frontend/client/src/components/chat-with-artifacts.tsx` | Root: chat + right panel, run lifecycle |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Phase visualization, progress bar, logs |
| `frontend/client/src/components/phase-card.tsx` | Per-phase card: status, files, param overrides |
| `frontend/client/src/components/chat-message.tsx` | Individual message bubbles, workflow artifacts |
| `frontend/client/src/components/chat-interface.tsx` | Input box, send, file upload trigger |
| `frontend/client/src/components/findings-card.tsx` | AI analysis of run outputs |
| `frontend/client/src/styles/workflow-panel.css` | Panel layout, phase card styles |
| `frontend/server/routes.ts` | All 110+ HTTP endpoints |
| `frontend/server/galaxy-assistant.ts` | Claude + Gemini agentic loop |

### State Machine (WorkflowViewer)

```
idle → pending → running → completed
                        ↘ failed
                        ↘ paused → running (resume)
```

- `status` comes from `/api/workflows/runs/:id` (polled every 10s)
- `progressPercent` drives the progress bar (hidden when 0)
- `processes[]` drives phase card status icons
- `log_tail[]` streams into the log panel

### What Users See Per Status

| Status | Progress bar | Phase cards | Log pane | Buttons |
|--------|-------------|-------------|----------|---------|
| `pending` | hidden | all gray | "starting…" | Cancel |
| `running` (0 tasks) | hidden | all gray | "Waiting for logs…" | Cancel, Pause |
| `running` (tasks > 0) | shown | colored per phase | live lines | Cancel, Pause |
| `paused` | shown (frozen) | colored | static | Resume, Cancel |
| `completed` | 100% | all green | final lines | Download, Rerun |
| `failed` | red | failed phase red | error lines | Resume, Rerun |

**Known UX gap:** During Nextflow S3 cache scan (2–5 min), `totalTasks=0` → progress bar hidden, users see "Waiting for logs…". Consider adding "Scanning workflow cache…" indicator when `status=running` AND `totalTasks=0` AND elapsed > 30s.

---

## 5. Node.js Server Layer

### Route Groups

```
/api/biomate/chat             SSE streaming chat
/api/workflows/*              execution, runs, outputs, findings
/api/nextflow/*               Nextflow-specific (steps, status proxy)
/api/invocations/*            Galaxy invocation proxy
/api/ai_assistant/*           search, generate, ranked search
/api/datasets/*               upload, import-url, download
/api/billing/*                usage, quota, lago status
/api/internal/billing/*       LLM cost events (internal key required)
/api/memory/*                 user episodes, corrections
/api/sessions/*               chat session CRUD
/api/admin/*                  audit log, invite codes, index health
/api/qc/*                     QC profiles, gate events
```

### Middleware Stack (per request)

```
Request
  → CORS
  → auditMiddleware (logs all requests to DB)
  → authenticateToken | optionalAuth
  → checkBillingQuota (for execution routes)
  → route handler
  → auditService.recordResponse (on completion)
Response
```

### Galaxy Proxy Pattern

All Galaxy API calls from Node.js:
```typescript
const resp = await galaxyProxy.post('/api/nextflow/execute', body, {
  headers: { 'X-API-Key': user.galaxyApiKey }
});
```
- Uses user's personal Galaxy API key (stored in PostgreSQL)
- E2E test bypass: `X-E2E-Test-Token: biomate-e2e-test-bypass-2024` skips auth

### SSE Pattern (Chat Streaming)

```
Client: GET /api/biomate/chat?...
Server: Content-Type: text/event-stream
        Cache-Control: no-cache
        Connection: keep-alive

Events:
  data: {"type":"token","content":"I'll run..."}
  data: {"type":"workflow","workflow_ga":{...}}
  data: {"type":"done"}
  data: {"type":"error","message":"..."}
```

---

## 6. Galaxy Python Backend

### Process Model

```
Docker container (biomate-galaxy-dev)
└── supervisord
    └── gunicorn (master)
        ├── worker 1 (Python 3.9, FastAPI/Uvicorn)
        ├── worker 2
        └── worker N
            ↓ spawns (detached, start_new_session=True)
            nextflow subprocess (PID in own session)
                ↓ submits
                AWS Batch jobs (independent)
```

**Critical:** `start_new_session=True` in both Popen calls in `nextflow_executor.py` (~lines 2061, 2570) ensures Nextflow survives gunicorn worker restarts. Batch jobs always survive container restarts (run independently on Batch EC2).

### In-Memory State (`_runs` dict)

```python
_runs: Dict[str, {
    'status': str,           # running | completed | failed | paused
    'process': Popen,        # subprocess handle (None after restart)
    'nextflow_path': str,    # .nf file path
    'work_dir': str,         # /tmp/nextflow_runs/<run_id>/work or S3
    'is_batch': bool,
    'user_id': str,
    'log_tail': List[str],   # last 100 log lines
    'processes': List[dict], # per-task status from trace
    'completedTasks': int,
    'totalTasks': int,
    'progressPercent': float,
    'started_at': float,
    'completed_at': float,   # set on exit
}]
```

**After gunicorn restart:** `_runs` is empty. Status endpoint reads from:
1. `timing.json` in run dir → `completed_at`, `returncode`
2. `nextflow.log` → recent log lines
3. `workflow-trace.txt` → task-level statuses

### CryoSPARC Credential Injection

In `execute_nextflow()` (~line 2264):
```python
env['CRYOSPARC_LICENSE']  = os.environ.get('CRYOSPARC_LICENSE', '')
env['CRYOSPARC_HOST']     = os.environ.get('CRYOSPARC_HOST', '3.88.225.107')
env['CRYOSPARC_PORT']     = os.environ.get('CRYOSPARC_PORT', '30000')
env['CRYOSPARC_EMAIL']    = os.environ.get('CRYOSPARC_EMAIL', 'admin@biomate.ai')
env['CRYOSPARC_PASSWORD'] = os.environ.get('CRYOSPARC_PASSWORD', '')
```
These are forwarded to every Batch task via the Nextflow AWS Batch config's `jobEnvironment`.

### Key API Endpoints (Galaxy)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/nextflow/execute` | Launch Nextflow pipeline |
| GET | `/api/nextflow/status/{run_id}` | Poll status + logs |
| POST | `/api/nextflow/resume/{run_id}` | Resume with -resume, copy .nextflow cache |
| GET | `/api/nextflow/steps` | Parse .nf file → phase structure |
| GET | `/api/nextflow/runs/{run_id}/output_files` | List S3 outputs with presigned URLs |
| POST | `/api/ai_assistant/generate_workflow` | AI workflow generation |
| POST | `/api/ai_assistant/search_ranked` | BGE + FTS workflow search |
| GET | `/api/nextflow/findings/{run_id}` | AI analysis of outputs |
| POST | `/internal/billing/llm_cost` | Record LLM token cost |
| POST | `/internal/billing/job_completed` | Record Batch job cost |

---

## 7. Nextflow Executor Internals

### Work Directory Structure

```
/tmp/nextflow_runs/<run_id>/
├── nextflow.log              ← Nextflow progress display (tail for status)
├── workflow-trace.txt        ← TSV: task_id, name, status, duration, CPU, mem
├── timing.json               ← {started_at, completed_at, returncode}
├── biomate_executor_override.config  ← generated Nextflow config
└── work/
    ├── .nextflow/            ← MUST be here for -resume to work
    │   ├── cache/            ← task hash → S3 output mapping
    │   ├── history           ← run history file
    │   └── plr/              ← pipeline log records
    └── ab/cdef123.../        ← local task work dirs (or S3-backed)
        ├── .command.sh
        ├── .command.log
        ├── .command.err
        └── .exitcode
```

**S3 task work dirs** (Batch mode):
```
s3://biomate-nextflow-work/nextflow/work/<user>/<run_id>/<ab>/<cdef.../
├── .command.sh
├── .command.log
├── .command.err
├── .exitcode
├── .command.trace   ← CPU/mem/wall time
└── <output files>
```

### Resume Cache Copy Logic

When `resume_from_run_id` is set:
```python
# Before work_dir created:
_src = work_base / resume_from_run_id / "work" / ".nextflow"

# After work_dir created (just before Popen):
_dest = work_dir / ".nextflow"
if _src.exists() and not _dest.exists():
    shutil.copytree(_src, _dest)
```

**Why this is needed:** Nextflow's `-resume` flag only works if `.nextflow/cache/` exists in the CWD. Without copying it, Nextflow prints "never run this project before — Option `-resume` is ignored" and re-runs all tasks.

### Status Computation Pipeline

```
GET /api/nextflow/status/{run_id}
    │
    ├── check _runs[run_id] (in-memory)
    │   ├── found + process alive → status = 'running'
    │   ├── found + returncode = 0 → status = 'succeeded'
    │   └── found + returncode ≠ 0 → status = 'failed'
    │
    ├── not found (after restart):
    │   read timing.json → completed_at present? → terminal status
    │   read nextflow.log → last 20 lines → log_tail
    │   read workflow-trace.txt → parse tasks
    │
    └── build response:
        {status, completedTasks, totalTasks, progressPercent,
         processes[], log_tail[], s3_output_files[], duration_s}
```

---

## 8. AWS Batch & CryoSPARC Execution

### Batch Job Lifecycle

```
Nextflow submits job
    │
    ▼
AWS Batch job queue (biomate-nextflow-queue or galaxy-cloud-queue-gpu)
    │
    ▼
Compute Environment scales up EC2 instance
    │
    ▼
Job runs in ECR container:
  - pulls s3://…/<task_hash>/.command.sh
  - executes task (Python, CryoSPARC SDK, etc.)
  - uploads outputs + .exitcode to S3
    │
    ▼
Nextflow TaskPollingMonitor polls Batch every 5s
    → SUCCEEDED: mark task COMPLETED, cache hash→outputs
    → FAILED: mark FAILED, trigger Nextflow error handling
```

### CryoSPARC SPA Pipeline — 25-Step Flow

| Task # | Process Name | CryoSPARC Job Type | Queue | New? |
|--------|-------------|-------------------|-------|------|
| 1 | INIT_CRYOSPARC_PROJECT | import_movies | CPU | ✅ |
| 2 | SPLIT_INTO_BATCHES | — (Python) | CPU | ✅ |
| 3 | PATCH_MOTION_CORRECTION_BATCH | patch_motion_correction_multi | CPU | ✅ |
| 4 | PATCH_CTF_ESTIMATION_BATCH | patch_ctf_estimation_multi | CPU | ✅ |
| 5 | BLOB_PICKER_BATCH | blob_picker_gpu | GPU | ✅ |
| 6 | MERGE_MICROGRAPHS | — | CPU | ✅ |
| 7 | MERGE_PARTICLES | — | CPU | ✅ |
| 8 | MICROGRAPH_DENOISER | — (mock) | CPU | ✅ |
| 9 | JUNK_2D_DETECTOR | — (mock) | CPU | ✅ |
| 10 | INSPECT_PICKS | — (mock) | CPU | ✅ |
| 11 | EXTRACT_PARTICLES_R1_BATCH | extract_micrographs_cpu_parallel | CPU | ✅ |
| 12 | MERGE_PARTICLES_R1 | — | CPU | ✅ |
| 13 | SPLIT_PARTICLE_BATCHES | — | CPU | ✅ |
| 14 | CLASSIFY_2D_R1_BATCH | class_2D | GPU | ✅ |
| 15 | MERGE_CLASSES | — | CPU | ✅ |
| 16 | SELECT_2D_R1 | — | CPU | ✅ |
| 17 | TEMPLATE_PICKER | template_picker_gpu | GPU | ✅ |
| 18 | INSPECT_PICKS_R2 | — (mock) | CPU | ✅ |
| 19 | EXTRACT_PARTICLES_R2 | extract_micrographs_cpu_parallel | CPU | ✅ |
| 20 | SPLIT_PARTICLE_BATCHES_R2 | — | CPU | ✅ |
| 21–22 | CLASSIFY_2D_R2_BATCH (×2) | class_2D | GPU | ✅ |
| 23 | MERGE_CLASSES_R2 | — | CPU | ✅ |
| 24 | SELECT_2D_R2 | — | CPU | ✅ |
| 25 | AB_INITIO_BATCH | homo_abinit | GPU | ✅ **Bug 6 fixed** |
| 26 | HOMO_REFINEMENT | homo_refine_new | GPU | ⏳ |
| 27–31 | Post-processing | validation → ctf_refine_local → nonuniform_refine_new → local_resolution → sharpen | GPU | ⏳ |

### Known CryoSPARC v5 Renames

| Process | v4 job type | v5 job type |
|---------|------------|------------|
| VALIDATION_FSC | `fsc_validation` | `validation` |
| LOCAL_CTF_REFINEMENT | `local_ctf_refinement` | `ctf_refine_local` |
| NON_UNIFORM_REFINEMENT | `non_uniform_refinement_new` | `nonuniform_refine_new` |
| LOCAL_RESOLUTION | `local_resolution_estimation` | `local_resolution` |
| SHARPEN | `sharpening_tools` | `sharpen` |
| AB_INITIO output slot | `"volume"` | `"volume_class_0"` (fallback chain in main.nf) |

---

## 9. Billing & Cost Tracking

### Three-Layer Stack

```
User action
    │
    ▼
1. LLM cost: routes.ts emits after each chat stream
   → POST /internal/billing/llm_cost
   → billing_internal.py → Redis + Lago

2. Batch job cost: nextflow_executor.py on run completion
   → POST /internal/billing/job_completed
   → CostCalculator (instance × duration) → Lago

3. S3 storage: Lambda triggered by PutObject/DeleteObject
   → POST /internal/billing/s3_put → Lago
```

### AWS Billing Stack (Production)

```
LAGO_API_URL=http://35.86.137.71:3000
LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080
JAVA_BILLING_ENABLED=true
REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
```

**Never use local Lago Docker (`localhost:3010`) for billing tests.**

---

## 10. Logging & Monitoring

### Current Log Coverage

#### Galaxy backend (`nextflow_executor.py`)

| Event | Log level | Message pattern |
|-------|-----------|----------------|
| Run start | INFO | `[Nextflow run {run_id}] Starting: {cmd}` |
| .nextflow cache copy | INFO | `Copied .nextflow cache from {prev}/work/.nextflow → work/.nextflow` |
| .nextflow cache missing | WARNING | `No .nextflow cache found for {run_id} — resume will be ignored` |
| Task completed | INFO | (via Nextflow daemon log, not Galaxy log) |
| Run exit | INFO | `[Nextflow run {run_id}] finished with exit code {returncode}` |
| Log stream error | ERROR | `[Nextflow run {run_id}] log streaming error: {exc}` |
| S3 output listing | INFO | `[Nextflow] Listed {n} S3 output files from {uri}` |
| S3 tag success | INFO | `[S3 tag] Tagged {n} output objects for run={id} user={uid}` |
| S3 tag failure | WARNING | `[S3 tag] Failed to tag s3://{bucket}/{key}: {err}` |
| Billing emit | INFO | `[billing] job_completed emitted for run {id} ({duration}s)` |
| CryoSPARC creds injected | INFO | `[Nextflow] CryoSPARC license key will be injected into Batch tasks` |
| GPU queue routing | INFO | `[Nextflow] GPU queue routing: process_gpu → {queue}` |
| Launch failed | ERROR | `[Nextflow run {run_id}] failed to launch: {exc}` |

#### Galaxy backend (`ai_assistant.py`)

| Event | Log level | Message pattern |
|-------|-----------|----------------|
| Workflow search | INFO | search query, top-5 results |
| Model call | DEBUG | token counts, model name |
| Redis session store | INFO | `[WorkflowSessionStore] Initialized (Redis={url})` |
| Disambiguation gate | INFO | disambiguation fired, candidates |

### What Is NOT Logged (Gaps)

1. **No structured log when Nextflow is killed by SIGTERM** — only Galaxy's `_stream_logs` thread dying silently
2. **No alert when gunicorn restarts** — gunicorn logs to supervisor but not forwarded
3. **No per-task Batch job ID logged** in Galaxy — Nextflow daemon log has it but Galaxy doesn't capture it
4. **No log when `.nextflow/` cache copy fails silently** (currently only WARNING, and `_resume_nf_cache_src` variable access via `locals()` is fragile)
5. **No health-check endpoint for Nextflow process liveness** — only status endpoint which returns stale data post-restart
6. **CryoSPARC job UIDs not stored** in Galaxy's run record — can't cross-reference CS project from run_id alone

---

## 11. Alerting & What to Monitor

### Key Metrics to Watch

#### 1. Gunicorn Health
```bash
# From EC2 host — should return valid JSON, not empty reply
curl -s http://localhost:8081/api/nextflow/status/<any_run_id> | python3 -c "import json,sys; json.load(sys.stdin)"

# Container uptime
docker ps --format "{{.Names}} {{.Status}}" | grep galaxy
```
**Alert if:** empty reply from port 8081 (gunicorn crashed/restarting)

#### 2. Active Run Liveness
```bash
# Check Nextflow process inside container
docker exec 28af3ce133ca bash -c \
  'ls /tmp/nextflow_runs/*/nextflow.log 2>/dev/null | xargs -I{} tail -1 {}'
```
**Alert if:** a run is `status=running` but its `nextflow.log` hasn't been updated in >10 minutes

#### 3. AWS Batch Job Queue Depth
```bash
aws batch list-jobs --job-queue biomate-nextflow-queue --job-status RUNNABLE \
  --region us-west-2 --query 'jobSummaryList | length(@)'
```
**Alert if:** >20 jobs RUNNABLE for >30 minutes (compute environment scaling issue)

#### 4. S3 Work Dir Growth
```bash
aws s3 ls s3://biomate-nextflow-work/nextflow/work/ --recursive \
  --human-readable 2>/dev/null | tail -1
```
**Alert if:** >500 GB (stale cached runs not cleaned up)

#### 5. CryoSPARC Availability
```bash
curl -s http://3.88.225.107:30000/ | grep -q "CryoSPARC"
```
**Alert if:** CryoSPARC UI unreachable (Batch containers will fail at CS SDK connect)

#### 6. Billing Pipeline Health
```bash
curl -s http://35.86.137.71:3000/api/customers \
  -H "Authorization: Bearer 01b71711-be39-49af-8d14-87a4ee827157" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['customers']), 'customers')"
```
**Alert if:** Lago unreachable or 0 customers (billing events not reaching Lago)

### Recommended Monitoring Dashboard

| Panel | Source | What to show |
|-------|--------|-------------|
| Active runs | `_runs` dict size | Count of `status=running` |
| Batch job queue | Batch API | RUNNABLE / RUNNING / FAILED counts per queue |
| Gunicorn uptime | docker stats | Container restart count, uptime |
| CryoSPARC GPU | CS API `/gpu_metrics` | GPU utilization %, memory used |
| Billing events | Lago `/api/events` | Events/hour, total cost this month |
| S3 bucket size | CloudWatch | `BucketSizeBytes` for `biomate-nextflow-work` |
| Error rate | Galaxy logs | ERROR count per 5min window |

---

## 12. Incident Runbook

### Scenario 1: "Status shows running but nothing is happening"

**Symptoms:** Run status = `running`, no log lines updating, no Batch jobs visible

**Diagnosis:**
```bash
# 1. SSH to EC2
ssh -i /tmp/biomate_ec2_key_sync ubuntu@52.42.49.175

# 2. Check if Nextflow process is alive
docker exec 28af3ce133ca bash -c 'ls /tmp/nextflow_runs/<run_id>/'

# 3. Check Nextflow log for last activity
docker exec 28af3ce133ca bash -c 'tail -20 /tmp/nextflow_runs/<run_id>/nextflow.log'

# 4. Check timing.json for completion
docker exec 28af3ce133ca bash -c 'cat /tmp/nextflow_runs/<run_id>/timing.json'
```

**Fix:** If Nextflow was killed (gunicorn restart), resume:
```bash
curl -X POST 'http://localhost:8081/api/nextflow/resume/<run_id>' \
  -H 'Content-Type: application/json' \
  -H 'X-E2E-Test-Token: biomate-e2e-test-bypass-2024' \
  -d '{"nextflow_path":"biomni_workflows/.../main.nf","is_batch":true,"user_id":"<uid>","parameters":{...}}'
```

---

### Scenario 2: Galaxy API returns empty reply

**Symptoms:** `curl localhost:8081/...` returns empty, frontend shows errors

**Diagnosis:**
```bash
docker ps | grep galaxy      # check container running
docker exec 28af3ce133ca supervisorctl status   # check gunicorn status
docker logs 28af3ce133ca --tail 50   # check startup errors
```

**Fix:**
```bash
docker exec 28af3ce133ca galaxyctl restart gunicorn
# OR full container restart:
docker restart 28af3ce133ca
```
⚠️ Container restart kills all Nextflow subprocesses (even with `start_new_session=True`). Resume any active runs afterward.

---

### Scenario 3: Nextflow -resume ignored ("never run this project before")

**Symptoms:** After resume, all tasks re-run from scratch (not from cache). 6-8 hour re-run instead of minutes.

**Diagnosis:** Check `.nextflow/` was copied to correct path:
```bash
docker exec 28af3ce133ca bash -c \
  'ls /tmp/nextflow_runs/<new_run_id>/work/.nextflow/'
# Should show: cache  history  plr
```

**Fix:** If missing, manually copy from previous run:
```bash
docker exec 28af3ce133ca bash -c '
cp -r /tmp/nextflow_runs/<prev_run_id>/work/.nextflow \
      /tmp/nextflow_runs/<new_run_id>/work/.nextflow
'
# Then restart Nextflow (stop current, resume again)
```

---

### Scenario 4: CryoSPARC job fails with APIError 404 on output slot

**Symptoms:** `APIError: ...outputs/volume:load... code 404`

**Root cause:** CryoSPARC v5 renamed `homo_abinit` output slot from `"volume"` to `"volume_class_0"`.

**Fix:** Already applied in `main.nf` lines ~1066–1083 — fallback chain tries `volume_class_0 → volume_0 → volume → volumes`. If a new job type has this issue, apply the same pattern.

---

### Scenario 5: Batch job stuck in RUNNABLE

**Symptoms:** Nextflow submitted a Batch job but it never starts (no compute available)

**Diagnosis:**
```bash
aws batch describe-jobs --jobs <job_id> --region us-west-2 \
  --query 'jobs[0].{status:status,reason:statusReason}'

aws batch list-jobs --job-queue biomate-nextflow-queue \
  --job-status RUNNABLE --region us-west-2 | python3 -c \
  "import json,sys; jobs=json.load(sys.stdin)['jobSummaryList']; print(f'{len(jobs)} runnable')"
```

**Fix:** Check compute environment is ENABLED:
```bash
aws batch describe-compute-environments \
  --compute-environments biomate-nextflow-ce-v2 --region us-west-2 \
  --query 'computeEnvironments[0].{state:state,status:status}'
```
If DISABLED, enable via console or:
```bash
aws batch update-compute-environment \
  --compute-environment biomate-nextflow-ce-v2 \
  --state ENABLED --region us-west-2
```

---

### Scenario 6: docker cp fails with "Could not find the file /proc/self/fd"

**Symptom:** `Error response from daemon: Could not find the file /proc/self/fd in container`

**Root cause:** Target path in container is a symlink to stdin (baked into original image Apr 8).

**Fix:**
```bash
docker exec 28af3ce133ca rm /app/lib/galaxy/webapps/galaxy/api/nextflow_executor.py
docker cp /tmp/nextflow_executor.py 28af3ce133ca:/app/lib/galaxy/.../nextflow_executor.py
docker exec 28af3ce133ca galaxyctl restart gunicorn
```

---

### Scenario 7: EC2 instance-connect key expired mid-transfer

**Symptom:** SSH/SCP hangs or fails with "Permission denied" mid-operation

**Root cause:** EC2 instance-connect keys expire every ~60 seconds.

**Fix:** Regenerate before EVERY SSH/SCP call:
```bash
aws ec2-instance-connect send-ssh-public-key \
  --region us-west-2 --instance-id i-06696b0d91f4346e0 \
  --instance-os-user ubuntu --ssh-public-key file:///tmp/biomate_ec2_key_sync.pub
# Key valid for ~60s — issue SSH immediately after
```

---

## 13. Draw.io Diagrams (XML)

### Diagram 1 — Full System Architecture

Save as `.drawio` file, open at draw.io or VS Code Draw.io extension.

```xml
<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1654" pageHeight="1169" math="0" shadow="0">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />

    <!-- ═══ USER BROWSER ═══ -->
    <mxCell id="10" value="User Browser" style="shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.client;labelBackgroundColor=#ffffff;sketch=0;fontStyle=1;fontSize=11;" vertex="1" parent="1">
      <mxGeometry x="60" y="80" width="80" height="80" as="geometry" />
    </mxCell>
    <mxCell id="11" value="Chat Panel&#xa;(SSE stream)" style="rounded=1;whiteSpace=wrap;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
      <mxGeometry x="40" y="200" width="120" height="40" as="geometry" />
    </mxCell>
    <mxCell id="12" value="Workflow Panel&#xa;(poll /runs/:id)" style="rounded=1;whiteSpace=wrap;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
      <mxGeometry x="40" y="260" width="120" height="40" as="geometry" />
    </mxCell>

    <!-- ═══ NODE.JS SERVER ═══ -->
    <mxCell id="20" value="Node.js Server&#xa;(EC2 :5000)" style="rounded=1;whiteSpace=wrap;fillColor=#d5e8d4;strokeColor=#82b366;fontStyle=1;fontSize=12;" vertex="1" parent="1">
      <mxGeometry x="240" y="80" width="160" height="280" as="geometry" />
    </mxCell>
    <mxCell id="21" value="routes.ts&#xa;110+ endpoints" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="255" y="110" width="130" height="40" as="geometry" />
    </mxCell>
    <mxCell id="22" value="galaxy-assistant.ts&#xa;Claude Sonnet 4.6&#xa;+ Gemini Flash" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="255" y="165" width="130" height="55" as="geometry" />
    </mxCell>
    <mxCell id="23" value="GalaxyAPIProxy&#xa;→ :8081" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="255" y="235" width="130" height="40" as="geometry" />
    </mxCell>
    <mxCell id="24" value="PostgreSQL&#xa;(sessions, users)" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="255" y="290" width="130" height="40" as="geometry" />
    </mxCell>

    <!-- ═══ GALAXY BACKEND ═══ -->
    <mxCell id="30" value="Galaxy Backend&#xa;Docker :8081 → :8080" style="rounded=1;whiteSpace=wrap;fillColor=#ffe6cc;strokeColor=#d6b656;fontStyle=1;fontSize=12;" vertex="1" parent="1">
      <mxGeometry x="480" y="80" width="180" height="320" as="geometry" />
    </mxCell>
    <mxCell id="31" value="gunicorn&#xa;(N workers, Python 3.9)" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="495" y="110" width="150" height="35" as="geometry" />
    </mxCell>
    <mxCell id="32" value="nextflow_executor.py&#xa;execute / status / resume" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="495" y="160" width="150" height="45" as="geometry" />
    </mxCell>
    <mxCell id="33" value="ai_assistant.py&#xa;search / generate" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="495" y="220" width="150" height="35" as="geometry" />
    </mxCell>
    <mxCell id="34" value="_runs dict (in-memory)&#xa;+ timing.json on disk" style="rounded=1;whiteSpace=wrap;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
      <mxGeometry x="495" y="270" width="150" height="40" as="geometry" />
    </mxCell>
    <mxCell id="35" value="Nextflow subprocess&#xa;start_new_session=True" style="rounded=1;whiteSpace=wrap;fillColor=#f8cecc;strokeColor=#b85450;" vertex="1" parent="1">
      <mxGeometry x="495" y="325" width="150" height="40" as="geometry" />
    </mxCell>

    <!-- ═══ AWS BATCH ═══ -->
    <mxCell id="40" value="AWS Batch (us-west-2)" style="rounded=1;whiteSpace=wrap;fillColor=#f5f5f5;strokeColor=#666666;fontStyle=1;fontSize=12;" vertex="1" parent="1">
      <mxGeometry x="750" y="80" width="200" height="200" as="geometry" />
    </mxCell>
    <mxCell id="41" value="biomate-nextflow-queue&#xa;(CPU: m6i.xlarge)" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="765" y="110" width="170" height="45" as="geometry" />
    </mxCell>
    <mxCell id="42" value="galaxy-cloud-queue-gpu&#xa;(GPU: g4dn/g5 + L4)" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="765" y="170" width="170" height="45" as="geometry" />
    </mxCell>
    <mxCell id="43" value="S3: biomate-nextflow-work&#xa;work/ + outputs/" style="rounded=1;whiteSpace=wrap;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
      <mxGeometry x="765" y="230" width="170" height="40" as="geometry" />
    </mxCell>

    <!-- ═══ CRYOSPARC ═══ -->
    <mxCell id="50" value="CryoSPARC EC2&#xa;3.88.225.107:30000&#xa;(us-east-1, L4 GPU)" style="rounded=1;whiteSpace=wrap;fillColor=#e1d5e7;strokeColor=#9673a6;fontStyle=1;fontSize=12;" vertex="1" parent="1">
      <mxGeometry x="750" y="330" width="200" height="100" as="geometry" />
    </mxCell>
    <mxCell id="51" value="/home/ubuntu/biomate_movies/&#xa;2b97383e3f/*.mrcs" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="765" y="380" width="170" height="35" as="geometry" />
    </mxCell>

    <!-- ═══ BILLING ═══ -->
    <mxCell id="60" value="Billing Stack (us-west-2)" style="rounded=1;whiteSpace=wrap;fillColor=#fff2cc;strokeColor=#d6b656;fontStyle=1;fontSize=12;" vertex="1" parent="1">
      <mxGeometry x="480" y="460" width="180" height="120" as="geometry" />
    </mxCell>
    <mxCell id="61" value="Lago 35.86.137.71:3000" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="495" y="490" width="150" height="30" as="geometry" />
    </mxCell>
    <mxCell id="62" value="Java billing :8080" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="495" y="530" width="150" height="30" as="geometry" />
    </mxCell>
    <mxCell id="63" value="Redis ElastiCache" style="rounded=1;whiteSpace=wrap;fillColor=#f9f9f9;" vertex="1" parent="1">
      <mxGeometry x="495" y="562" width="150" height="30" as="geometry" />
    </mxCell>

    <!-- ═══ EDGES ═══ -->
    <!-- Browser → Node.js -->
    <mxCell id="e1" value="HTTPS/SSE" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="10" target="20" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Node.js → Galaxy -->
    <mxCell id="e2" value="HTTP proxy" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="23" target="30" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Galaxy → Nextflow subprocess -->
    <mxCell id="e3" value="Popen&#xa;(detached)" style="edgeStyle=orthogonalEdgeStyle;dashed=1;" edge="1" source="32" target="35" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Nextflow → Batch -->
    <mxCell id="e4" value="submit jobs" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="35" target="40" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Batch → S3 -->
    <mxCell id="e5" value="read/write" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="40" target="43" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Batch → CryoSPARC -->
    <mxCell id="e6" value="cryosparc-tools SDK" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="42" target="50" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Galaxy → Billing -->
    <mxCell id="e7" value="cost events" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="32" target="60" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <!-- Browser → Poll -->
    <mxCell id="e8" value="poll /runs/:id every 10s" style="edgeStyle=orthogonalEdgeStyle;dashed=1;" edge="1" source="12" target="20" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
  </root>
</mxGraphModel>
```

### Diagram 2 — Nextflow Resume Flow

```xml
<mxGraphModel>
  <root>
    <mxCell id="0" /><mxCell id="1" parent="0" />

    <mxCell id="10" value="Resume Request&#xa;POST /api/nextflow/resume/{run_id}" style="rounded=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1"><mxGeometry x="300" y="40" width="240" height="50" as="geometry" /></mxCell>
    <mxCell id="11" value="Lookup _runs[run_id]&#xa;(in-memory)" style="rhombus;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1"><mxGeometry x="340" y="130" width="160" height="60" as="geometry" /></mxCell>
    <mxCell id="12" value="Reconstruct from env:&#xa;work_dir = s3://{bucket}/nextflow/work/{user}/{run_id}&#xa;is_batch = true" style="rounded=1;fillColor=#f8cecc;" vertex="1" parent="1"><mxGeometry x="560" y="125" width="240" height="60" as="geometry" /></mxCell>
    <mxCell id="13" value="Copy .nextflow/ cache&#xa;prev/work/.nextflow → new_run/work/.nextflow" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="340" y="240" width="240" height="50" as="geometry" /></mxCell>
    <mxCell id="14" value="Nextflow CLI:&#xa;nextflow run main.nf -profile awsbatch -resume&#xa;-w s3://.../work/{user}/{new_run_id}/" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="300" y="340" width="300" height="60" as="geometry" /></mxCell>
    <mxCell id="15" value="Popen(start_new_session=True)" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="340" y="450" width="220" height="40" as="geometry" /></mxCell>
    <mxCell id="16" value="Nextflow scans S3 cache&#xa;(2–5 min for large work dirs)" style="rounded=1;fillColor=#fff2cc;" vertex="1" parent="1"><mxGeometry x="340" y="540" width="220" height="50" as="geometry" /></mxCell>
    <mxCell id="17" value="Cache hits: skip to last completed task&#xa;New tasks: submit to Batch" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="310" y="640" width="280" height="50" as="geometry" /></mxCell>

    <mxCell id="e1" edge="1" source="10" target="11" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e2" value="not found (restart)" edge="1" source="11" target="12" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e3" value="found or reconstructed" edge="1" source="11" target="13" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e3b" edge="1" source="12" target="13" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e4" edge="1" source="13" target="14" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e5" edge="1" source="14" target="15" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e6" edge="1" source="15" target="16" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
    <mxCell id="e7" edge="1" source="16" target="17" parent="1"><mxGeometry relative="1" as="geometry" /></mxCell>
  </root>
</mxGraphModel>
```

### Diagram 3 — CryoSPARC SPA 25-Step Pipeline

```xml
<mxGraphModel>
  <root>
    <mxCell id="0" /><mxCell id="1" parent="0" />

    <!-- Phase A -->
    <mxCell id="A" value="Phase A — Data Ingest" style="rounded=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="20" y="20" width="180" height="30" as="geometry" /></mxCell>
    <mxCell id="A1" value="1. INIT (import_movies)" style="rounded=1;fillColor=#dae8fc;" vertex="1" parent="1"><mxGeometry x="20" y="60" width="180" height="30" as="geometry" /></mxCell>
    <mxCell id="A2" value="2. SPLIT_INTO_BATCHES" style="rounded=1;fillColor=#dae8fc;" vertex="1" parent="1"><mxGeometry x="20" y="100" width="180" height="30" as="geometry" /></mxCell>

    <!-- Phase B -->
    <mxCell id="B" value="Phase B — Preprocessing" style="rounded=1;fillColor=#d5e8d4;strokeColor=#82b366;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="220" y="20" width="200" height="30" as="geometry" /></mxCell>
    <mxCell id="B1" value="3. PATCH_MOTION_CORRECTION" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="220" y="60" width="200" height="30" as="geometry" /></mxCell>
    <mxCell id="B2" value="4. PATCH_CTF_ESTIMATION" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="220" y="100" width="200" height="30" as="geometry" /></mxCell>
    <mxCell id="B3" value="5. BLOB_PICKER (GPU)" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="220" y="140" width="200" height="30" as="geometry" /></mxCell>
    <mxCell id="B4" value="6-10. MERGE + DENOISER + JUNK + INSPECT" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="220" y="180" width="200" height="30" as="geometry" /></mxCell>
    <mxCell id="B5" value="11. EXTRACT_R1 (CPU)" style="rounded=1;fillColor=#d5e8d4;" vertex="1" parent="1"><mxGeometry x="220" y="220" width="200" height="30" as="geometry" /></mxCell>

    <!-- Phase C -->
    <mxCell id="C" value="Phase C — 2D Classification R1" style="rounded=1;fillColor=#ffe6cc;strokeColor=#d6b656;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="440" y="20" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C1" value="12-13. MERGE_R1 + SPLIT" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="60" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C2" value="14. CLASSIFY_2D_R1 (GPU)" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="100" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C3" value="15-16. MERGE_CLASSES + SELECT_R1" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="140" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C4" value="17. TEMPLATE_PICKER (GPU)" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="180" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C5" value="18-20. INSPECT + EXTRACT_R2 + SPLIT" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="220" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C6" value="21-22. CLASSIFY_2D_R2 ×2 (GPU)" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="260" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="C7" value="23-24. MERGE_R2 + SELECT_R2" style="rounded=1;fillColor=#ffe6cc;" vertex="1" parent="1"><mxGeometry x="440" y="300" width="220" height="30" as="geometry" /></mxCell>

    <!-- Phase D -->
    <mxCell id="D" value="Phase D — 3D Reconstruction" style="rounded=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="680" y="20" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="D1" value="25. AB_INITIO (homo_abinit GPU)&#xa;★ Bug 6 fixed: volume_class_0 slot" style="rounded=1;fillColor=#e1d5e7;" vertex="1" parent="1"><mxGeometry x="680" y="60" width="220" height="45" as="geometry" /></mxCell>
    <mxCell id="D2" value="26. HOMO_REFINEMENT (homo_refine_new GPU)" style="rounded=1;fillColor=#e1d5e7;" vertex="1" parent="1"><mxGeometry x="680" y="115" width="220" height="30" as="geometry" /></mxCell>

    <!-- Phase E -->
    <mxCell id="E" value="Phase E — Post-processing" style="rounded=1;fillColor=#f8cecc;strokeColor=#b85450;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="680" y="180" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="E1" value="27. VALIDATION_FSC (validation)" style="rounded=1;fillColor=#f8cecc;" vertex="1" parent="1"><mxGeometry x="680" y="220" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="E2" value="28. LOCAL_CTF_REFINEMENT (ctf_refine_local)" style="rounded=1;fillColor=#f8cecc;" vertex="1" parent="1"><mxGeometry x="680" y="260" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="E3" value="29. NON_UNIFORM_REFINEMENT (nonuniform_refine_new)" style="rounded=1;fillColor=#f8cecc;" vertex="1" parent="1"><mxGeometry x="680" y="300" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="E4" value="30. LOCAL_RESOLUTION (local_resolution)" style="rounded=1;fillColor=#f8cecc;" vertex="1" parent="1"><mxGeometry x="680" y="340" width="220" height="30" as="geometry" /></mxCell>
    <mxCell id="E5" value="31. SHARPEN (sharpen)" style="rounded=1;fillColor=#f8cecc;" vertex="1" parent="1"><mxGeometry x="680" y="380" width="220" height="30" as="geometry" /></mxCell>
  </root>
</mxGraphModel>
```

---

## Appendix: Logging Gaps & Recommended Additions

### Gaps Found (Priority Order)

| Priority | Gap | Recommendation |
|----------|-----|----------------|
| P1 | No log when Nextflow process killed by SIGTERM | Add SIGTERM handler in `_stream_logs` that logs "Nextflow process killed (SIGTERM) — resume required" |
| P1 | No alert when gunicorn restarts unexpectedly | Supervisor event listener → CloudWatch alarm or Slack webhook on restart |
| P2 | No Batch job ID in Galaxy run record | Log `[Nextflow run {run_id}] Batch job {batch_job_id} submitted for task {task_name}` by parsing `nextflow.log` |
| P2 | `.nextflow/` cache copy uses fragile `locals()` hack | Refactor to class-level variable, add explicit `log.info/warning` on copy result |
| P2 | `completed_at` not written if `_stream_logs` thread dies | Move `timing.json` write to Nextflow process exit detection, not thread teardown |
| P3 | CryoSPARC job UIDs not stored | Write CS project UID + job UID to run record on each CS task |
| P3 | No health endpoint for "is Nextflow running" | Add `GET /api/nextflow/alive/{run_id}` checking process exists + log freshness |
| P3 | Frontend shows no indicator during S3 cache scan | Add `"Scanning workflow cache…"` hint when `status=running` AND `totalTasks=0` AND `elapsed > 30s` |

### Recommended Log Format (Structured JSON)

For production, replace plain-text logs with structured JSON to enable CloudWatch Insights queries:

```python
log.info(json.dumps({
    "event": "nextflow_run_started",
    "run_id": run_id,
    "user_id": user_id,
    "nextflow_path": nf_path,
    "is_batch": is_batch,
    "resume_from": resume_from_run_id,
    "timestamp": time.time()
}))
```

This enables queries like:
```
fields run_id, user_id, event, timestamp
| filter event = "nextflow_run_started"
| sort timestamp desc
| limit 50
```
