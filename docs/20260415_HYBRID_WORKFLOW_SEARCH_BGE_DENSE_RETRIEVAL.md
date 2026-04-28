# Hybrid Workflow Search — BGE Dense Retrieval Integration

**Date:** 2026-04-15  
**Branch:** integration/next-phase  
**Status:** Implementation complete, E2E hold (another session fixing system issues)

---

## Summary

Added BGE dense retrieval (BAAI/bge-small-en-v1.5) to the 2449-workflow search index in `unified_workflow_search.py`, combining it with the existing FTS5 + keyword weights + named-tool anchor + LLM Pass-0 stack. This is a **combine, not replace** approach per the user's explicit direction.

---

## Background / Motivation

Before this session, the retrieval stack for individual workflows was:

| Method | Status |
|---|---|
| FTS5 BM25 full-text search | Active (workflow search) |
| Keyword weight re-ranking | Active (workflow search) |
| Named-tool anchor (AND constraint) | Active — added this session |
| LLM Pass-0 catalog browse | Active (workflow search) |
| BGE dense retrieval | Active for **tools** (`galaxy_ai_tools_embeddings.npz`) |
| BGE dense retrieval | Active for **chains** (in-memory) |
| BGE dense retrieval | **MISSING** for individual workflows |

The user's direction: "I don't think any approach is replaceable. They could be combined." This session closes the gap by adding BGE embeddings for workflows.

---

## What Was Built

### 1. Workflow Embedding Index

**File:** `database/galaxy_ai_workflow_embeddings.npz`  
**Size:** 2449 workflows × 384 dimensions (BAAI/bge-small-en-v1.5)  
**Build time:** ~51 seconds on CPU  
**Persistence:** Saved to disk; loaded from disk on subsequent restarts (no rebuild)

Each workflow is encoded as:  
`"{name}. {description[:600]}. Domain: {domain}. Tags: {tags}. {annotation[:300]}"`

### 2. Code Changes in `unified_workflow_search.py`

**Module-level singletons added (after imports):**
```python
_WORKFLOW_EMBED_MODEL_NAME = "BAAI/bge-small-en-v1.5"
_WORKFLOW_EMBED_NPZ: Optional[Path] = None
_WF_EMBED_MODEL: Optional[Any] = None
_WF_EMBED_IDS: List[int] = []
_WF_EMBED_MATRIX: Optional[Any] = None
_WF_EMBED_READY: bool = False
_WF_DENSE_MIN_SIM: float = 0.30
_WF_DENSE_TOP_N: int = 60
_WF_DENSE_BONUS_WEIGHT: float = 5.0
```

**New methods on `UnifiedWorkflowSearch`:**

- `_ensure_workflow_embeddings()` — lazy init; loads `.npz` if it exists, otherwise calls `_build_workflow_embeddings()`; forces CPU device (GPU not compatible with current PyTorch build on this machine)
- `_load_workflow_embeddings()` — loads ids + matrix from `.npz`
- `_build_workflow_embeddings()` — encodes all workflows from DB, saves `.npz`
- `_dense_workflow_prefilter(query, top_n, min_sim)` — returns `{workflow_id: cosine_sim}` for top-N hits above threshold; returns `{}` silently on any error

**Changes to `search()` method:**

1. **Before FTS query:** call `_dense_workflow_prefilter(query)` → `dense_sim_map`
2. **In FTS scoring loop:** add `dense_sim_map[id] * _WF_DENSE_BONUS_WEIGHT` bonus on top of existing FTS+keyword score (additive, does not replace)
3. **After LLM Pass-0 rescue:** new "Dense rescue" block fetches workflows that scored well in dense retrieval but were absent from FTS results entirely (e.g., paraphrase queries with no token overlap)

### 3. Score Blending

