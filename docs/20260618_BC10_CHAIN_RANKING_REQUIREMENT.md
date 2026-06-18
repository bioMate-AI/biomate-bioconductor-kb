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

## Why the wrong chain wins

The chain_lookup at `backend/lib/galaxy/ai/ai_assistant.py:3367` calls:

```python
chain_results = self.workflow_search.search_chains(user_intent, min_score=0.35, limit=3)
```

Then takes `chain_results[0]` and hardcodes `confidence: 9`. The wrong chain wins because:

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

## Path A — chain-domain coherence guard (recommended, smallest)

In `ai_assistant.py:3367`, **before** picking `chain_results[0]`:

1. Compute query-domain hint from the query text using existing signal:
   - single_cell: `\b(single[ -]?cell|sc[Rr][Nn][Aa]|UMI|individual cells|subpopulation|cell type|10x|droplet)\b`
   - transcriptomics: `\b(rnaseq|differential expression|deseq2|edger|limma|count matrix|bulk)\b`
   - variant_calling: `\b(variant|VCF|GATK|sarek|germline|somatic|SNV|indel)\b`
   - chip_seq: `\b(ChIP|MACS|peak calling|motif)\b`
   - etc.
2. If exactly one domain hint is strong (≥2 tokens):
   - Filter `chain_results` to chains whose `domain` matches the hint.
   - If filter yields ≥1 chain, use the filtered list.
   - If filter yields 0 chains, fall back to original list (do not return empty).
3. Log the filter decision so future regressions are diagnosable: `[chain_lookup] domain hint=single_cell; filtered 2 → 0; using original`.

**Tested example:** BC-10 query has UMI + "individual cells" + "subpopulations" + "marker genes" = 4 single_cell tokens, 0 variant_calling tokens. Filter should reduce candidates to single_cell chains. If `bioc_scrna_cluster_v2` is in the original 3 results, it wins. If not, the search-recall problem (Path B) is the real fix.

## Path B — fix search_chains recall (harder, separate session)

Even with the domain guard, the underlying `search_chains` recall is poor — scRNA chains aren't reaching the top-3 for an obviously-scRNA query. Possibilities:

- The chain embeddings index isn't including scRNA chains' `example_queries` field
- BGE encoder sees "tumor" + "biopsy" as oncology and biases toward variant chains
- `min_score=0.35` is too high for embedding-based recall

Diagnose with:
```bash
# Inspect what chains rank for the query at various thresholds
python -c "from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch; \
    s = UnifiedWorkflowSearch(); \
    for r in s.search_chains('I have expression data from 8000 individual cells with UMI counts from a tumor biopsy. I want to find cell subpopulations and marker genes', min_score=0.0, limit=20): \
        print(r.score, r.domain, r.name)"
```

If scRNA chains score < 0.35, the index quality is the issue. Fix would be to extend `example_queries` for scRNA chains with the kind of scenario-prose users actually write.

## Files to touch

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/ai_assistant.py:3367` | Add `_filter_chains_by_query_domain(chain_results, user_intent)` call before `top_chain = chain_results[0]` |
| `backend/lib/galaxy/ai/ai_assistant.py` (helper) | Implement `_query_domain_hint(text) -> Optional[str]` |
| `backend/tests/test_chain_lookup_domain_guard.py` | Add 6 tests covering: scRNA query → scRNA chain; bulk query → bulk; variant query → variant; ambiguous query → no filter; mixed domain query → no filter; empty filter → fall back to original |
| `evaluation/runners/routing_v6/` | Re-run after fix; assert ≥99/120 exact match (no regression beyond noise) |

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
