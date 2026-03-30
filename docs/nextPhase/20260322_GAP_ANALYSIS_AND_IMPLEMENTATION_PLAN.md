# Next Phase: Gap Analysis & Implementation Plan
**Date**: 2026-03-22  
**Branch**: `integration/next-phase`

---

## Status of A1 (Input/Output Type Columns)

**Status: ✅ FULLY IMPLEMENTED — no work needed.**

`input_types` and `output_types` columns exist in the `workflows` SQLite table and are **populated for every workflow**:

| Source | Total | Has input_types | Has output_types |
|---|---|---|---|
| bioconductor | 1818 | 1818 | 1818 |
| nfcore | 230 | 230 | 230 |
| biomni_nextflow | 296 | 296 | 296 |
| biomate | 2 | 2 | 2 |
| Others | 99 | 99 | 99 |
| **Total** | **2445** | **2445** | **2445** |

The output→input type wiring is also implemented in `workflow_chain.py` (the chain executor uses `output_types` and `input_types` for compatibility checking in the resolver endpoint `POST /api/workflows/runs/{run_id}/resolve-outputs`).

---

## Gap B4: Multi-Step Sequential Intent → `pipeline_steps`

### What's there
- `galaxy-assistant.ts` has a multi-intent system that **fans out** multiple intents in **parallel**.
- `chat-message.tsx` already handles `workflow_type === 'pipeline'` with `pipeline_steps: [...]` — it renders `PipelineListView`.
- `PipelineListView` calls `POST /api/workflows/chain` on confirm.
- `workflow_chain.py` backend is 651 lines and fully implements sequential chain execution.

### What's missing
**The galaxy-assistant never emits `workflow_type: 'pipeline'` with `pipeline_steps`.**

When a user says "RNA-seq then DE then pathway enrichment", the multi-intent system processes each as a parallel independent result, picking only one as `generatedWorkflow`. The sequential ordering, output→input wiring, and `pipeline_steps` array are never set.

### Implementation Plan

**File**: `frontend/server/galaxy-assistant.ts`

1. **Detect sequential intent** in `analyzeUserIntent()`:
   - Trigger words: "then", "followed by", "after that", "pipeline of", "chain:", "step 1 ... step 2"
   - Add `isSequential: boolean` field to `IntentDecomposition`

2. **In `processMultiIntent()`**: when `isSequential === true`, instead of picking one primary workflow:
   - Collect all sub-intent workflows as ordered steps
   - Map each to a `PipelineStep`-compatible object:
     ```ts
     { id, workflow_name, nextflow_path, params, status: 'pending',
       input_from: previousStepId, uses_description: "output of step N" }
     ```
   - Return response with:
     ```ts
     generatedWorkflow: {
       workflow_type: 'pipeline',
       name: '<derived chain name>',
       pipeline_steps: [...],
       success: true,
     }
     ```

3. **In the `analyzeUserIntent` LLM prompt**: add instruction to set `is_sequential: true` when intents are ordered (step feeds next).

**Effort**: ~2–3 hours. Moderate complexity.

---

## Gap B3: Frontend Proxy for `/api/workflows/chain`

### What's there
- Backend `POST /api/workflows/chain` is fully implemented (651-line `workflow_chain.py`).
- Backend `GET /api/workflows/chain/{chain_run_id}` is also implemented.
- `chat-message.tsx` already calls `fetch('/api/workflows/chain', ...)` on confirm.

### What's missing
**`frontend/server/routes.ts` has no proxy for `/api/workflows/chain`.**  
The frontend Express server intercepts all `/api/*` calls. Without a proxy entry, the fetch from `chat-message.tsx` returns a 404.

### Implementation Plan

**File**: `frontend/server/routes.ts`

Add two proxy routes alongside the existing `preflight`, `estimate_cost`, `validate_profile` proxies:

```ts
// POST /api/workflows/chain — submit a sequential chain run
app.post("/api/workflows/chain", optionalAuth, express.json(), async (req, res) => {
  const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
  const resp = await fetch(`${galaxyUrl}/api/workflows/chain`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req.body),
  });
  const data = await resp.json();
  res.status(resp.status).json(data);
});

// GET /api/workflows/chain/:chainRunId — poll status
app.get("/api/workflows/chain/:chainRunId", optionalAuth, async (req, res) => {
  const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
  const resp = await fetch(`${galaxyUrl}/api/workflows/chain/${req.params.chainRunId}`);
  const data = await resp.json();
  res.status(resp.status).json(data);
});
```

**Effort**: 15 minutes. Very low risk.

---

## Gap D4: Error Recovery UX

### What's there
- `nextflow-workflow-viewer.tsx` shows `status === 'failed'` and `status === 'running'`.
- The terminal output panel shows raw Nextflow logs.
- No LLM-based error explanation or actionable recovery buttons.

### What's missing
When a workflow fails, users see raw Nextflow stacktraces. They need:
1. **Human-readable error summary** — "What went wrong and why"
2. **Suggested fix action** — "Try adding `--genome GRCh38`" or "Missing Docker image"
3. **"Fix & Retry" button** — pre-fills the chat with a fix suggestion

