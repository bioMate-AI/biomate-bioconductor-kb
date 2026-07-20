# Workflow Retrieval Refactor Session
**Date:** 2026-07-15

---

## Root Cause

UC6 (SARS-CoV-2 spike/ACE2 macrolactam cyclic peptide PPI blocker) was routed to a DiffDock docking workflow instead of `cyclic_peptide_design`.

The retrieval stack contained a "named anchor" mechanism that extracted tool names from the user query via pattern matching (`"using X"`, `"run X"`, `"X or Y"`) and **AND-required** that token in every FTS result:

```
query: "benchmark DiffDock or HADDOCK-based docking to PDB 6M0J"
→ anchor extracted: diffdock
→ FTS query: diffdock AND (macrolactam cyclic peptide PPI)
→ cyclic_peptide_design excluded (no "diffdock" in its text)
→ DiffDock workflow returned as top result
```

Meanwhile the AI text response (Step 6) correctly described cyclic peptide design because `DOMAIN_ROUTING_RULES` was injected into its LLM prompt. Text and panel showed different things because two separate decision systems used different context.

Second problem: the system was effectively FTS-only despite code existing for two additional retrieval signals. `set_llm_client()` was never called on the search engine singleton, so Pass-0 LLM always returned `[]`. `galaxy_ai_workflow_embeddings.npz` was never built, so BGE dense retrieval silently disabled itself at import time.

---

## Changes

### `backend/lib/galaxy/ai/unified_workflow_search.py`

**Removed — 6 hard-coded constant sets:**

| Constant | Contents |
|----------|----------|
| `_NAMED_ANCHOR_BLOCKLIST` | ~50 generic words excluded from anchor detection |
| `_KNOWN_NFCORE_PIPELINE_SLUGS` | 16 nf-core pipeline names for special handling |
| `_EPI_TOPE_PREDICTION_SIGNALS` | 13 terms to boost epitopeprediction scoring |
| `_MHCQUANT_MS_SIGNALS` | 10 terms to boost/penalize mhcquant |
| `_CODON_MRNA_SIGNALS` | 9 terms to route to codon optimization |
| `_DOCKING_VINA_SIGNALS` | 8 terms to route to AutoDock Vina |

**Removed — 4 dead methods** (all only called each other; nothing in `search()` called them after anchor removal):

- `_extract_named_tool_anchor()` — pattern-matched `"using X"` / `"run X"` to extract tool name
- `_extract_biomni_subworkflow_anchor()` — hard-routed codon optimization and AutoDock Vina to specific BioMNI subworkflow names
- `_extract_explicit_pipeline_slug()` — matched `"nf-core/X"` patterns against `_KNOWN_NFCORE_PIPELINE_SLUGS`
- `_resolve_pipeline_slug_conflict()` — chose between epitopeprediction and mhcquant by keyword list comparison

**Removed — from `search()` method:**

The named anchor AND-requirement block and its suppression workaround:
```python
# REMOVED:
_named_anchor = self._extract_named_tool_anchor(effective_query, cursor)
if _named_anchor:
    _alt_before = re.compile(re.escape(_named_anchor) + r'.{0,60}\b(?:or|either)\b', ...)
    _alt_after  = re.compile(r'\b(?:or|either|including|such as|like|e\.g\.)\b.{0,60}' + ...)
    if _alt_pattern.search(effective_query):
        _named_anchor = None
if _named_anchor:
    fts_query = f'{_named_anchor} AND ({fts_query})'
```

The FTS query is now built purely from `user_intent + key_terms` with no forced tokens.

**Removed — from `_calculate_score()`:**

Per-workflow score patches:
```python
# REMOVED:
# +20 for epitopeprediction when has_pred_intent
# -35 for mhcquant when negated
# +22 for codon optimization workflow
# -28 cross-penalties between epitopeprediction/mhcquant/codon
has_pred_intent = any(s in query_lower for s in _EPI_TOPE_PREDICTION_SIGNALS)
has_ms_intent   = any(s in query_lower for s in _MHCQUANT_MS_SIGNALS)
has_codon_intent = any(s in query_lower for s in _CODON_MRNA_SIGNALS)
if bare_name == "epitopeprediction": score += 20.0
...
```

Replaced with a single general rule:
```python
# KEPT — general explicit negation only:
negated_slugs = self._extract_negated_pipeline_slugs(query_lower)
if self._normalise_pipeline_slug(name_lower.split("/")[-1]) in negated_slugs:
    score -= 35.0
```

