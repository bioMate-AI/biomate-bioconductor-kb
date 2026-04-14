# BioMate Tool-Use Agent — Concrete Design

**Date**: 2026-04-04  
**Prerequisite reading**: `docs/20260404_AGENT_ARCHITECTURE_DESIGN.md`

---

## What Already Exists (Audit findings)

| Capability | Status | Location |
|---|---|---|
| Jupyter/RStudio launch | ✅ exists | `interactive-tool-launcher.tsx`, `/api/interactive-tools/launch` |
| Galaxy dataset preview (first N lines) | ✅ exists | `GET /api/outputs/:id/preview` |
| Galaxy dataset parse (VCF/FASTA/etc.) | ✅ exists | `GET /api/outputs/:id/parse` |
| Job stdout/stderr streaming | ✅ exists | `GET /api/galaxy/jobs/:jobId/stdout` |
| SSE streaming pipeline | ✅ exists | `POST /api/chat/stream` |
| Anthropic SDK wired | ✅ exists | `context-compressor.ts`, `galaxy-assistant.ts` |
| Anthropic `tool_use` block handling | ✅ exists (sanitizer) | `context-compressor.ts` |
| Tool definitions passed to Claude | ❌ not yet | — |
| Code execution endpoint | ❌ not yet | — |

**Key finding**: The Anthropic SDK is already in use and `tool_use` block handling exists in the context compressor (for sanitization). The missing piece is defining `tools` and passing them in the Claude API call.

---

## Phase 1 — Code Execution Tool

### Why not Galaxy Jupyter directly?

Galaxy's Jupyter/RStudio opens in a **new browser tab** and is designed for interactive human use. The LLM cannot send code to it and read back results — there is no programmatic loop. It is the right tool for when a researcher wants a full notebook session, but not for the LLM to execute code as part of a conversation turn.

**What we need instead**: synchronous code execution with captured output that fits inside a chat turn (< 10 seconds). Galaxy's job queue is too slow for this — typical overhead is 5–15 seconds just to schedule a job.

**Solution: a lightweight inline executor + Galaxy for longer jobs**

```
Fast path (< 10s): POST /api/code/run
  → Python subprocess in restricted subprocess (no network, /tmp only)
  → Captures stdout/stderr/output files
  → Returns in < 2s for typical data manipulation

Slow path (long-running analysis): 
  → Galaxy script runner tool via /api/tools
  → Returns job_id, polls for completion
  → LLM informs user "running in background"
```

The fast path handles 95% of ad-hoc intents (filter rows, count, plot, convert). The slow path escalates to Galaxy for anything that would take > 10 seconds.

### New endpoint: `POST /api/code/run`

```typescript
// Request
{
  language: 'python' | 'r' | 'bash',
  code: string,
  input_datasets: string[],      // galaxy_dataset_ids — mounted read-only at /data/
  timeout_seconds: number,       // default 15, max 60
}

// Response
{
  stdout: string,
  stderr: string,
  exit_code: number,
  output_files: Array<{          // files written to /output/ by the script
    name: string,
    path: string,
    size: number,
    preview: string,             // first 10 lines if text
  }>,
  duration_ms: number,
}
```

**Execution**: Python subprocess with `subprocess.run()` and `timeout`. The user's datasets are accessible at `/data/<galaxy_dataset_id>/<filename>` inside the subprocess. Output written to `/tmp/biomate_code_output/<session_id>/` is captured and returned.

Available libraries (pre-installed, no pip needed):
- `pandas`, `numpy`, `scipy`, `matplotlib`, `seaborn`
- `biopython`, `pysam`
- `json`, `csv`, `pathlib`, `re` (stdlib)

### Anthropic Tool Definition

```typescript
const CODE_RUN_TOOL = {
  name: "run_code",
  description: `Execute Python, R, or bash code on the user's uploaded datasets.
Use this for: filtering/subsetting data, format conversion, basic statistics, 
generating plots, exploring file contents, or any ad-hoc computation.
Input datasets are available at /data/<dataset_id>/<filename>.
Write output files to /output/ — they will be shown to the user.`,
  input_schema: {
    type: "object",
    properties: {
      language: { type: "string", enum: ["python", "r", "bash"] },
      code: { type: "string", description: "The code to execute" },
      input_datasets: { 
        type: "array", 
        items: { type: "string" },
        description: "galaxy_dataset_ids of files to make available at /data/"
      },
    },
    required: ["language", "code"],
  },
};
```

### UX: Code Block in Chat

The user described wanting the same experience as Claude Code — a short visible code window that can be expanded. Here's exactly how it would look:

