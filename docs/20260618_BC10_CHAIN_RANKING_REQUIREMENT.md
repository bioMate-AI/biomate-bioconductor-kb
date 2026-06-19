# Requirement: BC-10 chain_lookup picks variant_calling chain for single-cell query

**Date:** 2026-06-18
**For:** handoff to a focused chain-ranking session
**Companion to:** `docs/20260617_QC_CONFIG_BIOC_DESEQ2_REQUIREMENT.md` (same handoff format)
**Related:** BC-04 was fixed today via named-workflow detector (commit `92e7c2b6`); BC-10 needs a different fix.

## Problem (verified live, 2026-06-18)

For the query:

> *"I have expression data from 8,000 individual cells with UMI counts from a tumor biopsy. I want to find cell subpopulations and marker genes. What is the right analysis pipeline?"*

The chat-stream returns a workflow card, but the wrong workflow:

| Field | Value | Comment |
|---|---|---|
| `intentType` | `workflow_generation` | ✅ correct |
| `shouldGenerate` | `True` | ✅ correct |
| `workflowGenerated` | `True` | ✅ correct |
| `workflow.chain_name` | **`bioc_variant_annotation_workflow`** | ❌ **wrong** — variant_calling domain |
| `workflow.chain_domain` | `variant_calling` | ❌ for a clearly single-cell query |
| `workflow.confidence` | `9` (hardcoded by chain_lookup) | misleading — score is high because confidence is hardcoded, not computed |
| `response.preview` | "scrnaseq_standard_endtoend — End-to-end single-cell RNA-seq pipeline…" | ⚠️ **chat text and panel object disagree** |
| `all_chains[]` | `[bioc_variant_annotation_workflow, consensus_de_with_piano]` | both wrong-domain |

The LLM's prose response correctly identifies the use case as scRNA-seq and mentions `scrnaseq_standard_endtoend` (workflow id 14435), but the `workflow` object on the panel is the variant-calling chain. **User sees a panel that contradicts the AI's own answer.**

## Why the wrong chain wins — THREE distinct defects, not one

The chain_lookup at `backend/lib/galaxy/ai/ai_assistant.py:3367` calls:

```python
chain_results = self.workflow_search.search_chains(user_intent, min_score=0.35, limit=3)
```

Then takes `chain_results[0]` and hardcodes `confidence: 9`. `search_chains` itself has a three-tier pipeline (embedding → pre-filters → LLM verification → fallback). **All three protective layers fail for BC-10 for different reasons:**

### Defect 1 — LLM scope-check returns unparseable garbage

Verified in live Galaxy log (`/tmp/galaxy_restart.log`):
```
[ChainIndex] LLM raw response: '*'
[ChainIndex] LLM response unrecognized: '*'
[UnifiedWorkflowGeneration] Chain match: bioc_variant_annotation_workflow (4 steps)
```

`_llm_select_chain` at `unified_workflow_search.py:2072` prompts the LLM (Gemini 3.1 Pro) to return one of `chain:<name>`, `clarify:<name>|<question>`, or `none`. The LLM returned literally `'*'`. The parser doesn't recognize it, logs a warning, and **falls through to `return None`** at line ~2160. The caller interprets `None` as "LLM unavailable" and trusts the embedding ranking — which is wrong.

**This is the load-bearing defect.** The LLM verification IS in place but its parse-failure path is too permissive. A garbage response should not be treated as "unavailable" — it should either retry, escalate to a different model, or refuse to return a chain.

### Defect 2 — fallback policy returns the embedding's top hit even when LLM verification failed

`unified_workflow_search.py:2421-2422`:
```python
# LLM unavailable — trust embedding ranking
return top_candidates[:limit]
```

"LLM unavailable" is conflated with "LLM verification failed." The right behavior is **different**:
- LLM unavailable (network error, no provider): yes, fall back to embedding
- LLM responded with garbage: treat as "couldn't verify"; better to surface no chain than the wrong chain

### Defect 3 — embedding ranking is brittle for biomedical text

The chain embedding is `all-MiniLM-L6-v2` over `name + display_name + description + example_queries + tags`. For BC-10:
- `bioc_variant_annotation_workflow.example_queries` contains `"tumor variant summary oncoplot"` — token "tumor" matches the user's "tumor biopsy"
- `bioc_scrna_cluster_v2.example_queries` contains `"single cell analysis from raw counts"`, etc.

MiniLM is undertrained on biomedical text and gives the shared "tumor" token enough weight to put `variant_annotation` above any scRNA chain, even though the user's query has 4+ scRNA-specific tokens (`individual cells`, `UMI counts`, `subpopulations`, `marker genes`) and 1 weakly-shared token (`tumor`).

The 6 scRNA chains that exist (verified live):