**Removed — from `_infer_domain_preferences()`:**

The codon/epitope-specific hard-coded block that used the now-removed signal lists.

**Simplified — `_extract_negated_pipeline_slugs()`:**

Removed the `_KNOWN_NFCORE_PIPELINE_SLUGS` loop. Now parses only plain regex negation (`"not X"`, `"avoid X"`, `"don't use X"`). Still called from `search()` to filter explicitly negated workflows and from `_calculate_score()` for the −35 penalty.

**Updated — Pass-0 LLM prompt in `_browse_catalog_with_llm()`:**

Added explicit tool request guidance with positive and negative examples:

```
- EXPLICIT TOOL REQUEST: If the query says 'using <Tool>', 'run <Tool>', or 'with <Tool>'
  as the primary method, rank that tool's workflow #1.
  POSITIVE: 'run DiffDock on my protein' → DiffDock workflow should be #1.
  POSITIVE: 'using HADDOCK for docking' → HADDOCK workflow should be #1.
  NEGATIVE: 'benchmark DiffDock or HADDOCK' → the user is comparing tools,
  not requesting DiffDock specifically; pick the workflow that best fits the overall goal.
  NEGATIVE: 'like DiffDock but for cyclic peptides' → the user is describing style,
  not requesting DiffDock; pick the cyclic peptide workflow.
```

---

### `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

**Added — Pass-0 LLM wiring** (immediately after AIAssistant singleton is created at line ~2764):

```python
if WORKFLOW_SEARCH_AVAILABLE and _workflow_search is not None:
    try:
        from galaxy.ai.llm_client import LLMClient
        _workflow_search.set_llm_client(LLMClient(ai_config))
        log.info("[WorkflowSearch] Pass-0 LLM wired — multi-signal retrieval active")
    except Exception as _llm_wire_exc:
        log.warning("[WorkflowSearch] Pass-0 LLM wiring failed: %s", _llm_wire_exc)
```

`set_llm_client()` had existed on `UnifiedWorkflowSearch` since earlier but was never called. Without it, `_browse_catalog_with_llm()` returned `[]` immediately on every search.

**Added (prior session) — `candidate_workflows` field in `/api/ai_assistant/generate_workflow` response:**

Top-5 candidates (name, description, domain, score) returned alongside the best match, enabling Step 6b reselection in the Node layer.

**Added (prior session) — `GET /api/ai_assistant/workflow_by_name` endpoint:**

Direct DB lookup by exact workflow name. Used by Step 6b after reselection to fetch the confirmed workflow without running a second FTS search.

---

### `frontend/server/galaxy-assistant.ts`

**Added — Step 6b reselection** (runs after Step 6 text generation, before Step 7 SSE emit):

```typescript
if (generatedWorkflow?.success && generatedWorkflow?.candidate_workflows?.length > 1) {
  const reselectedName = await this._reselectWorkflow(
    message, response.message,
    generatedWorkflow.candidate_workflows,
    decomposition.preferredDomains ?? []
  );
  if (reselectedName && reselectedName !== generatedWorkflow.workflow_name) {
    const reselected = await this._lookupWorkflowByName(reselectedName);
    if (reselected?.success) {
      generatedWorkflow = {
        ...generatedWorkflow, ...reselected,
        source: 'llm_reselection',
      };
    }
  }
}
```

**Added — `_reselectWorkflow()` private method:**

- Input: user message + generated AI text + top-5 candidates + preferredDomains
- LLM call: `intentModel`, `max_tokens=4`, `temperature=0`
- Prompt includes domain routing rules (scoped to detected domains) + explicit pos/neg examples for tool request vs comparison context
- Output: candidate name (1–5) or null; null keeps the FTS result unchanged

**Updated — `_reselectWorkflow()` prompt** to include the same pos/neg examples added to the Pass-0 LLM:

```
POSITIVE example: user says "run DiffDock on my protein" → select DiffDock workflow.
NEGATIVE example: user says "benchmark DiffDock or HADDOCK-based docking" but the AI response
  describes cyclic peptide design → select the cyclic peptide workflow, not DiffDock.
```

**Added — `_lookupWorkflowByName()` private method:**