**Chat message rendering for a `run_code` tool call:**

```
┌─ BioMate ──────────────────────────────────────────────────────────┐
│  I'll subset your table to the top 10 rows and run the pipeline.   │
│                                                                      │
│  ┌─ ⚙ Python ─────────────────────────── [Expand] [Copy] ─────┐  │
│  │  import pandas as pd                                          │  │
│  │  df = pd.read_csv('/data/abc123/samples.csv')                │  │
│  │  df.head(10).to_csv('/output/subset_10rows.csv', index=False)│  │
│  │  print(f"Saved {len(df.head(10))} rows")                     │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ✓ Ran in 0.3s · Output: subset_10rows.csv (10 rows)               │
│                                                                      │
│  Now submitting to the [pipeline name] workflow...                  │
└─────────────────────────────────────────────────────────────────────┘
```

The code block is collapsed by default to 3 lines, expandable to full view. Shows language, duration, output file summary. Identical mental model to Claude Code.

**New React component**: `CodeExecutionBlock` — a chat message variant that renders:
- Language badge + duration
- Collapsed/expanded code with syntax highlighting  
- Stdout (truncated to 500 chars, expandable)
- Output file previews (if any text/CSV/image files in /output/)
- Error state in red if exit_code ≠ 0

**SSE event type**: `code_execution` — carries `{code, language, stdout, exit_code, output_files}` in the existing streaming pipeline.

---

## Phase 2 — File Reading Tool

### Galaxy's dataset APIs are already suitable

BioMate already has:
- `GET /api/outputs/:id/preview` → first N lines of any text/table file
- `GET /api/outputs/:id/parse` → structured parse for VCF/FASTA/BED/GFF

The dataset IDs are already present in the chat context from the `[Uploaded datasets: ...]` block. The LLM already reads these from user messages. What's missing: the LLM can't *call* a preview endpoint — it can only see the dataset IDs in text.

### New Anthropic Tool: `read_file`

```typescript
const READ_FILE_TOOL = {
  name: "read_file",
  description: `Read and preview an uploaded dataset to understand its contents.
Use this before running code or dispatching a workflow — it lets you see the 
column names, data types, record count, and first rows without guessing.
Returns a structured preview regardless of file format (CSV, TSV, FASTA, VCF, etc.)`,
  input_schema: {
    type: "object",
    properties: {
      galaxy_dataset_id: { 
        type: "string", 
        description: "The galaxy_dataset_id from the [Uploaded datasets:] block" 
      },
      n_lines: { 
        type: "number", 
        default: 20,
        description: "Number of rows/records to preview" 
      },
    },
    required: ["galaxy_dataset_id"],
  },
};
```

**Backend**: routes to `GET /api/outputs/:id/preview?lines=20`, formats the result into a compact summary:

```
File: samples.csv | 847 rows × 12 columns | 34 KB
Columns: sample_id, condition, batch, reads_R1, reads_R2, ...
First 5 rows:
  sample_id  condition  batch  reads_R1
  S01        tumor      A      SRR123456
  S02        normal     A      SRR123457
  ...
```

This turns the `[Uploaded datasets: ...]` pattern from a one-way hint into a two-way capability. The LLM can now verify file contents before acting, rather than assuming.

### Better solution for large files: file summary endpoint

For files too large to preview meaningfully (BAM, large FASTQ), add `GET /api/outputs/:id/summary`:
- Returns: format, size, record count, key statistics (for FASTQ: total reads, mean quality; for VCF: variant count by type; for CSV: column names + dtypes + null counts)
- Computed once and cached

---

## Phase 3 — What Actually Changes With Workflow Dispatch as a Tool

This is the phase that needs the most clarification. Here is exactly what changes:

### Current architecture (two parallel processes)

```
User message
    │
    ├─→ generateResponse() ─────→ SSE event: {type: 'delta', text: "I'll run RNA-seq..."}
    │
    └─→ generateWorkflow() ─────→ SSE event: {type: 'workflow', workflowCard: {...}}
```

The two processes run independently. The response text and the workflow card are generated in parallel and arrive separately. The LLM's text response doesn't "know" what workflow was actually selected — it only knows the user intent. The LLM cannot conditionally generate a workflow card (e.g., "only generate a workflow if the pilot code succeeded").

### New architecture (single agent loop with tool calls)

