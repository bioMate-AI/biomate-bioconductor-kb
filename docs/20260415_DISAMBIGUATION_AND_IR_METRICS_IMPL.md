# Disambiguation Guardrail & IR Metrics — Implementation Plan

**Date:** 2026-04-15  
**Status:** Implementation complete; tests pending

---

## 1. Problem Statement

### 1a. Routing ambiguity without user feedback

BioMate's current routing silently picks the top-scored workflow even when multiple plausible candidates score within 3 points of each other. This causes:

- User frustration when the system picks wrong and they have to re-describe from scratch
- Feedback loss: the system never learns what the user actually wanted
- False precision: a score gap of 7.8 vs 7.2 is not diagnostically meaningful

**Solution:** When routing is ambiguous, surface the top candidates and let the user pick. This is the "interactive guardrail" — the multi-tier search system still does the work, but when it cannot confidently commit, it asks before proceeding.

### 1b. Routing evaluation measures end-to-end LLM quality, not search quality

The existing routing benchmark (chat mode) measures whether the correct workflow appears in the LLM's text response. This conflates two independent quality axes:
- **Search layer:** does the correct workflow appear in the ranked list at all?
- **LLM layer:** does the LLM pick the right one from the candidates it receives?

**Solution:** Add an IR evaluation mode that calls the search layer directly and measures MRR, P@K, NDCG@K — the standard information retrieval metrics — so we can diagnose each layer independently.

---

## 2. Architecture

### 2a. Disambiguation flow

```
User query
    ↓
[Chain search] → match found → return chain plan (unchanged)
    ↓ no match
[Iterative workflow search] → top-N results
    ↓
Disambiguation gate:
  IF match_type != 'high_confidence'     (top score < 12.0)
  AND len(plausible) >= 2               (at least 2 results score ≥ 6.0)
  AND gap(#1, #2) < 3.0                 (top two within 3 points of each other)
    → return workflow_type='disambiguation' with candidate list
  ELSE
    → proceed to Step 2 (template reuse / adapt / generate)
    ↓
[WorkflowDisambiguationCard in frontend] → user selects candidate
    ↓
onAdjustViaChat("I want to use <display_name>")
    ↓
[Second turn] explicit name → high_confidence match → workflow panel
```

### 2b. Threshold rationale

| Threshold | Value | Rationale |
|---|---|---|
| `_DISAMBIG_MIN_SCORE` | 6.0 | Matches `_MATCH_SCORE_MED` — anything below is not a plausible candidate |
| `_DISAMBIG_GAP_THRESHOLD` | 3.0 | Empirically: < 3.0 = genuinely ambiguous; > 3.0 = clear leader |
| `high_confidence` bypass | score ≥ 12.0 | No point asking user when one workflow clearly dominates |

### 2c. IR evaluation architecture

```
query
  ↓
/api/ai_assistant/search_ranked  (Python Galaxy backend: port 8081)
  ↓ proxied through
/api/ai_assistant/search_ranked  (Node.js proxy: port 5000)
  ↓
evaluation/adapters/routing_adapter.py::fetch_ranked_list()
  ↓
ir_metrics(ranked_names, correct_workflow, acceptable_alts)
  ↓ computes:
  MRR, P@1, P@3, NDCG@3, Hit@5
```

The search_ranked endpoint returns:
1. Chain matches first (cosine similarity ≥ 0.35)
2. Individual workflow matches ranked by multi-signal score (FTS + keyword + key-phrase + name-overlap + source-priority)

---

## 3. Files Changed