### Implementation Plan

**Backend** (`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`):
- Add endpoint `POST /api/workflows/explain_error`:
  - Input: `{ run_id, error_log: str, workflow_name: str }`
  - LLM call: parse the Nextflow log, classify error type (missing param, Docker failure, resource limit, data format), return `{ error_type, human_summary, suggested_fix, chat_prompt }`

**Frontend proxy** (`frontend/server/routes.ts`):
- Add `POST /api/workflows/explain_error` proxy

**Frontend UI** (`frontend/client/src/components/nextflow-workflow-viewer.tsx`):
- In the `status === 'failed'` section, add:
  - "Analyzing error..." spinner (triggered automatically after failure detected)
  - Error explanation card with `human_summary` and `suggested_fix`
  - "Fix & Retry" button that calls `onAdjustViaChat` with the `chat_prompt`

**Effort**: 3–4 hours. Backend LLM call + UI card.

---

## Gap C2: Data-Dependent Parameter Auto-Fill

### What's there
- `backend/lib/galaxy/ai/pilot_analysis/registry.py` — registry of data characterization analyzers
- `POST /api/workflows/preflight` — 3-phase check (parameters, inputs, structure)
- `nextflow-workflow-viewer.tsx` — renders parameter fields

### What's missing
When a user uploads a file, the system doesn't automatically infer parameter values from the data characteristics. For example:
- FASTQ file → infer `genome` from species markers, `strandedness` from read layout
- VCF file → infer `build` from contig names
- CSV file → infer column names for `--sample_sheet` or `--input`

This requires:
1. **Data characterization step** — run analyzers from `pilot_analysis/registry.py` on uploaded files
2. **Decision tree** — map data characteristics to parameter suggestions with confidence
3. **UI auto-fill** — pre-populate parameter fields with badges showing "auto-detected from your data"

### Implementation Plan

**Phase 1 (Quick win)**: File-type detection
- In `POST /api/workflows/preflight`, for each `inputFile`, detect type (FASTQ, VCF, BAM, CSV, etc.)
- Run the matching analyzer from `pilot_analysis/registry.py`
- Return `parameter_suggestions: [{param_id, suggested_value, confidence, rationale}]`

**Phase 2 (Full)**: Wire suggestions into the UI parameter fields
- `nextflow-workflow-viewer.tsx`: when preflight returns `parameter_suggestions`, pre-fill matching fields with a "🔬 Auto-detected" badge
- User can override; badge stays to indicate AI-suggested value

**Effort**: Phase 1: 2–3 hours. Phase 2: 1–2 hours. Total: ~4 hours.

---

## Priority Order for Implementation

| Priority | Gap | Effort | User Impact |
|---|---|---|---|
| P0 | B3 (chain proxy) | 15 min | Unblocks PipelineListView from 404 |
| P1 | B4 (sequential intent) | 2–3 h | Enables real multi-step pipeline UX |
| P2 | D4 (error recovery) | 3–4 h | Critical for power users hitting failures |
| P3 | C2 (data-aware params) | 4–5 h | Reduces friction for first-time users |

---

## Implementation Session Progress

- [x] A1: Confirmed fully done — input_types/output_types populated for all 2445 workflows
- [x] B3: Proxy wired in routes.ts (`POST /api/workflows/chain` + `GET /api/workflows/chain/:id`)
- [x] B4: Sequential intent detection + `pipeline_steps` emission in galaxy-assistant
  - Added `isSequential` to `IntentDecomposition`
  - LLM prompt now detects trigger words ("then", "followed by", "step 1...step 2")
  - New `processSequentialPipeline()` method builds `{workflow_type: 'pipeline', pipeline_steps: [...]}` response
  - `chat-message.tsx` (already built) will render PipelineListView for these responses
- [x] D4: Error recovery UX — backend + frontend
  - Backend: `POST /api/workflows/explain_error` in `ai_assistant.py` (LLM + regex fallback)
  - Frontend proxy: `routes.ts`
  - UI: Error recovery card in `nextflow-workflow-viewer.tsx` auto-triggered on failure, with "Fix & Retry via Chat" button
- [x] C2 Phase 1: `_infer_param_suggestions()` added to `nextflow_executor.py`
  - File-type decision table: FASTQ→strandedness, BAM→skip_alignment, CSV→input/samplesheet, H5AD→input_format, etc.
  - `parameter_suggestions` now included in `POST /api/workflows/preflight` response
  - UI auto-fill (C2 Phase 2) deferred: requires viewer to receive uploaded file paths

## Remaining Work

- [ ] C2 Phase 2: Wire `parameter_suggestions` from preflight response into workflow viewer parameter fields (auto-fill with "🔬 detected" badge)
- [ ] B4 test: Verify sequential pipeline triggers correctly for "RNA-seq then DE" queries
- [ ] D4 test: Verify error card appears and chat prompt is correct on workflow failure
