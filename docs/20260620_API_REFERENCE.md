# BioMate API Reference

**Date:** 2026-06-20  
**Server:** Node.js Express on port 5000  
**OpenAPI spec:** `connectors/openapi-biomate-api.yaml` in the connector repo

---

## Overview

BioMate exposes a REST API used by the web frontend, MCP connectors, Claude Code
extensions, CI pipelines, and lab-instrument integrations. All endpoints are under
`/api/`.

### Base URLs

| Environment | URL |
|-------------|-----|
| BioMate Cloud | `https://app.biomate.ai` |
| Dev EC2 | `https://dev-public.biomate.ai` |
| Local dev | `http://localhost:5000` |

### Error format

All 4xx/5xx responses return:
```json
{ "error": "<message>" }
```

Some errors include additional fields (`hint`, `guidance`, `details`).

---

## Authentication

BioMate supports two authentication modes that can be used interchangeably on
all protected endpoints.

### Mode 1 — JWT (browser / OAuth flow)

```
Authorization: Bearer <jwt>
# or
Cookie: biomate_token=<jwt>
```

Obtain a JWT via `POST /api/auth/login`.  The token is also set as an HttpOnly
cookie automatically on login.

**Token lifetime:**
- `rememberMe=false` → 24 h JWT, session cookie (cleared on browser close)
- `rememberMe=true` → 30-day JWT, persistent cookie

### Mode 2 — Static API key (headless / CI / MCP connector)

```
X-API-Key: <key>
# or (non-JWT Bearer)
Authorization: Bearer <key>
```

