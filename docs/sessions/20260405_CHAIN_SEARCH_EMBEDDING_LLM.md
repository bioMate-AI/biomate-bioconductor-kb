# 2026-04-05 — Chain Search: Embedding + LLM Reranking

## Problem

The previous chain matching used pure Jaccard token overlap.  It had three failure modes:

1. **Name not used** — `chain.name` and `chain.display_name` were absent from the token pool, so "bulk_rnaseq_de_analysis" would not score on a query containing exactly those words.
2. **No stemming** — "differentially" ≠ "differential"; "expressed" ≠ "expression".  Queries phrased naturally (as users type) failed to match.
3. **Ambiguous overlap** — `alternative_polyadenylation_analysis` has "differential APA genes" in its description, so DE queries matched it.  No mechanism to check full-scope alignment.
4. **No LLM involvement** — the top Jaccard result was returned directly with no cross-check.
5. **Scope mismatch** — "germline variant calling on WES" matched `rare_disease_multimodal_workup` (a 5-step chain) because germline+WES are components of it.  The system should ask for clarification instead of assuming the user wants the full chain.

---

## Solution

Three-tier chain search in `search_chains()`:

### Tier 1 — Embedding similarity

- **Model**: `all-MiniLM-L6-v2` (same as `VectorToolSearch`; shares the weights file)
- **Text per chain**: `name (underscores → spaces) + display_name + description + example_queries + tags`  — all fields, so name-exact matches score very high
- **Threshold**: `_CHAIN_EMBED_MIN_SIMILARITY = 0.42` (module constant)
  - Intentionally higher than single-workflow search.  Chains span multiple steps; a 0.30 hit means one component matches, not the full scope.  0.42 filters to cases where the query is semantically close to the whole chain.
- **Candidates**: top 3 above threshold are passed to LLM

### Tier 2 — LLM scope check + clarification

`_llm_select_chain()` receives the short candidate list and runs a single Haiku call (max_tokens=60).

**What the LLM is shown per chain:**
```
- chain_name: Display Name
  Scope: <description[:200]>
  Steps: step1, step2, step3, ...
```

**Rules given to LLM (in prompt):**
1. Match only if the query covers the chain's **full** scope (all major steps)
2. Partial component match → return `none`
3. Probable match but missing key context → return `clarify:<name>|<question>`

**Response format:**
- `chain:<name>` — confident full-scope match → return that chain
- `clarify:<name>|<question>` — scope probable but one detail needed → return chain with `clarification_needed=True` and `clarification_question` set
- `none` — no chain fits → return `[]` (fall through to single-workflow search)

None of this is domain-specific.  The prompt shows real chain data (steps, description) rather than baking in names.

### Tier 3 — Jaccard fallback

Used only when `sentence_transformers` is unavailable.  Now includes `chain.name` and `chain.display_name` in the token pool (they were absent before).

---

## Clarification flow in `ai_assistant.py`

When `top_chain.clarification_needed is True`, the chain lookup returns:

```python
{
    'success': False,
    'workflow_type': 'clarification',
    'message': <llm_question>,
    'clarification_question': <llm_question>,
    'candidate_chain': <chain_name>,
}
```

The response goes back to the user as a chat message.  On the next turn, the user's fuller answer re-triggers the full search pipeline.  If the answer confirms full scope, the chain launches; if not, single-workflow search finds the right simpler pipeline (e.g. `nf-core/sarek` for germline alone).

---

## No hardcoded chain/workflow/domain names

All logic is data-driven from the `workflow_chains` table:

- Chain names, display names, descriptions, steps are read at runtime from SQLite.
- The LLM prompt is constructed from that data — no chain names appear in code.
- Adding or removing a chain requires only a DB row change, not code.

---

## Constants introduced (all at module level)

```python
# unified_workflow_search.py, lines 36-41
_CHAIN_EMBED_MODEL_NAME    = "all-MiniLM-L6-v2"   # matches VectorToolSearch.DEFAULT_MODEL
_CHAIN_EMBED_MIN_SIMILARITY = 0.42                  # min cosine sim to reach LLM
```

`_CHAIN_EMBED_MODEL_NAME` matches `VectorToolSearch.DEFAULT_MODEL` — if the embedding model is ever upgraded, change both constants together (or consolidate to one).

---

## Pre-existing issues — status and resolution

### Confidence scale inconsistency (`ai_assistant.py`)

**Status: intentionally not unified.**

Each path calculates confidence differently because the inputs differ:

| Path | Scale | Meaning |
|---|---|---|
| FTS/scoring result | 0–12 float | Raw scoring sum (keyword hits, tag match, category bonus) |
| LLM reranker | 0.0–1.0 float | Semantic similarity, normalized |
| Chain embedding | 0.0–1.0 float | Cosine similarity |
| LLM scope check | 5 int | Qualitative mid-point when LLM returns `chain:` without a score |

These should remain as-is. Unifying them would require defining a single calibration function that converts across different measurement systems — that adds complexity for no product benefit. Downstream consumers (adapters, frontend) must treat `confidence` as a within-path relative signal, not a cross-path absolute.

### `REQUEST_INDICATORS` text matching (`prereq_recovery_adapter.py`)

**Status: resolved.** The aim — consistent templated output so adapters don't parse English — is now achieved via `event: needs_input` SSE.

Changes made in this session:

1. **`event: needs_input` extended** (`routes.ts`): now emitted for TWO cases:
   - `prerequisitesValidation.canRun === false` → `missing` = list of unmet param names
   - `workflow_type === "clarification"` → `missing` = `[clarification_question]`

   Previously, clarification responses fell through to `responseState = "workflow_failed"` — the event was never emitted. They are now correctly classified as `"needs_input"`.