```
User message
    │
    └─→ Claude agent loop:
            Turn 1: Claude reasons → calls run_code({code: "df.head(10)..."})
            Tool executes → returns {stdout: "Saved 10 rows", output_files: [...]}
            
            Turn 2: Claude sees result → calls dispatch_workflow({
              workflow: "rnaseq_pipeline",
              parameters: {reads: "output_subset.csv", ...}
            })
            Tool executes → returns {run_id: "abc", workflowCard: {...}}
            
            Final turn: Claude generates response incorporating both results
            SSE events: code_execution block + workflow card + text
```

### UX changes (what the user sees)

**Before**: response text appears, then workflow card appears below it, independently.

**After**: user sees a sequence of actions:
```
┌─ BioMate ────────────────────────────────────────────────┐
│                                                            │
│  ┌─ ⚙ Python ─────────────────────── ✓ 0.3s ──────┐     │
│  │  df.head(10).to_csv('/output/subset.csv')         │     │
│  └────────────────────────────────────────────────────┘     │
│                                                            │
│  ┌─ 🔬 Dispatch Workflow ────────── ✓ queued ──────┐    │
│  │  nfcore/rnaseq · subset.csv · 10 samples          │    │
│  └────────────────────────────────────────────────────┘    │
│                                                            │
│  Running pilot on 10 samples. Results will appear         │
│  in the workflow panel. [View workflow →]                  │
└────────────────────────────────────────────────────────────┘
```

Both tool calls are visible, collapsible, and auditable. The workflow card appears as the result of the dispatch tool, not as a parallel process.

### Backend changes

1. Add `dispatch_workflow` as a tool definition alongside `run_code` and `read_file`
2. When Claude calls `dispatch_workflow`, the backend runs the existing `generateWorkflow()` + `executeWorkflow()` logic and returns the result as a tool result
3. The SSE pipeline emits tool_result events that the frontend renders as collapsible blocks
4. Remove (or keep as fallback) the current parallel workflow generation — over time the tool call path replaces it

### What does NOT change

- The actual workflow execution infrastructure (Nextflow, Galaxy) is unchanged
- The workflow card component in the frontend is unchanged
- The existing workflow search, parameter filling, and execution logic is unchanged
- The only change is HOW the workflow dispatch is triggered — tool call instead of parallel process

---

## Phase 4 — Domain Knowledge Stays; Delivery Changes

You are right that domain knowledge is BioMate's unique value. The concern about tool_use replacing it is a misunderstanding — here's the clarification:

### Current problem: static injection wastes tokens and is always-on

When a user asks about RNA-seq, the current system injects ~800 tokens of cryo-EM guidance into the prompt. Wasted. When knowledge changes (new protocol, new tool recommendation), the prompt must be updated manually.

### Solution: domain knowledge becomes a retrievable tool, not a removed asset

The cryo-EM knowledge base we built (150-chunk RAG index, structured parameters DB, protocol JSON) is the perfect example. We already exposed it as `GET /api/cryo_em/context`. This endpoint IS the domain knowledge tool. We just expose it as an Anthropic tool instead of injecting it statically.

```typescript
const QUERY_KNOWLEDGE_TOOL = {
  name: "query_domain_knowledge",
  description: `Query BioMate's curated life science knowledge base.
Use this when you need:
- Protocol parameters for a specific experiment type (cryo-EM pixel size, RNA-seq parameters)
- Tool recommendations and comparisons for a specific domain
- QC thresholds, best practices, common failure modes
- BioMate's workflow catalog recommendations for a domain
This returns structured knowledge from peer-reviewed protocols and curated guidelines.`,
  input_schema: {
    type: "object",
    properties: {
      query: { type: "string", description: "What you want to know" },
      domain: { 
        type: "string", 
        enum: ["cryo_em", "rna_seq", "variant_calling", "proteomics", "drug_discovery", "general"],
        description: "The biological domain"
      },
    },
    required: ["query"],
  },
};
```

Backend routes to the appropriate knowledge endpoint:
- `cryo_em` → `POST /api/cryo_em/context` (the RAG pipeline we built)
- `rna_seq` → structured DB query (extend the same pattern)
- `drug_discovery` → structured workflow guidance
- `general` → BioMate's tool catalog + workflow search

### What this looks like in the chat

User: "What pixel size should I use for my 45 kDa membrane protein in nanodisc?"

