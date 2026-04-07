# Session: Bug Fixes & Full System Audit
**Date**: 2026-03-30  
**Branch**: `integration/next-phase`  
**Final audit result**: 10/10 endpoints green

---

## Issues Found and Fixed

### 1. TypeScript Errors (4 pre-existing, 1 new from session)

| File | Error | Fix |
|------|-------|-----|
| `galaxy-assistant.ts` | Backticks inside template literal broke TS parser — the sequential pipeline documentation section used backtick-quoted code spans (`` `"is_sequential": true` ``) which terminated the template string | Replaced with plain double-quoted text |
| `routes.ts` | `finalStatus === 'ok'` — dead code, TS type is `'completed'\|'error'` | Changed to `=== 'completed'` (which was the intent) |
| `chat-message.tsx` | `executionStatus` union type didn't include `'ok'\|'error'` (Galaxy API values) | Widened via `as string` cast |
| `structure-viewer.tsx` | `import * as $3Dmol from '3dmol'` — package not installed | Ran `npm install 3dmol` (package has built-in types at `build/types/index.d.ts`) |

After fixes: **`npx tsc --noEmit` returns 0 errors**.

---

### 2. B3 Chain Proxy Field Normalization

**Problem**: `chat-message.tsx` calls `POST /api/workflows/chain` with `workflow_steps: [...]` but the Galaxy backend (`workflow_chain.py`) expects `steps: [...]`. The proxy was passing the body through verbatim, causing a 400 validation error.

**Fix**: Updated the proxy in `routes.ts` to normalize the payload:
```ts
const rawSteps = req.body?.steps || req.body?.workflow_steps || [];
const backendBody = {
  chain_run_id: req.body?.chain_run_id,
  steps: rawSteps.map((s: any) => ({
    nextflow_path: s.nextflow_path || s.nextflowPath || s.workflowPath || s.workflow_path,
    params: s.params || s.parameters || {},
  })),
};
```

**Verification**: `chain_run_id=chain_1774831507_25bb0d` returned successfully.

---

### 3. D4 Error Explanation — `anthropic` Missing in Galaxy Venv

**Problem**: `POST /api/workflows/explain_error` returned 500 with `ModuleNotFoundError: No module named 'anthropic'`. The Galaxy backend runs in its own virtualenv (`backend/.venv`) which didn't have the Anthropic SDK.

**Fix**: Installed into Galaxy venv:
```bash
/home/yzhang/biomate/backend/.venv/bin/pip install anthropic
# → anthropic-0.86.0 installed
```

**Note**: `llm_used=False` in current audit because `ANTHROPIC_API_KEY` is not set in the running Galaxy process environment. The LLM path requires the key. The regex fallback is functional and returns structured responses. To enable LLM analysis, set `ANTHROPIC_API_KEY` in Galaxy's startup environment.

---

### 4. Domain Taxonomy — 0 Domains Returned

**Problem**: `GET /api/user/domain-taxonomy` returned `{"domains": {}, "labels": {}}`. The import of `DOMAIN_TAXONOMY` was gated behind `_DOMAIN_PROFILE_AVAILABLE` which requires `psycopg2` (PostgreSQL driver for agentic memory). Since `psycopg2` is not installed, the entire block failed, leaving `DOMAIN_TAXONOMY = {}`.

**Fix**: Separated the two imports in `ai_assistant.py`:
```python
# Taxonomy always works (no psycopg2 needed)
try:
    from galaxy.ai.domain_taxonomy import DOMAIN_TAXONOMY, DOMAIN_LABELS, get_topics_for_domains
except Exception as _dt_err:
    logging.warning(f"Domain taxonomy not available: {_dt_err}")

# Memory service is optional (requires psycopg2)
try:
    from galaxy.ai.memory.agentic_memory import get_memory_service as _get_memory_service
    _DOMAIN_PROFILE_AVAILABLE = True
except Exception as _dp_err:
    logging.warning(f"Domain profile memory not available: {_dp_err}")
```

Also removed the guard in `get_domain_taxonomy()` since taxonomy is always available.