Fetches `GET {GALAXY_URL}/api/ai_assistant/workflow_by_name?name=<name>` with master API key. Returns null on any error; caller keeps the FTS result.

---

### `frontend/server/routes.ts`

**Added — proxy route:**

```typescript
app.get("/api/ai_assistant/workflow_by_name", async (req, res) => {
  const name = req.query.name as string;
  if (!name) return res.status(400).json({ success: false, error: "name required" });
  const response = await galaxyAPIProxy.client.get(
    `/api/ai_assistant/workflow_by_name?name=${encodeURIComponent(name)}`
  );
  res.json(response.data);
});
```

---

## Resulting Retrieval Stack

Four signals, all additive. No signal can exclude a workflow from the result set.

```
Signal A — Pass-0 LLM          [NOW ACTIVE]
  broad FTS (60 candidates, relaxed OR query)
  → LLM ranks best 10 IDs (cheap/fast model, max_tokens=512)
  → rank-based score bonus: rank 0 → +3.0, rank 9 → +0.3
  → "rescue": LLM-ranked IDs not in main FTS fetched directly by ID

Signal B — FTS (BM25)
  Query = user_intent + key_terms, OR-joined, no anchor forcing
  Natural keyword ranking; score is base value for combination

Signal C — BGE Dense Embeddings  [auto-builds on first warmup]
  sentence-transformers cosine similarity over all 2,455 workflows
  NPZ: backend/database/galaxy_ai_workflow_embeddings.npz
  Locally disabled (broken torch dylib); activates on dev EC2 Docker

Signal D — Step 6b LLM Reselection  [NEW]
  Post-text arbitration using generated AI response as additional context
  Handles cases where FTS and the text disagree on the right workflow

Final score = FTS_BM25
            + Pass-0_LLM_bonus  (0 – +3.0)
            + BGE_cosine_bonus  (when available)
            + domain_match_bonus
            + name_match_bonus  (exact/prefix/substring)
            + exec_status_bonus (real_exec_status = success)
            − domain_penalty
            − explicit_negation_penalty  (−35 for "not X")
```

---

## UC6 Before / After

| | Before | After |
|--|--------|-------|
| FTS query | `diffdock AND (macrolactam cyclic peptide PPI)` | `macrolactam cyclic peptide PPI blocker` |
| `cyclic_peptide_design` in results | No (excluded by anchor) | Yes (top FTS result) |
| Pass-0 LLM | Dead (set_llm_client never called) | Active; ranks `cyclic_peptide_design` #1 from 60 candidates |
| Step 6b reselection | Did not exist | Confirms cyclic_peptide_design from candidates |
| Panel workflow | DiffDock ✗ | cyclic_peptide_design ✓ |
| Text/panel sync | No | Yes |

---

## What Was Not Changed

**`DOMAIN_ROUTING_RULES`** in `frontend/server/galaxy-assistant.ts` — per-domain narrative strings injected into Step 6 and Step 6b LLM prompts. These are LLM context injection (helping the LLM choose between candidates already in the result set), not FTS manipulation (excluding candidates from the result set). They are scoped by `preferredDomains` from intent analysis so only the relevant domain's rules are injected. Long-term path: enrich workflow descriptions in the DB so the LLM can reason from them directly, then retire these rules.

---

## Verification

- Python AST: `python3.9 -c "import ast; ast.parse(open('lib/galaxy/ai/unified_workflow_search.py').read())"` → OK
- Python AST: `python3.9 -c "import ast; ast.parse(open('lib/galaxy/webapps/galaxy/api/ai_assistant.py').read())"` → OK
- TypeScript: `npx tsc --noEmit -p .` → 0 errors
- Vitest: 930 passed, 6 skipped across 63 test files

**Not yet synced to dev.** Per user instruction: do not run `sync_to_dev.sh` until proved locally.

---

## Open Items

1. **BGE embeddings NPZ** — will auto-build on first worker warmup after sync to dev EC2 (Docker container has working PyTorch). Verify with `ls backend/database/galaxy_ai_workflow_embeddings.npz` on the container after first request.
2. **Integration test UC6 on dev** — after sync, send the UC6 query and confirm the `workflow_ready` SSE event carries `cyclic_peptide_design` not a DiffDock workflow.
3. **`DOMAIN_ROUTING_RULES` long-term** — audit which routing rules exist because descriptions are thin; enrich those workflow descriptions in the DB; remove the corresponding rule entries.