1. The query contains "tumor biopsy" — "tumor" matches `tumor_summary_oncoplots` (a step in the variant_annotation chain) and the example_query "tumor variant summary oncoplot".
2. `search_chains` doesn't penalize cross-domain mismatch — a chain with `domain: variant_calling` can outrank an obviously-correct `domain: single_cell` chain on a single shared token.
3. The 6 scRNA chains that exist (verified live):
   - `single_cell_multimodal_analysis` (id 3)
   - `scrna_adt_multimodal_via_scrapper` (id 33)
   - `scrna_consensus_de_bioc` (id 39)
   - `bioc_scrna_cluster_v2` (id 49) ← **strongest semantic match for "find cell subpopulations and marker genes"**
   - `scrna_pseudobulk_de_bioc` (id 60)
   - `scrnaseq_standard_to_isee` (id 66)
   none appear in BC-10's `all_chains[]` output. They never even cleared the 0.35 threshold for this query.

4. The public `/api/ai_assistant/search_ranked` endpoint (different code path) returns **0 chains** for the same query but does surface scRNA workflows: `celda` (41.5), `glmgampoi_cell_level_marker_gene_identification` (36.9), etc. So the scRNA signal IS recoverable; just not by `search_chains`.

## Hard constraint: no domain heuristic that breaks other queries

A naive fix ("if query says 'cells', filter to single_cell chains") will regress queries like "compare bulk RNA-seq and single-cell RNA-seq pipelines" or "variant calling on single-cell DNA" where cross-domain matches are legitimate. Per the `CLAUDE.md` benchmark-driven discipline, any ranking change needs:

- Re-run of `evaluation/runners/routing_v6/` (101/120 exact match baseline)
- Re-run of `evaluation/runners/biomni_eval1_v17/` (gwas_causal 74-78%, rare_disease 77-80% baselines)
- No regression > 2pp on either

## Fix options — escalating cost, do A+B+C before D