**Verification**: Returns all 14 domains (genomics, transcriptomics, single_cell, epigenomics, proteomics, metabolomics, metagenomics, structural_biology, drug_discovery, cryo_em, pharmacology, systems_biology, synthetic_biology, bioimaging).

---

### 5. C2 Preflight Proxy — Input File Format Mismatch

**Problem**: The frontend proxy at `/api/workflows/preflight` only extracted `inputFiles` from a nested `workflowDefinition` structure. Direct API calls (and internal tests) send `input_files` at the top level — these were silently dropped.

**Fix**: Updated the proxy to accept both formats:
```ts
const { workflowDefinition, parameters, inputFiles, input_files, required_params } = req.body || {};
const backendBody = {
  input_files: input_files || inputFiles || [],
  required_params: required_params || (workflowDefinition?.parameters || []).filter(...),
  // ...
};
```

---

## Final Audit Results (10/10)

| # | Feature | Endpoint | Result |
|---|---------|----------|--------|
| 1 | Core — Frontend | `GET /api/health` | ✓ galaxy=connected |
| 2 | Core — Galaxy | `GET /api/version` | ✓ v25.1.dev0 |
| 3 | C1/C2 Preflight + Suggestions | `POST /api/workflows/preflight` | ✓ ready=True, params=[strandedness, skip_fastqc] |
| 4 | C1 Missing param detection | `POST /api/workflows/preflight` | ✓ ready=False, parameters=fail |
| 5 | D1 Cost estimation | `POST /api/workflows/estimate_cost` | ✓ $0.34–$1.56 USD |
| 6 | C3 Validate profile | `POST /api/workflows/validate_profile` | ✓ status returned |
| 7 | B3 Sequential chain | `POST /api/workflows/chain` | ✓ chain_run_id returned |
| 8 | D4 Error recovery | `POST /api/workflows/explain_error` | ✓ error_type + summary returned |
| 9 | B Domain taxonomy | `GET /api/user/domain-taxonomy` | ✓ 14 domains |
| 10 | Workflow catalog | `GET /api/ai_assistant/workflow_catalog` | ✓ 2445 workflows |

---

## System Examination Guide

The system is now ready for examination. Here is what to test:

### Sequential Pipeline (B4)
Send to chat: `"RNA-seq alignment then differential expression then pathway enrichment"`
- Expected: The AI detects sequential intent and renders a numbered `PipelineListView` showing 3 steps
- Backend key: `galaxy-assistant.ts` → `processSequentialPipeline()` → `{workflow_type: 'pipeline', pipeline_steps: [...]}`

### Error Recovery (D4)
Run any workflow → let it fail → observe the "⚠ Workflow Failed" recovery card
- The card shows human-readable error summary + suggested fix
- "Fix & Retry via Chat" button pre-fills the chat with a corrective message

### Parameter Suggestions (C2)
Call `POST /api/workflows/preflight` with a `.fastq.gz` input file
- Response includes `parameter_suggestions: [{param_id: "strandedness", suggested_value: "auto", ...}]`

### Chain Execution (B3)
The "Confirm & Run" button in `PipelineListView` now POSTs to `/api/workflows/chain` successfully

### Domain Profile (B)
`GET /api/user/domain-taxonomy` → 14 research domains with topics
The `DomainProfileSelector` UI component is available in the registration flow

### Workflow Catalog
2445 indexed workflows across 8 sources:
- nfcore (230), bioconductor (1818), biomni_nextflow (296), nfcore_subwf (93), others (8)

---

## Known Limitations

| Item | Status | Notes |
|------|--------|-------|
| D4 LLM error analysis | Regex fallback only | Set `ANTHROPIC_API_KEY` in Galaxy env to enable LLM |
| C2 Phase 2 UI auto-fill | Not implemented | Badges on param fields require threading input file list into viewer |
| Domain profile persistence | Read-only | Writes need psycopg2/PostgreSQL for agentic memory |
| B4 sequential pipeline | LLM-dependent | Quality depends on Claude detecting "then/followed by" in user messages |