The key is not a JWT (doesn't start with `eyJ`).  Configure on the BioMate server:
```bash
BIOMATE_CONNECTOR_API_KEY=<secret>    # the key the client sends
BIOMATE_CONNECTOR_USER_ID=<int>       # the user ID to attach to requests
```

**How the middleware chain works:**  
`authenticateStaticApiKey` runs first. If `X-API-Key` matches, `req.user` is set
and `authenticateToken` skips (it detects `req.user` already set). If no API key
is present, the request falls through to JWT auth normally.

### MFA

After login, if MFA is enabled the server returns a short-lived `mfa_challenge`
token instead of a full JWT. Exchange it at `POST /api/auth/mfa/challenge`.
The `mfa_challenge` token cannot be used for any other authenticated request.

### Subscription gate

Authenticated requests that pass identity checks are then checked for an active
subscription. 403 is returned if the subscription is expired, unless the
`X-E2E-Test-Token` bypass header is present (non-production only).

### Rate limits

| Endpoint | Limit |
|----------|-------|
| `POST /api/auth/login` | 10 req/min |
| `POST /api/auth/register` | 5 req/min |

---

## Auth Endpoints

### `POST /api/auth/login`

```json
// Request
{ "email": "user@example.com", "password": "secret", "rememberMe": false }

// Response 200
{
  "success": true,
  "token": "<jwt>",
  "user": { "id": 42, "email": "user@example.com", "username": "alice", "role": "user" },
  "subscription": { "active": true, "plan": "pro", "expiresAt": null }
}

// Response 401  →  {"success": false, "error": "Invalid credentials"}
// Response 403  →  {"error": "TRIAL_EXPIRED", "message": "Your trial has expired."}
```

### `POST /api/auth/logout`

Clears the `biomate_token` cookie. No body required.

### `GET /api/auth/me`

Returns the currently authenticated user. Returns 401 if not authenticated.

---

## Open Claw — Agentic Session

The Open Claw endpoints power the Claude-with-BioMate-tools agentic loop. They
are also what the MCP server's `biomate_session` tool proxies.

### `GET /api/open-claw/tools`

Returns the full schema of all 17 BioMate tools (same as `OPEN_CLAW_TOOLS` in
`routes.ts`). No auth required.

```json
{
  "tools": [ { "name": "search_workflow", "description": "...", "input_schema": {...} }, ... ],
  "model": "claude-sonnet-4-6",
  "note": "Open Claw mode: Claude has direct access to BioMate tools."
}
```

### `POST /api/open-claw/stream` — SSE

Runs Claude with BioMate tools in an agentic loop. Returns
`Content-Type: text/event-stream`.

**Request body:**
```json
{
  "messages": [
    { "role": "user", "content": "Run RNA-seq on GSE183947" }
  ],
  "system": "(optional system prompt override)"
}
```

Messages follow the [Anthropic Messages API](https://docs.anthropic.com/en/api/messages)
format. Pass the full conversation history for multi-turn sessions.

**SSE event stream:**

| Event | Payload | Meaning |
|-------|---------|---------|
| `delta` | `{text: string}` | Streaming text chunk from Claude |
| `tool_call_start` | `{id, name}` | Claude is invoking a tool |
| `tool_call_complete` | `{id, name, input}` | Tool input fully parsed |
| `tool_result` | `{tool_use_id, name, result}` | Synchronous tool result |
| `complete` | `{iterations: number}` | Loop finished — terminal |
| `error` | `{error: string}` | Unhandled server error — terminal |

The loop runs until Claude produces a response with no tool calls, or hits the
10-iteration limit. All tool calls are executed synchronously within the loop
before the next Claude turn starts.

**Consuming SSE in Node.js:**
```typescript
const resp = await fetch('/api/open-claw/stream', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
  body: JSON.stringify({ messages }),
});
for await (const line of resp.body) {
  if (line.startsWith('event:')) { /* ... */ }
  if (line.startsWith('data:')) {
    const data = JSON.parse(line.slice(5));
    // handle data
  }
}
```

---

## Workflow Discovery

### `POST /api/workflows/search`

Semantic search over 2,455 indexed workflows.

```json
// Request
{ "query": "differential expression RNA-seq human", "limit": 5 }

// Response 200
{ "workflows": [ { "id": 123, "name": "DESeq2", "domain": "transcriptomics", "description": "..." } ], "total": 5 }
```

---

## Workflow Execution

### `POST /api/workflows/execute`

Launches a Nextflow/Galaxy workflow on AWS Batch. Returns a `WorkflowRun`
immediately; the run is async. Poll `/api/workflows/runs/:id/status` for progress.

```json
// Request
{
  "workflowDefinition": { /* workflow_ga spec from search/generate */ },
  "params": { "genome": "GRCh38", "input": "s3://..." },
  "projectId": "uuid-optional"
}

// Response 200 — WorkflowRun (see schema below)
// Response 409 — AutoFix active, manual retry blocked:
{
  "error": "autofix_active_retry_blocked",
  "message": "...",
  "guidance": "Wait for AutoFix to complete before triggering a manual rerun."
}
```

---

## Run Management

### `WorkflowRun` schema

```typescript
{
  id: string;                  // UUID
  workflowName: string;
  status: "pending" | "running" | "completed" | "failed" | "cancelled";
  createdAt: string;           // ISO 8601
  startedAt: string | null;
  completedAt: string | null;
  workflowDefinition: object;
  execution: {
    status: string;
    nextflowRunId: string | null;
    galaxyInvocationId: string | null;
    s3OutputBucket: string | null;
    errorMessage: string | null;
    startedAt: string | null;
    completedAt: string | null;
  };
  // ── Inline convenience fields (added for MCP / headless clients) ──
  output_files: string[];      // S3 URIs of published output files
  inline_findings: object[];   // AI-synthesized key results
}
```

### `GET /api/workflows/runs`

```
GET /api/workflows/runs?limit=50&status=completed&projectId=<uuid>
```

Parameters: `limit` (default 100, max 500), `status`, `projectId`, `chatSessionId`.

### `GET /api/workflows/runs/:id`

Returns the enriched `WorkflowRun` with `output_files` and `inline_findings` populated.

**Stuck-run guard**: runs in `status=running` for >12 h are auto-transitioned to
`failed`. AWS Batch outputs may still be recoverable via
`GET /api/workflows/runs/:id/output_files`.

### `GET /api/workflows/runs/:id/status`

Lightweight poll (no full run record):
```json
{ "id": "uuid", "status": "running", "progress": 45, "currentPhase": "alignment", "currentStep": "STAR" }
```

### `POST /api/workflows/runs/:id/cancel`

```json
// Request (optional)
{ "reason": "Wrong parameters, resubmitting" }

// Response 200
{ "success": true, "id": "uuid", "status": "cancelled" }
```

Best-effort: sends cancel signal to Nextflow via Galaxy. If Galaxy is unreachable,
the frontend record is still marked `cancelled`.

### `GET /api/workflows/runs/:id/findings`

AI-synthesized key results for a completed run:
```json
{ "findings": [...], "qc_metrics": {...}, "summary_md": "## Summary\n..." }
```

### `GET /api/workflows/runs/:id/output_files`

```json
[
  { "name": "results.vcf.gz", "s3_uri": "s3://biomate-nextflow-work/.../results.vcf.gz", "size_bytes": 1234567 },
  ...
]
```

### `GET /api/workflows/runs/:id/logs`

```json
{ "stdout": "...", "stderr": "...", "nextflow_log": "..." }
```

---

## Analysis

### `POST /api/workflows/runs/:id/ai/analyze`

AI interpretation of a completed run's outputs.

```json
// Request (question is optional)
{ "question": "which compounds passed ADMET filters?" }

// Response 200
{
  "analysis": "## Key Findings\n\nOf the 847 compounds screened...",
  "findings": [...],
  "suggested_next_steps": ["Run PBPK on the 12 ADMET-passing compounds", ...]
}
```

### `POST /api/workflows/explain_error`

Diagnose a failed run:

```json
// Request
{ "run_id": "uuid", "error_log": "(optional pasted log)" }

// Response 200
{
  "root_cause": "Genome index not found for GRCm39",
  "category": "missing_reference",
  "fix": "Set genome=GRCh38 (human) or confirm GRCm39 index is available",
  "fix_params": { "genome": "GRCh38" }
}
```

---

## Database Queries

### `POST /api/databases/query`

```json
// Request
{ "database": "uniprot", "query": "TP53" }
{ "database": "pdb", "query": "1TUP" }
{ "database": "pubchem", "query": "ibuprofen" }
{ "database": "clinvar", "query": "rs7412" }

// Response — database-specific JSON
```

Supported databases: `uniprot`, `pdb`, `alphafold`, `ncbi_gene`, `dbsnp`,
`clinvar`, `gnomad`, `kegg`, `reactome`, `chebi`, `pubchem`, `hpo`, `omim`, `string`.

---

## Public Data Sources

Three endpoints for browsing and staging public genomic data.

Auth: both JWT and static API key accepted (chained middleware).

### `GET /api/data/sources`

Lists configured public data source plugins:

```json
{
  "sources": [
    { "id": "ebi_ftp", "label": "EBI — European Bioinformatics Institute", "type": "ftp", "writable": false },
    { "id": "ncbi_ftp", "label": "NCBI — National Center for Biotechnology Information", "type": "ftp", "writable": false },
    { "id": "ensembl_ftp", "label": "Ensembl — Genome Browser", "type": "ftp", "writable": false },
    { "id": "ucsc_downloads", "label": "UCSC Genome Downloads", "type": "ftp", "writable": false },
    { "id": "http_public", "label": "HTTP/HTTPS — Public URLs", "type": "http", "writable": false }
  ]
}
```

Falls back to the static list if Galaxy is unavailable.

### `GET /api/data/browse`

```
GET /api/data/browse?source=ncbi_ftp&path=/genomes/refseq/vertebrate_mammalian/Homo_sapiens/
```

Proxies to Galaxy `/api/remote_files`. Returns directory listing:

```json
{
  "source": "ncbi_ftp",
  "path": "/genomes/...",
  "entries": [
    { "name": "GRCh38_latest_genomic.fna.gz", "type": "file", "size": 874263491, "uri": "ftp://ftp.ncbi.nlm.nih.gov/..." },
    { "name": "annotation", "type": "directory" }
  ]
}
```

### `POST /api/data/fetch`

Downloads a public file to BioMate's S3 workspace.

```json
// FTP source
{ "source_id": "ebi_ftp", "remote_path": "/pub/databases/uniprot/.../uniprot_sprot.fasta.gz" }

// HTTP source
{ "source_id": "http_public", "url": "https://zenodo.org/record/6977412/files/sequences.fasta" }

// Response 200
{
  "s3_uri": "s3://biomate-nextflow-work/public-data/uniprot_sprot.fasta.gz",
  "s3_key": "public-data/uniprot_sprot.fasta.gz",
  "presigned_url": "https://biomate-nextflow-work.s3.amazonaws.com/...",
  "filename": "uniprot_sprot.fasta.gz",
  "size_bytes": 874263491,
  "source_url": "ftp://ftp.ebi.ac.uk/pub/databases/uniprot/.../uniprot_sprot.fasta.gz"
}
```

Pass the `s3_uri` directly as a workflow input parameter.

---

## Accession Resolution

### `POST /api/accession/resolve`

Classifies a public archive accession and returns the best fetcher workflow
with pre-filled parameters.

**Routing table:**

| Prefix | Archive | Workflow | Param |
|--------|---------|----------|-------|
| `GSE*`, `GDS*` | GEO series | Geo Data Connector (id=10672) | `accession` |
| `GSM*` | GEO sample | Geo Data Connector (id=10672) | `accession` |
| `SRR*`, `SRX*`, `SRS*`, `SRP*` | SRA | nf-core/fetchngs (id=12704) | `input` |
| `ERR*`, `ERX*`, `ERP*`, `PRJEB*` | ENA | nf-core/fetchngs (id=12704) | `input` |
| `DRR*`, `DRP*`, `PRJDB*` | DDBJ | nf-core/fetchngs (id=12704) | `input` |
| `PRJNA*` | SRA/NCBI | nf-core/fetchngs (id=12704) | `input` |
| `E-MTAB-*`, `E-GEOD-*` | ArrayExpress | nf-core/fetchngs (id=12704) | `input` |

```json
// Request
{ "accession": "GSE183947" }

// Response 200
{
  "accession": "GSE183947",
  "accession_type": "GEO_series",
  "archive": "GEO",
  "workflow_id": 10672,
  "workflow_name": "Geo Data Connector",
  "nextflow_path": "nextflow_nfcore/subworkflows/genomics/geo_data_connector/main.nf",
  "prefilled_params": { "accession": "GSE183947" },
  "description": "Downloads GEO series matrix + clinical metadata via GEOquery; emits channels ready for DESeq2/edgeR.",
  "ready_to_run": true,
  "next_step": "Call run_workflow with workflow_id=10672 and params={\"accession\":\"GSE183947\"}"
}

// Response 422 — unrecognised prefix
{
  "error": "Unrecognised accession format",
  "hint": "Supported prefixes: GSE, GSM, GDS, SRR, SRX, SRS, SRP, ERR, ERX, ERP, DRR, DRP, PRJNA, PRJEB, E-MTAB-*, E-GEOD-*",
  "accession": "JUNK123"
}
```

**Typical agentic flow for "run RNA-seq on GSE183947":**
```
1. POST /api/accession/resolve  {accession: "GSE183947"}
   → prefilled_params: {accession: "GSE183947"}, workflow_id: 10672

2. POST /api/workflows/execute
   {workflowDefinition: {id: 10672, ...}, params: {accession: "GSE183947"}}
   → {id: "run-uuid", status: "pending"}

3. GET /api/workflows/runs/run-uuid/status  (poll until completed)

4. POST /api/workflows/runs/run-uuid/ai/analyze  {question: "top DE genes?"}
```

---

## File Operations

### `POST /api/files/preview`

Preview any file stored in S3 or pasted inline:

```json
// Request
{ "s3_key": "s3://biomate-nextflow-work/.../variants.vcf.gz", "file_type": "vcf" }
// or
{ "inline_data": ">seq1\nATCGATCG...", "file_type": "fasta" }

// Response 200
{
  "file_type": "vcf",
  "preview": "<table>...",
  "metadata": { "total_variants": 12450, "pass_rate": 0.87 }
}
```

### `POST /api/uploads/signed_url`

Get a presigned S3 PUT URL for direct large-file upload:

```json
// Request
{ "filename": "sample.fastq.gz", "content_type": "application/gzip" }

// Response 200
{
  "upload_url": "https://biomate-nextflow-work.s3.amazonaws.com/inputs/user-42/abc123/sample.fastq.gz?X-Amz-...",
  "s3_key": "inputs/user-42/abc123/sample.fastq.gz",
  "s3_uri": "s3://biomate-nextflow-work/inputs/user-42/abc123/sample.fastq.gz",
  "expires_in": 3600
}
```

Upload directly to S3:
```bash
curl -X PUT "<upload_url>" \
  -H "Content-Type: application/gzip" \
  --data-binary @sample.fastq.gz
```

Then use `s3_uri` as a workflow input parameter.

---

## Memory

### `GET /api/memory/relevant`

```
GET /api/memory/relevant?query=RNA-seq+DESeq2+human&scope=all&limit=5
```

Returns prior runs, procedures, and preferences relevant to the query.
Used by the `recall_memory` MCP tool. Requires authentication.

```json
{
  "runs": [ { "id": "uuid", "workflowName": "DESeq2", "status": "completed", ... } ],
  "findings": [...],
  "procedures": [...],
  "preferences": { "genome": "GRCh38", "strandedness": "reverse" }
}
```

---

## Export

### `POST /api/export/qc_report`

```json
// Request
{ "invocationId": "galaxy-invoc-id", "format": "html" }

// Response 200 (format=html)
// Content-Type: text/html
// Content-Disposition: attachment; filename="biomate_qc_report_abc12345.html"
// <self-contained HTML report>

// Response 200 (format=json)
{ "invocationId": "...", "run": { ... } }
```

---

## Internal / Galaxy Backend Endpoints

The Galaxy backend (port 8081) has additional endpoints not exposed through
the Node.js proxy. These are called by Node.js internally and are not
intended for direct external use.

| Galaxy endpoint | Called by Node.js | Purpose |
|----------------|-------------------|---------|
| `POST /api/nextflow/execute` | `POST /api/workflows/execute` | Launch Nextflow job |
| `POST /api/nextflow/cancel/:id` | `POST /api/workflows/runs/:id/cancel` | Cancel Nextflow subprocess |
| `GET /api/nextflow/steps` | Lazily on workflow card open | Fetch phase/step tree |
| `POST /api/nextflow/fetch_public_data` | `POST /api/data/fetch` | FTP → S3 download |
| `GET /api/remote_files/plugins` | `GET /api/data/sources` | List file source plugins |
| `GET /api/remote_files` | `GET /api/data/browse` | Browse file source path |
| `POST /api/ai_assistant/generate_workflow` | Workflow generation chat | LLM → workflow spec |
| `POST /internal/billing/llm_cost` | After each chat stream | Record LLM tokens to Lago |

---

## Tool → Endpoint Mapping (17 MCP Tools)

| MCP Tool | HTTP Endpoint | Auth |
|----------|--------------|------|
| `biomate_session` | `POST /api/open-claw/stream` | optional |
| `search_workflow` | `POST /api/workflows/search` | optional |
| `get_workflow_spec` | `POST /api/ai_assistant/generate_workflow` | optional |
| `run_workflow` | `POST /api/workflows/execute` | optional |
| `get_run` | `GET /api/workflows/runs/:id` | optional |
| `cancel_run` | `POST /api/workflows/runs/:id/cancel` | optional |
| `list_runs` | `GET /api/workflows/runs` | optional |
| `preview_file` | `POST /api/files/preview` | optional |
| `export_report` | `POST /api/export/qc_report` | optional |
| `analyze_results` | `POST /api/workflows/runs/:id/ai/analyze` | **required** |
| `explain_error` | `POST /api/workflows/explain_error` | optional |
| `query_database` | `POST /api/databases/query` | optional |
| `resolve_accession` | `POST /api/accession/resolve` | **required** |
| `browse_data` | `GET /api/data/browse` | **required** |
| `fetch_public_data` | `POST /api/data/fetch` | **required** |
| `recall_memory` | `GET /api/memory/relevant` | **required** |
| `upload_file` | `POST /api/uploads/signed_url` | optional |

"required" = `authenticateStaticApiKey → authenticateToken` chain.
"optional" = `optionalAuth` (works anonymously but user-scoped features require auth).