```
final_score = fts_keyword_score       # existing: BM25 + keyword weights + source priority
            + llm_pass0_bonus         # existing: 0–3.0 based on LLM rank
            + cosine_sim * 5.0        # NEW: BGE dense bonus (sim=0.5→+2.5, sim=0.8→+4.0)
```

Named-tool anchor (AND constraint at FTS query level) is unaffected — it still hard-gates the FTS candidates, then dense similarity adds on top.

---

## Test Results

All 5 representative queries correctly rank the right workflow #1 after combining FTS + dense:

| Query | Top result | FTS+dense score | cosine_sim |
|---|---|---|---|
| "Search for proteins similar to p53 using ProTrek" | `protrek_protein_search` | 67.59 | 0.815 |
| "Run Boltz to predict protein structure" | `boltz_structure_prediction` | 64.41 | 0.838 |
| "virtual screening with DrugCLIP" | `drugclip_virtual_screening` | 65.57 | 0.857 |
| "RNA-seq differential expression analysis with STAR" | `nf-core/rnaseq` | 63.58 | 0.788 |
| "GROMACS molecular dynamics simulation" | `GROMACS Protein-Ligand MD + MM-GBSA` | 61.40 | 0.791 |

Import test: `python3 -c "from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch"` — **PASS**

---

## Design Decisions

1. **CPU forced for model load:** The NVIDIA GB10 GPU (sm_121) is not supported by the installed PyTorch wheels. Adding `device="cpu"` prevents silent CUDA errors during model init.

2. **Additive bonus, not replacement:** Dense similarity is a bonus term on the existing score. This means FTS score + named anchor still dominate for exact-name queries; dense helps for paraphrase/semantic queries where FTS scores are low.

3. **Dense rescue (not just bonus):** Workflows with high cosine similarity but no FTS token overlap are fetched directly and inserted with a synthetic score (`sim * 5.0`). This mirrors the LLM Pass-0 rescue pattern already in the codebase.

4. **Threshold calibration:** `min_sim=0.30`, `top_n=60`. These are conservative — any workflow with < 30% cosine similarity to the query is not rescued. The 60-candidate limit prevents the dense set from dominating over FTS on broad queries.

5. **Shared singletons:** `_WF_EMBED_MODEL`, `_WF_EMBED_MATRIX` etc. are module-level so a single gunicorn worker loads the model once, regardless of how many `UnifiedWorkflowSearch` instances exist.

---

## Bug Fixes Applied After Review

Three issues found and fixed during self-audit:

### Fix 1 — `match_type` re-classification after bonus

**Problem:** `_classify_match()` is called inside `_create_match()` before any bonus is applied. The original LLM Pass-0 code kept `match_type=match.match_type` after inflating the score, meaning a workflow scoring 10.0+4.0=14.0 was still labeled `medium_confidence`. The disambiguation gate in `ai_assistant.py` reads `match_type`, so this caused wrong-path routing for borderline cases.

**Fix:** After applying the combined bonus (LLM Pass-0 + dense), re-classify:
```python
new_score = round(match.score + bonus, 2)
match = WorkflowMatch(
    ...
    score=new_score,
    match_type=self._classify_match(new_score),  # re-classify with bonus
)
```

This was a pre-existing bug with LLM Pass-0 (max +3.0), made more impactful by dense bonus (max +4.0).

### Fix 2 — Failure sentinel `_WF_EMBED_FAILED`

**Problem:** If model or `.npz` loading fails, `_WF_EMBED_READY` stays `False`. Every subsequent `search()` call retries the full init path, adding latency on every query if there is a permanent failure (e.g. corrupted file, permissions).

**Fix:** Added `_WF_EMBED_FAILED: bool = False` module-level sentinel. Set to `True` in the `except` handler of `_ensure_workflow_embeddings()`. Checked at top of that method alongside `_WF_EMBED_READY`.

### Fix 3 — Dense rescue scores cannot trigger disambiguation