Each option targets specific defects from §"Why the wrong chain wins" above. The reranker question ("should we train our own?") is option D, and is **not the right first step** because options A+B+C address the load-bearing defects (#1, #2) that a reranker doesn't fix.

### Option A — Fix the LLM-verification parser (half day, addresses defect #1+#2)

In `unified_workflow_search.py:_llm_select_chain` (~line 2156):

1. When the LLM returns an unrecognized response (logged today as "LLM response unrecognized: '*'"):
   - **Retry once** with a stricter prompt ("You MUST return one of these literal strings: chain:<name>, clarify:<name>|<question>, none. No other characters.")
   - If retry also fails, treat as `[]` (explicit no-match), NOT `None` (unavailable). This surfaces "no chain found" to the user instead of silently trusting the embedding.

In `unified_workflow_search.py:2421-2422` (the fallback):

2. Distinguish "LLM unavailable" (network error, provider down) from "LLM gave bad output" (parse failure). For the latter, return `[]` not `top_candidates[:limit]`.

3. Add a structural guard: if the top embedding score < 0.50 (currently 0.42 threshold), require successful LLM verification — don't fall through to the embedding choice on a weak match.

This alone unblocks BC-10 in the test that matters (chain object stops being the wrong one). It is the cheapest, most evidence-backed fix.

### Option B — Swap to biomedical embedding (1–2 days, addresses defect #3)

`all-MiniLM-L6-v2` is general-purpose and brittle on biomedical text. BioMate already uses **`BAAI/bge-small-en-v1.5`** for workflow search (see `docs/20260415_HYBRID_WORKFLOW_SEARCH_BGE_DENSE_RETRIEVAL.md`); apply the same to the chain index for consistency. BGE outperforms MiniLM on MTEB by ~10 points and would weight the scRNA semantic cluster more strongly than a single shared token.

Alternative if biomedical specificity matters more: `pritamdeka/S-PubMedBert-MS-MARCO` (PubMed-tuned, slightly larger).

Either is **off-the-shelf, no training needed**. Just rebuild the chain embedding index with the new encoder.

### Option C — Adopt an off-the-shelf cross-encoder reranker (3–5 days, hardens defect #1)

Replace the external Gemini API call for chain verification with a local cross-encoder:

- `BAAI/bge-reranker-large` — purpose-built for query↔passage relevance, no fine-tuning needed
- Or self-host `Qwen3:32B` (already in the fallback chain per `[llm_client_fallback_implementation]` log) and prompt it for format-strict output

Local model wins on (i) format compliance (Gemini's `*` response wouldn't happen with a constrained cross-encoder scoring head), (ii) predictable latency, (iii) no external API dependency, (iv) privacy.

### Option D — Train a custom biomedical reranker (2–4 weeks initial + ongoing)

Fine-tune `BAAI/bge-reranker-base` on (query, correct_chain, negative_chains) triplets sourced from:
- `evaluation/runners/routing_v6/` (120 labeled cases)
- User feedback signals (click-through, thumbs-up)
- Programmatically-generated negatives from off-domain chains

**Only justified when:**
- A+B+C have shipped and still leave routing quality below target
- You have a labeled dataset growth strategy (the catalog changes monthly — labels go stale)
- A GPU compute budget for ongoing retraining
- A measurement owner who runs the eval gates

Custom training is a real commitment, not a quick fix. Premature investment without first proving A+B+C are insufficient would burn the team for marginal returns.

## Recommendation

**Sequence A → B → C → (maybe D).**

1. **A** today/tomorrow. Fixes BC-10 specifically. Tightens a safety hole that today silently ships wrong chains as if they were correct.
2. **B** within the week. Broad uplift; aligns with existing BGE usage for workflow search.
3. **C** if BC-10-class regressions recur after A+B. Probably worth doing for compliance/privacy reasons anyway.
4. **D** deferred until measured evidence (≥10 BC-10-class regressions across `routing_v6` runs) justifies the investment.

## Signals that would change the recommendation

| Observed signal | Implication |
|---|---|
| Running `routing_v6` and seeing >10 mis-routes of the BC-10 class (wrong-domain chain wins despite clear domain signal) | Escalate B → C earlier; consider scoping D |
| Strategic decision that NL-to-pipeline routing IS the product moat | Invest in D as a long-term capability — but still ship A+B+C first |
| Tight budget / few engineers | Stay at A only; treat BC-10 as a one-off |
| Privacy/compliance requirement rules out external LLM API | Skip to C (local model) immediately |
| User feedback loop captures click-through and "wrong chain" reports | Builds the labeled dataset D needs — start collecting now even if D is deferred |

## Files to touch (Option A — first ship)

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/unified_workflow_search.py:2156` | Tighten `_llm_select_chain` parse-failure: retry once with stricter prompt, then return `[]` (no match) instead of falling through to `return None` |
| `backend/lib/galaxy/ai/unified_workflow_search.py:2421-2422` | Distinguish "LLM unavailable" from "LLM parse failure"; only fall back to embedding ranking for the former |
| `backend/lib/galaxy/ai/unified_workflow_search.py` (new helper) | `_embed_score_meets_high_confidence(top_score) -> bool` — when True (≥0.50), embedding fallback is safe; when False, require successful LLM verification |
| `backend/tests/test_chain_lookup_parse_failure.py` | New tests: garbage LLM response → retry path; retry fails → returns []; embedding-only path requires score ≥0.50; verify BC-10 query no longer returns variant_calling chain |
| `evaluation/runners/routing_v6/` | Re-run after fix; assert ≥99/120 exact match (no regression beyond noise) |

## Files to touch (Option B — second ship)

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/unified_workflow_search.py` (chain index init) | Replace `all-MiniLM-L6-v2` with `BAAI/bge-small-en-v1.5` for chain embeddings |
| `backend/scripts/rebuild_chain_embeddings.py` (or equivalent) | Re-index 60+ chains with BGE encoder |
| `docs/20260415_HYBRID_WORKFLOW_SEARCH_BGE_DENSE_RETRIEVAL.md` | Update to reflect that chain index now uses the same BGE model as workflow index |

## Acceptance criteria

1. BC-10 query returns a chain whose `domain == single_cell` (any of the 6 chains listed above; `bioc_scrna_cluster_v2` preferred).
2. BC-04 (clusterProfiler) and the existing tier-0 demos (T01-T05, Zhi Z01/Z02, Zhao ZZ01/ZZ02) all still pass — no regression from the domain guard.
3. Routing benchmark exact-match within 2pp of current 101/120 baseline.
4. The `[chain_lookup] domain hint=…` log line appears for every guarded query.

## What was tried this session (do not repeat)

- **BC-04 fix** (named-workflow detector for clusterProfiler) — works for explicit-name queries only; BC-10 has no explicit name. Don't try the same pattern for "single_cell" as a detector — too many synonyms, too easy to over-trigger.
- **Ad-hoc search ranking patch** — declined per evidence rule; needs the benchmark loop above.

## Background reading

- `backend/lib/galaxy/ai/ai_assistant.py:3350-3433` — chain_lookup flow
- `backend/lib/galaxy/ai/unified_workflow_search.py` — `search_chains` implementation
- `evaluation/runners/routing_v6/` — current routing benchmark baseline
- `docs/20260415_HYBRID_WORKFLOW_SEARCH_BGE_DENSE_RETRIEVAL.md` — BGE encoder details
- `frontend/e2e/bioconductor-workflows-comprehensive.e2e.ts:782` — BC-10 test definition
