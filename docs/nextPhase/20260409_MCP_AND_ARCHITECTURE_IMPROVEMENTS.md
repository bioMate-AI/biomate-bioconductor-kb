# MCP Server, AsyncLocalStorage, Memory P2 & Architecture Improvements

**Date:** 2026-04-09  
**Branch:** integration/next-phase  
**Session scope:** Claude Code integration plan items P1–P2 from `docs/20260401_CLAUDE_CODE_INTEGRATION_PLAN.md`

---

## 1. Germline Schema Quality Fix

### Problem
`wgs_germline_gatk` had two issues:
1. **No `nextflow_schema.json`** — all param metadata was regex-scraped from `main.nf`, causing `caller` to render as plain text (should be a select), `genome` to render as a file picker (should be a select of hg38/hg19/mm10), and descriptions were generic ("Workflow parameter: Caller").
2. **Duplicate DB entry** — ID 12655 had path `nextflow_nfcore/genomics/wgs_germline_gatk/main.nf` which resolves to `None` (file doesn't exist). FTS happened to rank ID 10685 first today, but a reindex could promote the broken entry → 0 params rendered in UI.

### Fix
- **Created** `backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/nextflow_schema.json` with 6 groups (17 params):
  - `input_options`: `reads` (required, file-path), `max_spots` (integer, min=0)
  - `reference_options`: `genome` (enum: hg38/hg19/mm10), `reference`, `known_sites`, `dbsnp_vcf`
  - `caller_options`: `caller` (enum: gatk/deepvariant/freebayes), `scatter_count` (1–64), `ploidy`, `min_base_quality_score`, `vqsr_mode` (boolean)
  - `sample_options`: `sample_id`, `platform` (enum: ILLUMINA/PACBIO/ONT/BGISEQ/CAPILLARY), `library`
  - `qc_thresholds`: `min_mean_coverage`, `min_alignment_rate`
  - `generic_options`: `outdir`, resource limits (hidden)
- **Deleted** DB entry ID 12655 (wrong path); only ID 10685 remains.

### Schema Coverage Status
Drug discovery: 18/19 (94.7%) ✅  
Genomics: 1/31 (germline fixed, 30 remaining) ⚠️  
All other domains: 0 coverage — backlog item

---

## 2. Memory P2: Cross-Session LTM Injection

### Problem
`buildMemoryContextPrompt()` in `memory-integration.ts` was defined but **never called**. User experience level, success rate, preferences, corrections, and project context were loaded into `enhancedContext` but never reached the LLM's system prompt.

### Fix
Three changes:
1. **`frontend/server/galaxy-assistant.ts`**: Added `ltmContextBlock?: string` to `ChatContext` interface. In `generateResponse()`, wraps it in `<long_term_memory>` tags and prepends to system prompt (both research and workflow branches).
2. **`frontend/server/memory-integration.ts`**: In `processWithMemory()` Step 4, calls `buildMemoryContextPrompt(enhancedContext)` and sets `enhancedContext.ltmContextBlock`.

### What gets injected (when data exists)
```
<long_term_memory>
## User Context
- Experience Level: Expert
- Workflow Success Rate: 87%
- Previous Workflows: 34

## User Preferences
- tool:10685: {"tool_id": 10685, "tool_name": "Wgs Germline Gatk"}

## Recent Corrections (avoid these mistakes)
- Suggested: {...} → Corrected: {...}

## Project Context
- Name: Cancer Genomics Study
- Domain: genomics
- Research Goal: Identify somatic mutations in TCGA samples
</long_term_memory>
```

### Noise/length assessment
- New users with no history: `buildMemoryContextPrompt()` returns empty or 3-line block → not noisy
- Experienced users: ~15–20 lines — acceptable
- `projectId` is rarely set → project sections mostly absent in current usage
- **Future gate**: only inject when intent involves workflow generation (not conversational turns)

---

## 3. AsyncLocalStorage Per-Request Context

**File:** `frontend/server/request-context.ts` (new)

Provides request-scoped context (`requestId`, `userId`, `sessionId`, `conversationId`, `startedAt`) via Node.js `AsyncLocalStorage`. Available anywhere in an async call chain without threading through function signatures.

```typescript
import { getRequestContext } from './request-context';

// In any async code during a request:
const ctx = getRequestContext();
logger.info({ requestId: ctx?.requestId }, 'Galaxy API call');
```

**Wired in** `routes.ts` immediately before the audit middleware — after the global `express.json()` body parser in `index.ts` (lines 37–38), so `req.body` is populated when the middleware runs.

**Response header**: `X-Request-Id: <uuid>` added to every response for client-side trace correlation.

---

## 4. BioMate MCP Server

**File:** `backend/mcp/biomate_mcp_server.py`  
**Protocol:** MCP 2024-11-05, stdio transport, JSON-RPC 2.0

### Tools (9 total)

| Tool | Backend endpoint | Notes |
|---|---|---|
| `chat` | `POST /api/chat/stream` (SSE) | Primary interface — NL → intent → workflow selection → AI params → optional execute |
| `search_workflows` | SQLite FTS (direct DB) | No HTTP, instant |
| `get_workflow_params` | Local filesystem (nextflow_schema.json or main.nf parse) | Returns types, enums, required flags |
| `list_runs` | `GET /api/invocations` | Recent runs with status |
| `get_run_status` | `GET /api/invocations/:id/nextflow/status` | Falls back to `/api/invocations/:id` |
| `get_output_files` | `GET /api/invocations/:id/outputs` | Includes download + preview URLs |
| `upload_file` | `POST /api/datasets/upload` | Returns file_path for use as workflow param |
| `research_query` | `POST /api/ai_assistant/research_query` | Literature search with citations |
| `rerun_workflow` | `POST /api/workflows/runs/:runId/rerun` | Nextflow -resume from checkpoint |

### v1.0 bugs fixed in v1.1
- `run_workflow` (v1.0) sent `{workflowName, params}` to `/api/workflows/execute` — wrong format, bypassed all of BioMate's AI. **Removed entirely.**
- `chat` (missing in v1.0) — the real execution path through BioMate's AI pipeline. Added as tool #1.
- `get_workflow_params` (missing) — reads nextflow_schema.json using same resolution logic as `_find_nf_file`. Added.
- `list_runs`, `research_query`, `rerun_workflow` (all missing). Added.

### Register with Claude Code CLI
```bash
export BIOMATE_URL=http://localhost:5000
export BIOMATE_API_TOKEN=<your-jwt>
claude mcp add biomate -- python3 /home/yzhang/biomate/backend/mcp/biomate_mcp_server.py
```

### Tested
- MCP protocol handshake: ✅ (initialize → tools/list → tools/call)
- `search_workflows("germline")`: ✅ returns 6 results from FTS
- `get_workflow_params("germline")`: ✅ reads new nextflow_schema.json, returns 17 params with enums
- `upload_file` with nonexistent path: ✅ graceful error
- `chat` with wrong BIOMATE_URL: ✅ returns connection error, no crash

---

## 5. DB-Backed Feature Flags

**File:** `frontend/shared/schema.ts` (new table), `frontend/server/feature-flags.ts` (new helper)

Replaces scattered `process.env.ENABLE_X` checks with a runtime-togglable system.  
See section 6 of `docs/20260401_CLAUDE_CODE_INTEGRATION_PLAN.md`.

### Schema
```sql
CREATE TABLE feature_flags (
  flag_name TEXT PRIMARY KEY,
  enabled BOOLEAN DEFAULT false,
  rollout_pct INTEGER DEFAULT 100,   -- 0-100: % of users who see this flag
  user_overrides JSONB,              -- {"userId": true/false} explicit overrides
  description TEXT,
  updated_at TIMESTAMP
);
```

### Usage
```typescript
import { isEnabled } from './feature-flags';

// Global flag
if (await isEnabled('ux_feedback')) { ... }

// Per-user flag (respects rollout_pct + user_overrides)
if (await isEnabled('new_param_panel', userId)) { ... }
```

---

## 6. Remaining Architecture Items (Claude Code Integration Plan)

| Item | Effort | Status |
|---|---|---|
| MCP server (galaxy_mcp_server.py) | ~1 week | ✅ Done (v1.1) |
| Per-request AsyncLocalStorage | ~2 days | ✅ Done |
| DB-backed feature flags | ~1 week | ✅ Done |
| RBAC tool flags (`isDestructive`, `requiredRole`) | ~3 days | 🔲 Next |
| Pluggable hook registry (`hook_registry.py`) | ~2–3 weeks | 🔲 Backlog |
| MCP client (consuming external bioinformatics servers) | Strategic | 🔲 Deferred |