```
┌─ BioMate ──────────────────────────────────────────────────────┐
│                                                                   │
│  ┌─ 📚 Domain Knowledge · cryo_em ───────────────── ▼ ──┐     │
│  │  Query: pixel size for 45 kDa membrane protein nanodisc│     │
│  │  Source: BioMate cryo-EM protocol database (150 chunks)│     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                   │
│  For a ~45 kDa protein in saposin nanodisc:                     │
│  **Pixel size: 0.649 Å/pixel** (mandatory — not a suggestion)   │
│  Total dose: 60 e⁻/Å², Box size: 256 px                         │
│  TOPAZ picking is required at this MW range.                     │
│                                                                   │
│  This is tighter than the general rule because nanodisc          │
│  constraints dominate over protein MW at this scale.             │
└───────────────────────────────────────────────────────────────────┘
```

### What stays in the system prompt

The system prompt does NOT become generic. It retains:

1. **BioMate's identity and mission**: "You are BioMate, a life science AI assistant for researchers. You automate workflows, analyze data, and draw on curated domain knowledge."

2. **Tool descriptions**: The 3–5 tool definitions (run_code, read_file, dispatch_workflow, query_knowledge, search_literature).

3. **Core behavioral rules** (condensed from 16 rules to ~4):
   - Never fabricate biological conclusions without tool-backed evidence
   - When in doubt about data format, call read_file before acting
   - For validated reproducible analysis, use dispatch_workflow not run_code
   - Domain knowledge is in the knowledge base — call query_knowledge for protocols

4. **Workflow routing hints** (brief, kept because they improve routing accuracy): the 5-line list of domain → workflow mappings stays.

What LEAVES the system prompt:
- The static DOMAIN_SPECIALIST_GUIDANCE strings (800+ tokens per domain) → replaced by query_knowledge tool
- The 12 hard constraint rules → replaced by 4 principles
- The static parameter tables → moved to knowledge DB

### Net effect on tokens

| Component | Before | After |
|---|---|---|
| Hard rules | ~400 tokens | ~80 tokens (4 principles) |
| Domain specialist blocks (all domains) | ~1200 tokens always | 0 tokens unless domain detected; then ~500 tokens fetched on demand |
| Workflow catalog | ~300 tokens | ~100 tokens (routing hints only) |
| Tool definitions | 0 | ~400 tokens |
| **Total** | **~1900 tokens** | **~580 tokens base + ~500 tokens on demand** |

The domain knowledge is MORE detailed (full RAG retrieval) but uses FEWER tokens in cases where it's not needed.

---

## Integration: How All Four Phases Work Together

```
User: "Run a pilot on the top 10 rows of my expression matrix, then if the 
       gene count looks reasonable, run the full differential expression pipeline"

BioMate agent loop:

  Step 1: read_file(galaxy_dataset_id="abc123")
  → "expression_matrix.csv | 15,847 genes × 24 samples | columns: gene_id, S01..S24"

  Step 2: run_code(python, "df.head(10).to_csv('/output/pilot.csv')")
  → "Saved 10 rows → pilot.csv"

  Step 3: dispatch_workflow(workflow="nfcore/rnaseq", params={reads: "pilot.csv"})
  → run_id="pilot_run_001", workflow_card shown

  [User sees pilot results]
  
  User: "Looks good, run the full dataset"

  Step 4: query_knowledge(domain="rna_seq", query="DESeq2 parameters for 24 samples 2-group")
  → "Recommended: padj_threshold=0.05, lfc_threshold=1.0, min_counts=10"

  Step 5: dispatch_workflow(workflow="nfcore/rnaseq", 
                            params={reads: "expression_matrix.csv",
                                    padj: 0.05, lfc: 1.0})
  → Full pipeline running
```

The researcher never writes code, never looks up parameters, never fills in forms manually. The agent reads their file, runs a pilot, checks the result, fetches the right parameters from the knowledge base, and scales up — all in a natural conversation.

---

## Implementation Sequence

| Step | What | Effort | Value |
|---|---|---|---|
| 1 | Add tool definitions to Claude API calls in `galaxy-assistant.ts` | 1 day | Unlocks all tool calls |
| 2 | `POST /api/code/run` — Python subprocess executor | 2 days | Phase 1 complete |
| 3 | `CodeExecutionBlock` React component | 1 day | Phase 1 UX |
| 4 | Wire `read_file` to existing `/api/outputs/:id/preview` | 1 day | Phase 2 complete |
| 5 | Agent loop in `galaxy-assistant.ts` (multi-turn tool calls) | 3 days | Core infrastructure |
| 6 | `dispatch_workflow` tool + remove parallel flow | 2 days | Phase 3 complete |
| 7 | `query_knowledge` tool routing to existing `/api/cryo_em/context` etc. | 1 day | Phase 4 complete |
| 8 | Shrink system prompt (remove static domain blocks) | 1 day | Token savings |
| **Total** | | **~12 days** | |