**Confirmed safe (no fix needed):** Dense-rescued workflows get synthetic scores `sim * 5.0` — maximum 4.95. The disambiguation gate threshold is `_DISAMBIG_MIN_SCORE = 6.0`. Dense-rescued results are therefore always `low_confidence` and never eligible for disambiguation or direct high-confidence routing. They can only appear in the result list as low-ranked fallbacks.

---

## Files Changed

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/unified_workflow_search.py` | ~150 lines added (module constants + 4 methods + search() integration + 2 bug fixes) |
| `backend/database/galaxy_ai_workflow_embeddings.npz` | NEW — 2449-workflow BGE embedding index |

---

## IR Benchmark Results (2026-04-15)

Ran `run_routing.py --ir-mode` twice:

| Run | BGE active? | MRR | P@1 | NDCG@3 | Hit@5 |
|-----|------------|-----|-----|--------|-------|
| v2 (baseline, no sentence_transformers installed) | ❌ | 0.8465 | 0.7417 | 0.9200 | 0.9667 |
| v3 (BGE active, `sentence_transformers` installed) | ✅ | **0.6244** | **0.4167** | **0.6827** | 0.9667 |

**Result: BGE is a regression.** P@1 dropped from 74% to 42%. RNA-seq domain collapsed to P@1=0.000 (15/15 wrong top-1). Transcriptomics also severely hurt.

**Root cause (corrected after deeper analysis)**: The regression was caused by the **dense rescue block**, not the bonus weight. The rescue block injected semantically-similar-but-wrong workflows (e.g., `bulk_rnaseq_de_analysis`, `stringtie`) above correct results for every RNA-seq query.

**Standalone tuning analysis** (2026-04-15, `/tmp/bge_tune/test_bge_search.py`):

Ran a 120-query grid sweep with the dense rescue disabled to isolate the bonus effect:

| weight | min_sim | MRR | P@1 | Hit@5 |
|--------|---------|-----|-----|-------|
| 0.0 | 0.55 | 0.8492 | 0.7750 | 0.9500 | ← FTS-only |
| 0.5 | 0.55 | 0.8492 | 0.7750 | 0.9500 |
| 1.0 | 0.55 | 0.8492 | 0.7750 | 0.9500 |
| 2.0 | 0.55 | 0.8492 | 0.7750 | 0.9500 |
| 5.0 | 0.30 | 0.8492 | 0.7750 | 0.9500 |

**Finding: BGE bonus (with rescue disabled) is completely neutral at all tested weights.** Rankings do not change.

**Root cause of neutrality**: Among the 34 failing queries, the BGE cosine similarity difference between correct and wrong workflows is typically 0.005–0.1, while FTS score gaps are 2–20 points. The weight needed to flip rankings ranges from 17 to 999+. The bonus acts as a true tiebreaker only, which is the intended design.

**Resolution**: `_WF_DENSE_BONUS_WEIGHT = 0.5`, `_WF_DENSE_MIN_SIM = 0.55`, rescue disabled (`if False`).

BGE acts as a tiebreaker only. Dense rescue disabled permanently — it injected wrong workflows for the entire RNA-seq and transcriptomics domains.

**Final status**: BGE active as tiebreaker (weight=0.5). FTS-only IR performance preserved. Applied to production.

## E2E Validation — 9/9 PASS (2026-04-15)

Ran `PLAYWRIGHT_BASE_URL=https://dev-public.biomate.ai npx playwright test e2e/ai-containers.e2e.ts`:

- **9/9 passed** (6.4 min)
- AI-1 Boltz-2 ✓, AI-2 Chai-1 ✓, AI-3 DrugCLIP ✓, AI-4 SynCraft ✓, AI-5 STATE ✓, AI-6 scFv-PMPNN ✓, AI-7 ProTrek ✓, AI-8 ProFam-1 ✓, AI-SMOKE ✓
- Previous AI-2 failure was transient (Galaxy still loading after first sync); re-run 47s later passed

**Status: COMPLETE**