### Backend

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/ai_assistant.py` | Added disambiguation gate (lines ~2941–2981) between Step 1 search and Step 2 strategy decision |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Added `RankedSearchRequest` model + `search_ranked` endpoint (lines ~766–835) |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Raised Jaccard chain `min_score` 0.15→0.25; removed overfitting regex from `_detect_query_data_types`; removed `bulk_rnaseq_de_analysis` from `_CHAIN_REQUIRED_CONTEXT` |

### Frontend

| File | Change |
|---|---|
| `frontend/client/src/components/workflow-disambiguation-card.tsx` | New component — renders candidate selection cards with source badges |
| `frontend/client/src/components/chat-message.tsx` | Added `workflow_type === 'disambiguation'` branch (renders `WorkflowDisambiguationCard`); added import |
| `frontend/server/routes.ts` | Added `/api/ai_assistant/search_ranked` proxy route |

### Evaluation

| File | Change |
|---|---|
| `evaluation/adapters/routing_adapter.py` | Added `ir_metrics()`, `fetch_ranked_list()`, `_is_match()` static methods + updated docstring |
| `evaluation/runners/run_routing.py` | Added `--ir-mode` flag + IR summary block (MRR, P@K, NDCG@3, domain breakdown, miss analysis) |

---

## 4. Response Protocol

### `workflow_type = 'disambiguation'` response structure

```json
{
  "success": false,
  "workflow_type": "disambiguation",
  "message": "I found several workflows that could match your request. Which best fits what you need?",
  "candidates": [
    {
      "name": "nf-core/atacseq",
      "display_name": "ATAC-seq Analysis",
      "description": "Transposase-accessible chromatin profiling (ATAC-seq). Measures open chromatin regions...",
      "source": "nfcore",
      "format": "nextflow",
      "score": 9.2
    },
    {
      "name": "nf-core/chipseq",
      "display_name": "ChIP-seq",
      "description": "Antibody-based protein-DNA interaction profiling (ChIP-seq)...",
      "source": "nfcore",
      "format": "nextflow",
      "score": 8.7
    }
  ]
}
```

### User selection triggers

User clicks a candidate → frontend sends:
```
"I want to use <display_name>"
```

This message contains the exact pipeline name, which causes the backend to return a high-confidence match on the next turn.

---

## 5. Test Plan

### T1: Disambiguation trigger (manual)

**Precondition:** Backend running with updated `ai_assistant.py`

**Input queries that should trigger disambiguation:**
1. "Analyze chromatin accessibility changes between two conditions" — should offer atacseq + chipseq + cutandrun
2. "I want to do peak calling on my sequencing data" — should offer chipseq + atacseq + cutandrun
3. "Single-cell RNA-seq analysis starting from pre-processed data" — should offer scdownstream + scrnaseq

**Expected:** `workflow_type = 'disambiguation'` with ≥ 2 candidates

**Inputs that should NOT trigger disambiguation:**
1. "I have paired-end RNA-seq FASTQ files from human samples" — high-confidence rnaseq match
2. "Run nf-core/sarek on my WGS tumor-normal pair" — explicit name → skip disambiguation
3. "Align my Drop-Seq reads and generate a count matrix" — scrnaseq should dominate

### T2: Frontend card rendering (manual)

**Method:** Send a mock `workflow_type = 'disambiguation'` message via chat (or mock via dev tools)

**Expected:**
- Card shows workflow names + source badge (nf-core / BioMate / Bioconductor color-coded)
- Description snippet truncated to 2 lines
- Clicking a card sends "I want to use <display_name>" to chat
- Second turn returns the actual workflow panel

### T3: IR metrics (automated)

**Command:**
```bash
cd /home/yzhang/biomate/evaluation
python3 runners/run_routing.py --ir-mode --output results/routing_ir_v1/ --workers 5
```

**Expected targets:**
- MRR ≥ 0.80
- P@1 ≥ 0.70
- NDCG@3 ≥ 0.85
- Hit@5 ≥ 0.95

**Baseline (v1 IR run, 2026-04-15):**
```
MRR     = 0.847
P@1     = 0.742
NDCG@3  = 0.920
Hit@5   = 0.967
```
All 4 targets met.

### T4: Chat mode benchmark (automated)

**Command:**
```bash
python3 runners/run_routing.py --output results/routing_v3/ --workers 3
```

**Target:** Mean ≥ 0.80, Exact ≥ 78% (up from 74% baseline)

**Note:** The disambiguation gate returns `success=False` — the routing benchmark adapter may score this as 0.0 if it cannot parse the candidate list. The adapter should be updated to check for correct_workflow in the `candidates[*].name` list as an alternative extraction path.

### T5: Disambiguation + second-turn routing (E2E)

**Not yet implemented.** An E2E Playwright test should:
1. Send an ambiguous query
2. Assert `data-testid="disambig-candidate-*"` cards appear
3. Click the correct candidate
4. Assert the workflow panel (`data-testid="workflow-artifact-panel"`) loads

---

## 6. Evaluation for Workflow Generation Path

When `match_type = 'no_match'` (score < 6.0) or the query asks for something genuinely novel, BioMate generates a Nextflow workflow from scratch using the LLM. This path requires different evaluation:

### 6a. Component accuracy (what to measure)

| Metric | Description |
|---|---|
| Tool recall | Fraction of expected tools that appear in the generated workflow |
| Tool precision | Fraction of generated tools that are relevant (no hallucinated tools) |
| Structural validity | Does the generated `.nf` file parse without errors? |
| Parameter validity | Are parameters within valid ranges for the tools used? |

### 6b. Proposed evaluation approach

1. **LLM-as-judge:** For each generated workflow, ask Claude (or GPT-4) to evaluate:
   - "Does this workflow address the stated biological goal?"
   - "Are the tools correct and in the right order?"
   - "Are the parameters biologically meaningful?"
   - Output: pass/fail per criterion (binary) or 1–5 score

2. **Reference set:** Build a small (20–30 query) "generation benchmark" with:
   - Queries that have no direct nf-core match
   - Expert-annotated expected tool sets
   - Used to measure recall/precision against ground truth

3. **Parsability check:** Run `nextflow config <generated.nf>` to verify syntax

This is not yet implemented. Priority after disambiguation guardrail is stable.

---

## 7. Outstanding Items

- [ ] E2E Playwright test for disambiguation card (T5 above)
- [ ] Update `RoutingBenchmarkAdapter.score()` to extract from `candidates[*].name` when `workflow_type = 'disambiguation'` (currently scores 0.0 for disambiguation responses)
- [ ] Workflow generation evaluation benchmark (6a/6b above)
- [ ] Monitor disambiguation trigger rate in production — if > 30% of queries trigger it, thresholds need tuning
- [ ] Add `reasoning` field to disambiguation response so the card can explain WHY the system is uncertain
