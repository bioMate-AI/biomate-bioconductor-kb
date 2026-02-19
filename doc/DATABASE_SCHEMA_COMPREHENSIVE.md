# BioMate Comprehensive Database Schema Documentation

**Last Updated**: 2026-02-19
**Status**: Production
**Version**: 2.0 (includes Billing System)

---

## Table of Contents

1. [Overview](#overview)
2. [Redis Billing Ledger](#redis-billing-ledger)
3. [Galaxy SQLite Databases](#galaxy-sqlite-databases)
4. [Knowledge & Tools Databases](#knowledge--tools-databases)
5. [Frontend Databases](#frontend-databases)
6. [Data Flow Diagrams](#data-flow-diagrams)

---

## Overview

BioMate uses a **hybrid database architecture** optimized for different data access patterns:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BIOMATE DATABASE ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. REDIS (ElastiCache)              3. SQLITE (Galaxy Core)           │
│     Purpose: Real-time billing          Purpose: User accounts, jobs   │
│     Pattern: Key-value ledger            Pattern: Relational           │
│     Latency: <5ms                        Latency: <50ms                │
│     TTL: 35 days                         TTL: Permanent                │
│                                                                         │
│  2. POSTGRESQL (Lago - optional)     4. SQLITE (AI/Tools)              │
│     Purpose: Invoicing & payments        Purpose: Tool catalog, RAG    │
│     Pattern: Relational                  Pattern: Embedded search      │
│     Latency: 10-50ms                     Latency: <10ms                │
│     TTL: Permanent                       TTL: Permanent                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Redis Billing Ledger

**Location**: ElastiCache Redis (Multi-AZ)
**Endpoint**: `biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379`
**Database**: 0
**TTL**: 35 days (covers current + previous billing month)

### Key Naming Convention

```
cost:{user_id}:month:{YYYY-MM}:{category}
cost:{user_id}:job:{job_id}:running
quota:{user_id}:month:{YYYY-MM}:{type}
billing:last_batch_event_ts
s3:{user_id}:obj:{key_hash}
```

### Schema by Category

#### 1. Monthly Cost Ledger (Committed Costs)

**Key Pattern**: `cost:{user_id}:month:{YYYY-MM}:{category}`
**Type**: Redis HASH
**TTL**: 35 days

| Category | Hash Fields | Description |
|----------|-------------|-------------|
| **llm** | `input_usd` | LLM input token cost (float) |
| | `output_usd` | LLM output token cost (float) |
| | `input_tokens` | Total input tokens (int) |
| | `output_tokens` | Total output tokens (int) |
| | `calls` | Number of LLM calls (int) |
| **compute** | `vcpu_usd` | vCPU cost (float) |
| | `gpu_usd` | GPU cost (float) |
| | `mem_usd` | Memory cost (float) |
| | `seconds` | Total compute seconds (float) |
| | `jobs` | Number of jobs (int) |
| **storage** | `storage_usd` | S3 storage cost (float) |
| | `request_usd` | S3 request cost (float) |
| | `transfer_usd` | Data transfer cost (float) |
| | `bytes_stored` | Total bytes stored (int) |
| | `puts` | Number of PUT requests (int) |
| | `gets` | Number of GET requests (int) |

**Example**:
```redis
HGETALL cost:user-123:month:2026-02:llm
=> {
  "input_usd": "2.45",
  "output_usd": "12.30",
  "input_tokens": "980000",
  "output_tokens": "820000",
  "calls": "45"
}
```

#### 2. Monthly Total (Aggregated)

**Key Pattern**: `cost:{user_id}:month:{YYYY-MM}:total`
**Type**: Redis STRING (float)
**TTL**: 35 days

**Example**:
```redis
GET cost:user-123:month:2026-02:total
=> "14.75"  # Sum of all category costs
```

#### 3. Running Job Estimates (Live Costs)

**Key Pattern**: `cost:{user_id}:job:{job_id}:running`
**Type**: Redis STRING (JSON)
**TTL**: 35 days (cleared when job completes)

**Schema**:
```json
{
  "user_id": "user-123",
  "instance_type": "c6i.xlarge",
  "vcpus": 4,
  "memory_mb": 8192,
  "gpu_count": 0,
  "started_at_ms": 1708387200000,
  "is_spot": false,
  "est_usd": 0.0524,
  "elapsed_seconds": 327
}
```

**Example**:
```redis
GET cost:user-123:job:job-abc:running
=> "{\"user_id\":\"user-123\",\"instance_type\":\"c6i.xlarge\",\"vcpus\":4,\"memory_mb\":8192,\"gpu_count\":0,\"started_at_ms\":1708387200000,\"is_spot\":false,\"est_usd\":0.0524,\"elapsed_seconds\":327}"
```

#### 4. Quota Configuration

**Key Pattern**: `quota:{user_id}:month:{YYYY-MM}:{type}`
**Type**: Redis STRING
**TTL**: 35 days

| Type | Description | Example Value |
|------|-------------|---------------|
| `limit` | Monthly spend cap in USD | `"50.00"` |
| `alert_sent` | 80% warning sent flag | `"1"` |
| `exceeded_sent` | 100% alert sent flag | `"1"` |

**Example**:
```redis
GET quota:user-123:month:2026-02:limit
=> "50.00"

GET quota:user-123:month:2026-02:alert_sent
=> "1"  # Alert already sent
```

#### 5. S3 Object Metadata (for Delete Reversal)

**Key Pattern**: `s3:{user_id}:obj:{key_hash}`
**Type**: Redis HASH
**TTL**: 35 days

| Field | Description |
|-------|-------------|
| `put_at` | Upload timestamp (Unix epoch int) |
| `size_bytes` | Object size in bytes (int) |
| `storage_usd` | Pre-charged 30-day storage cost (string) |
| `month` | Billing month (YYYY-MM) |

**Example**:
```redis
HGETALL s3:user-123:obj:a1b2c3d4e5f6
=> {
  "put_at": "1708387200",
  "size_bytes": "1073741824",
  "storage_usd": "0.000736",
  "month": "2026-02"
}
```

#### 6. System Health (Lambda Heartbeat)

**Key Pattern**: `billing:last_batch_event_ts`
**Type**: Redis STRING (Unix timestamp)
**TTL**: None (permanent)

**Example**:
```redis
GET billing:last_batch_event_ts
=> "1708387200"  # Last Batch event processed at this timestamp
```

### Redis Data Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        REDIS BILLING DATA FLOW                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. LLM CALL                                                             │
│     User sends chat → AI generates response                             │
│     ↓                                                                    │
│     llm_client._emit_llm_billing()                                       │
│     ↓                                                                    │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:llm input_usd 0.025       │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:llm output_usd 0.125      │
│     HINCRBY cost:{user_id}:month:2026-02:llm calls 1                    │
│     INCRBYFLOAT cost:{user_id}:month:2026-02:total 0.150                │
│                                                                          │
│  2. BATCH JOB START                                                      │
│     AWS Batch job → RUNNING                                              │
│     ↓                                                                    │
│     EventBridge → Lambda → POST /internal/billing/job_started           │
│     ↓                                                                    │
│     SETEX cost:{user_id}:job:{job_id}:running 3024000 {json}            │
│     (Background thread polls every 10s, updates est_usd)                │
│                                                                          │
│  3. BATCH JOB END                                                        │
│     AWS Batch job → SUCCEEDED                                            │
│     ↓                                                                    │
│     EventBridge → Lambda → POST /internal/billing/job_completed         │
│     ↓                                                                    │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:compute vcpu_usd 0.34     │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:compute mem_usd 0.05      │
│     HINCRBY cost:{user_id}:month:2026-02:compute jobs 1                 │
│     INCRBYFLOAT cost:{user_id}:month:2026-02:total 0.39                 │
│     DEL cost:{user_id}:job:{job_id}:running                             │
│                                                                          │
│  4. S3 UPLOAD                                                            │
│     S3 ObjectCreated → SQS → Lambda → POST /internal/billing/s3_put     │
│     ↓                                                                    │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:storage storage_usd 0.023 │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:storage request_usd 0.005 │
│     HINCRBY cost:{user_id}:month:2026-02:storage puts 1                 │
│     HSET s3:{user_id}:obj:{hash} put_at {ts} size_bytes {size} ...     │
│     INCRBYFLOAT cost:{user_id}:month:2026-02:total 0.028                │
│                                                                          │
│  5. S3 DELETE (Cost Reversal)                                            │
│     S3 ObjectRemoved → SQS → Lambda → POST /internal/billing/s3_delete  │
│     ↓                                                                    │
│     HGETALL s3:{user_id}:obj:{hash}                                      │
│     Calculate refund = storage_usd * (remaining_days / 30)               │
│     HINCRBYFLOAT cost:{user_id}:month:2026-02:storage storage_usd -0.02 │
│     INCRBYFLOAT cost:{user_id}:month:2026-02:total -0.02                │
│     DEL s3:{user_id}:obj:{hash}                                          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Galaxy SQLite Databases

BioMate uses **3 separate SQLite databases** for different Galaxy functions:

### 1. Universe Database (`universe.sqlite`)

**Location**: `backend/database/universe.sqlite`
**Purpose**: User accounts, API keys, session management
**Size**: ~500 KB

**Key Tables**:

```sql
-- Users and Authentication
CREATE TABLE galaxy_user (
    id INTEGER PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password TEXT,  -- hashed
    username TEXT,
    active BOOLEAN DEFAULT 1,
    create_time DATETIME,
    update_time DATETIME
);

-- API Keys (for programmatic access)
CREATE TABLE api_keys (
    id INTEGER PRIMARY KEY,
    user_id INTEGER REFERENCES galaxy_user(id),
    key TEXT UNIQUE NOT NULL,  -- sha256 hash
    create_time DATETIME,
    deleted BOOLEAN DEFAULT 0
);

-- Sessions
CREATE TABLE galaxy_session (
    id INTEGER PRIMARY KEY,
    session_key TEXT UNIQUE,
    user_id INTEGER REFERENCES galaxy_user(id),
    create_time DATETIME,
    update_time DATETIME,
    last_action DATETIME
);
```

**Example Data**:
```sql
SELECT id, email, username FROM galaxy_user LIMIT 3;
-- 1 | admin@galaxy.org | admin
-- 2 | user@example.com | testuser
-- 3 | demo@biomate.ai | demo
```

### 2. Control Database (`control.sqlite`)

**Location**: `backend/database/control.sqlite`
**Purpose**: Workflow definitions, tool wrappers, data types
**Size**: ~50 MB

**Key Tables**:

```sql
-- Workflows (stored as JSON)
CREATE TABLE stored_workflow (
    id INTEGER PRIMARY KEY,
    user_id INTEGER REFERENCES galaxy_user(id),
    name TEXT,
    slug TEXT,
    published BOOLEAN DEFAULT 0,
    importable BOOLEAN DEFAULT 0,
    create_time DATETIME,
    update_time DATETIME,
    -- Workflow definition stored as JSON string
    stored_workflow_annotation_association TEXT
);

-- Tools Registry
CREATE TABLE tool (
    id TEXT PRIMARY KEY,  -- e.g., "toolshed.g2.bx.psu.edu/repos/iuc/bwa/bwa_mem/0.7.17.2"
    tool_version TEXT,
    name TEXT,
    description TEXT,
    config_file TEXT,  -- Path to XML
    hidden BOOLEAN DEFAULT 0,
    is_workflow_compatible BOOLEAN DEFAULT 1
);

-- Data Types
CREATE TABLE galaxy_datatype (
    id INTEGER PRIMARY KEY,
    extension TEXT UNIQUE,  -- e.g., "fastqsanger", "bam", "vcf"
    type TEXT,  -- Python class path
    mimetype TEXT,
    display_in_upload BOOLEAN DEFAULT 1
);
```

### 3. Results Database (`results.sqlite`)

**Location**: `backend/database/results.sqlite`
**Purpose**: Job execution state, history, datasets
**Size**: Variable (grows with usage)

**Key Tables**:

```sql
-- Histories (user workspaces)
CREATE TABLE history (
    id INTEGER PRIMARY KEY,
    user_id INTEGER REFERENCES galaxy_user(id),
    name TEXT DEFAULT 'Unnamed history',
    create_time DATETIME,
    update_time DATETIME,
    deleted BOOLEAN DEFAULT 0,
    published BOOLEAN DEFAULT 0,
    importable BOOLEAN DEFAULT 0
);

-- Datasets (result files)
CREATE TABLE history_dataset_association (
    id INTEGER PRIMARY KEY,
    history_id INTEGER REFERENCES history(id),
    name TEXT,
    extension TEXT,  -- File type (fastq, bam, etc.)
    file_size INTEGER,
    state TEXT,  -- 'ok', 'error', 'running', 'queued'
    create_time DATETIME,
    update_time DATETIME,
    deleted BOOLEAN DEFAULT 0,
    visible BOOLEAN DEFAULT 1,
    metadata TEXT,  -- JSON metadata
    -- S3 location
    object_store_id TEXT,
    _extra_files_path TEXT
);

-- Jobs (workflow step executions)
CREATE TABLE job (
    id INTEGER PRIMARY KEY,
    create_time DATETIME,
    update_time DATETIME,
    tool_id TEXT,
    tool_version TEXT,
    state TEXT,  -- 'new', 'queued', 'running', 'ok', 'error', 'deleted'
    command_line TEXT,
    user_id INTEGER REFERENCES galaxy_user(id),
    session_id INTEGER REFERENCES galaxy_session(id),

    -- AWS Batch integration
    job_runner_name TEXT,  -- 'batch'
    job_runner_external_id TEXT,  -- AWS Batch job ID
    destination_id TEXT,  -- 'biomate_batch_cpu' or 'biomate_batch_gpu'

    -- Execution details
    exit_code INTEGER,
    traceback TEXT,
    stdout TEXT,
    stderr TEXT
);

-- Workflow Invocations (full workflow runs)
CREATE TABLE workflow_invocation (
    id INTEGER PRIMARY KEY,
    workflow_id INTEGER REFERENCES stored_workflow(id),
    history_id INTEGER REFERENCES history(id),
    user_id INTEGER REFERENCES galaxy_user(id),
    state TEXT,  -- 'new', 'ready', 'scheduled', 'failed', 'cancelled', 'scheduled'
    create_time DATETIME,
    update_time DATETIME
);
```

**Data Flow Example**:
```
User submits workflow
  ↓
workflow_invocation created (state='new')
  ↓
history created for results
  ↓
job created for each step (state='queued')
  ↓
Jobs sent to AWS Batch (job_runner_external_id set)
  ↓
Jobs complete → datasets created
  ↓
workflow_invocation state → 'scheduled' (all done)
```

---

## Knowledge & Tools Databases

### 1. Galaxy AI Tools Database (`galaxy_ai_tools.db`)

**Location**: `backend/galaxy_ai_tools.db`
**Purpose**: Fast tool search, RAG embeddings, parameter inference
**Size**: ~130 MB

**Schema**:
```sql
-- Tools catalog (7000+ tools)
CREATE TABLE tools (
    id TEXT PRIMARY KEY,  -- Fully qualified tool ID
    name TEXT,
    description TEXT,
    version TEXT,
    owner TEXT,
    repository TEXT,
    categories TEXT,  -- JSON array
    requirements TEXT,  -- JSON (conda packages, containers)
    help_text TEXT,  -- Full help documentation

    -- Embeddings for semantic search
    embedding BLOB,  -- 1536-dim vector (OpenAI ada-002)

    -- Metadata
    creation_date DATETIME,
    last_updated DATETIME,
    downloads INTEGER,
    stars INTEGER
);

-- Tool parameters (for LLM parameter inference)
CREATE TABLE tool_parameters (
    id INTEGER PRIMARY KEY,
    tool_id TEXT REFERENCES tools(id),
    name TEXT,
    type TEXT,  -- 'text', 'integer', 'float', 'select', 'data'
    label TEXT,
    help TEXT,
    optional BOOLEAN DEFAULT 0,
    default_value TEXT,
    options TEXT  -- JSON array for select inputs
);

-- RAG index for fast lookup
CREATE INDEX idx_tools_embedding ON tools(embedding);
CREATE INDEX idx_tools_categories ON tools(categories);
CREATE VIRTUAL TABLE tools_fts USING fts5(name, description, help_text);
```

**Query Examples**:
```sql
-- Semantic search (via Python with numpy)
SELECT id, name, description
FROM tools
WHERE embedding IS NOT NULL
ORDER BY embedding_distance(embedding, ?)
LIMIT 10;

-- Full-text search
SELECT * FROM tools_fts WHERE tools_fts MATCH 'RNA sequencing alignment';

-- Category filter
SELECT * FROM tools WHERE categories LIKE '%genomics%';
```

### 2. Biomni Tools Database (`Biomni/biomni_tools_v2.db`)

**Location**: `Biomni/biomni_tools_v2.db`
**Purpose**: Nextflow workflow templates, nf-core modules
**Size**: ~20 MB

**Schema**:
```sql
-- Nextflow workflows
CREATE TABLE nextflow_workflows (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE,
    description TEXT,
    nf_core_version TEXT,
    manifest TEXT,  -- JSON
    params TEXT,  -- JSON schema
    main_nf TEXT,  -- Main workflow code
    modules TEXT,  -- JSON list of modules used
    indexed_at DATETIME
);

-- nf-core modules
CREATE TABLE nfcore_modules (
    id INTEGER PRIMARY KEY,
    name TEXT,
    version TEXT,
    category TEXT,
    main_nf TEXT,  -- Module code
    meta_yml TEXT,  -- Metadata YAML
    requirements TEXT  -- JSON (containers, conda)
);
```

---

## Frontend Databases

### Frontend State Database (`frontend/db/biomate.db`)

**Location**: `frontend/db/biomate.db`
**Purpose**: Local chat history, workflow drafts, user preferences
**Size**: <10 MB

**Schema**:
```sql
-- Chat sessions
CREATE TABLE chat_sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    title TEXT,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Chat messages
CREATE TABLE chat_messages (
    id INTEGER PRIMARY KEY,
    session_id TEXT REFERENCES chat_sessions(id),
    role TEXT,  -- 'user' or 'assistant'
    content TEXT,
    metadata TEXT,  -- JSON (tool calls, workflow refs)
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Workflow drafts (not yet submitted)
CREATE TABLE workflow_drafts (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES chat_sessions(id),
    workflow_ga TEXT,  -- JSON workflow definition
    status TEXT,  -- 'draft', 'validated', 'submitted'
    create_time DATETIME,
    update_time DATETIME
);
```

---

## Data Flow Diagrams

### Complete System Data Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                   BIOMATE END-TO-END DATA FLOW                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  USER BROWSER                                                            │
│     │                                                                    │
│     │ POST /api/chat "Analyze RNA-seq data"                             │
│     ↓                                                                    │
│  FRONTEND (Node.js)                                                      │
│     │ chat_messages INSERT INTO biomate.db                              │
│     │ POST /api/galaxy/ai_assistant/generate_workflow                   │
│     ↓                                                                    │
│  BACKEND (Galaxy Python)                                                 │
│     │ ── LLM call (Claude/Gemini) ──┐                                   │
│     │                                │                                   │
│     │                                └─→ REDIS: HINCRBYFLOAT llm costs  │
│     │                                                                    │
│     │ ── Tool search: galaxy_ai_tools.db (RAG)                          │
│     │ ── Workflow search: control.sqlite (stored_workflow)              │
│     │ ── Parameter inference: LLM + tool_parameters                     │
│     │                                                                    │
│     │ Returns: workflow_ga JSON                                         │
│     ↓                                                                    │
│  FRONTEND                                                                │
│     │ workflow_drafts INSERT (status='draft')                           │
│     │ User clicks "Run Workflow"                                        │
│     │ POST /api/workflows/execute                                       │
│     ↓                                                                    │
│  BACKEND                                                                 │
│     │ ── Quota check: REDIS GET quota limit ──┐                         │
│     │                                          │                         │
│     │ ← quota OK ←─────────────────────────────┘                         │
│     │                                                                    │
│     │ ── history INSERT INTO results.sqlite                             │
│     │ ── workflow_invocation INSERT (state='new')                       │
│     │ ── job INSERT × N steps (state='queued')                          │
│     │                                                                    │
│     │ For each job:                                                     │
│     │   ├─ batch.submit_job() ──→ AWS BATCH                             │
│     │   │   with tags: user_id, workflow_id, instance_type              │
│     │   └─ job.job_runner_external_id = batch_job_id                    │
│     ↓                                                                    │
│  AWS BATCH                                                               │
│     │ Job RUNNING ──→ EventBridge ──→ Lambda                             │
│     │                                    │                               │
│     │                                    └─→ REDIS: SETEX running job   │
│     │                                                                    │
│     │ Job SUCCEEDED ──→ EventBridge ──→ Lambda                           │
│     │                                     │                              │
│     │                                     └─→ REDIS: HINCRBYFLOAT costs │
│     │                                     └─→ Lago: POST /api/v1/events │
│     │                                                                    │
│     │ Results written to S3                                             │
│     │   ObjectCreated ──→ SQS ──→ Lambda                                │
│     │                                │                                   │
│     │                                └─→ REDIS: HINCRBYFLOAT storage    │
│     │                                └─→ REDIS: HSET s3:obj metadata    │
│     ↓                                                                    │
│  BACKEND                                                                 │
│     │ AWS Batch callback updates:                                       │
│     │   job.state = 'ok'                                                │
│     │   history_dataset_association INSERT (S3 path, state='ok')        │
│     ↓                                                                    │
│  FRONTEND                                                                │
│     │ Poll /api/workflows/runs/{id}/status                              │
│     │ Display results from history_dataset_association                  │
│     │                                                                    │
│     │ User views /api/billing/usage                                     │
│     │   └─→ BACKEND reads REDIS, returns real-time costs                │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Migration Notes

### From Legacy to Billing System v2.0

**Changes**:
1. Added ElastiCache Redis for billing ledger
2. New key patterns for S3 object metadata (delete reversal support)
3. Quota enforcement at job submission (via `check_and_reserve()`)
4. Real-time cost tracking (<10s latency vs 24hr AWS delay)

**Backward Compatibility**:
- All Galaxy SQLite schemas unchanged
- Existing jobs/workflows continue to work
- Billing is additive (no breaking changes)

**Data Retention**:
- Redis: 35 days (auto-expire)
- Lago: Permanent (for invoicing/audit)
- Galaxy SQLite: Permanent
- S3 results: 30 days (lifecycle policy)

---

## Backup & Disaster Recovery

```bash
# Redis backup (daily via AWS Backup)
aws backup start-backup-job \
  --resource-arn "arn:aws:elasticache:us-west-2:123456789012:cluster:biomate-billing-redis" \
  --backup-vault-name BioMateVault

# SQLite backup (manual)
cd backend/database
sqlite3 universe.sqlite ".backup universe.sqlite.bak"
sqlite3 control.sqlite ".backup control.sqlite.bak"
sqlite3 results.sqlite ".backup results.sqlite.bak"

# Upload to S3
aws s3 cp universe.sqlite.bak s3://biomate-backups/sqlite/$(date +%Y%m%d)/
```

---

## Performance Benchmarks

| Operation | Database | Latency | QPS |
|-----------|----------|---------|-----|
| GET current costs | Redis | 2-5ms | 10,000+ |
| User login | universe.sqlite | 15-30ms | 500+ |
| Tool search | galaxy_ai_tools.db | 10-50ms | 200+ |
| Job state update | results.sqlite | 20-80ms | 100+ |
| Workflow generation | Multiple DBs + LLM | 2-8s | 10-20 |

---

**Document Maintained By**: BioMate Engineering
**Last Schema Migration**: 2026-02-09 (Billing System v2.0)