2. **`event: needs_input` also sets `responseState`** in both endpoints: clarification is detected before the `workflowGenerationFailed` check.

3. **`biomate_client.py`**: `needs_input_fired` and `missing_from_event` now wired into `ChatResponse.needs_input` and `ChatResponse.missing_items`.

4. **`prereq_recovery_adapter.py`**: `_extract_what_was_requested` replaced by `_extract_what_was_requested_fallback`; loop detection uses `resp.needs_input` + `resp.missing_items` as primary signal, keyword heuristic as fallback only. `REQUEST_INDICATORS` renamed `_REQUEST_INDICATORS_FALLBACK`.

### `isDrugDevelopmentQuery` guard in streaming diagnostics (`routes.ts`)

**Status: resolved.**

The streaming endpoint's `workflowGenerationDiagnostics` had `if (!unresolvedWorkflowState || !isDrugDevelopmentQuery) return null` — it only fired for drug-related queries, and its reason/action text was drug-dev specific (ADMET, docking, PK/NCA).

Fix: removed `isDrugDevelopmentQuery` and `unresolvedWorkflowState` entirely. Replaced the drug-dev-specific content with the same generic conditional logic already present in the non-streaming endpoint (timeout/auth/tool/domain/confidence checks + generic follow-up questions). Both endpoints now produce identical diagnostic structure.

The unused `isDrugDevelopmentQuery` in the non-streaming endpoint was also removed.

### `_classify_match` magic numbers (`unified_workflow_search.py`)

**Status: resolved.** Promoted to module-level named constants:
```python
_MATCH_SCORE_HIGH = 12.0
_MATCH_SCORE_MED  = 6.0
```
`_classify_match` now references these instead of inline literals.

### Duplicate stopword sets (`unified_workflow_search.py`)

**Status: resolved.** Two inline sets (lines 733 and 1257) consolidated into one module-level constant:
```python
_SEARCH_STOPWORDS: frozenset = frozenset({
    "i", "want", "to", "the", "a", "an", "for", "with",
    "and", "or", "from", "in", "on", "my", "run", "perform",
    "execute", "do", "using", "via", "of", "at", "as", "by",
})
```
Both single-workflow tokenisation and chain Jaccard fallback now reference `_SEARCH_STOPWORDS`. Note: the chain set previously included more stopwords than the single-workflow set (`perform`, `execute`, `do`, `using`, `via`, `of`, `at`, `as`, `by`); the consolidated constant uses the superset so chain matching is unchanged.

---

## Behavior after change

| Query | Before | After |
|---|---|---|
| "Run differential expression analysis on RNA-seq data" | `alternative_polyadenylation_analysis` (wrong) | `bulk_rnaseq_de_analysis` |
| "Germline variant calling on whole exome" | `rare_disease_multimodal_workup` (scope mismatch) | Clarification: *"Do you have paired RNA-seq data? The full rare-disease pipeline includes RNA-seq outlier detection."* |
| "Run ADMET toxicity screening" | `drug_discovery_admet_gated_screening` | Clarification: *"Do you have a compound library for docking, or ADMET screening only?"* |
| "Align my FASTQ reads" | No chain (below threshold) | No chain — falls to single-workflow search |
| "DIA proteomics mass spectrometry" | No chain (correct: no proteomics chain registered) | No chain — falls to single-workflow search |

---

## Files changed

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Added `_CHAIN_EMBED_MODEL_NAME`, `_CHAIN_EMBED_MIN_SIMILARITY` constants; added `WorkflowChain.clarification_needed/clarification_question` fields; rewrote `search_chains` (embedding + LLM tiers); rewrote `_llm_select_chain` (scope check + clarify protocol); added `_rebuild_chain_embedding_index`, `_cosine_search_chains`, `_chain_embed_text` helpers; device detection via `vector_search._detect_device_safe` |
| `backend/lib/galaxy/ai/ai_assistant.py` | Chain lookup block: checks `clarification_needed`; if set, returns `workflow_type: 'clarification'` with question instead of launching chain |
| `frontend/server/routes.ts` | `runnableWorkflow` check extended to include chain results (`workflow_type === "chain" \|\| chain_name`); `event: workflow_ready` payload extended with `chain_name` and `chain_steps`; both streaming and non-streaming endpoints |
| `evaluation/core/biomate_client.py` | SSE parser captures `chain_name` and `chain_steps` from `event: workflow_ready`; `needs_input_fired` + `missing_from_event` wired into `ChatResponse.needs_input` / `ChatResponse.missing_items` |
| `evaluation/adapters/routing_adapter.py` | `score()` includes `chain_name + chain_steps` in search text so chain results score correctly |
| `evaluation/adapters/prereq_recovery_adapter.py` | Loop detection uses `resp.needs_input` + `resp.missing_items` as primary; keyword heuristic kept as fallback |
| `frontend/server/routes.ts` (2nd pass) | `responseState` in both endpoints: clarification classified as `"needs_input"` not `"workflow_failed"`; streaming `event: needs_input` covers clarification; removed `isDrugDevelopmentQuery` guard + drug-dev-specific diagnostic strings; streaming diagnostics now match non-streaming (generic, domain-agnostic) |
| `backend/lib/galaxy/ai/unified_workflow_search.py` (2nd pass) | Added `_MATCH_SCORE_HIGH`, `_MATCH_SCORE_MED`, `_SEARCH_STOPWORDS` module constants; removed two inline stopword literals + two magic number literals |
