# Scope: resolver precision for the composer (chainability-aware selection)

**Date:** 2026-10-21 · **Status:** SCOPE (new workstream). The keystone eval ranked resolver
precision as the top improvable composer lever (C>B: correct workflows lift fire). This scopes it
honestly — including two caveats that reshape the fix.

## Caveat 1 — the FTS-only numbers ≈ production ranking
All resolution/precision numbers in this thread were measured **FTS-only** (the embedding model is
ABI-blocked offline). But the dense bonus is capped at **max 0.5** vs FTS scores of 40+
(`unified_workflow_search.py:111`, `_WF_DENSE_BONUS_WEIGHT`), so embeddings barely move ranking.
→ FTS-only precision is close to production. **Still: re-run the curated eval in a full env with
embeddings ON to confirm before investing.**

## Caveat 2 — "57% precision" is partly a curation artifact, not pure resolver error
The mis-picks are BioMate **domain subworkflows** narrowly out-scoring canonical pipelines
(`subworkflows/bioconductor/rsubread` 58.0 > `nfcore/rnaseq` 53.5; `subworkflows/genomics/wgs_germline`
60.5 > `nfcore/sarek` 60.3). Per PR#188 (`_is_component_subworkflow`, memory
[[subworkflow_reclassify_routing]]) those `nextflow_nfcore/subworkflows/<domain>/` entries are
**intentionally retrievable** as complete analysis steps — the −8 subworkflow penalty + "never rank a
subworkflow above a pipeline" were REMOVED as wrong. So several "misses" vs my single curated
`expected` are **valid alternatives**, not errors. **Do NOT re-introduce a subworkflow penalty.**
Fix the eval: define `expected` as a **chainability-based SET** (any workflow with the right
clean, chainable I/O types for the stage), not one filename.

## The real lever — composition/chainability-aware selection
The concrete failure is not keyword relevance; it is that a relevant match can be a **dead composer
node**: `rsubread` is a legitimate RNA-seq step but has **empty `input_types`/`output_types`**, so it
can never hand off. The composer should, among the confident matches (score ≥ `DAG_RESOLVE_MIN_SCORE`),
prefer the candidate that is actually **composable in context**:
1. **non-empty, clean I/O types** (an empty-metadata match is unusable for chaining);
2. **type-chainable in the pipeline** (its inputs are satisfiable by upstream outputs / the user input,
   and its outputs feed the next stage) — a context-aware rerank, not a global score;
3. **exec-verified** (`real_exec_status IN ('ok','ok_warnings')`) as a tie-breaker.
This is a **composer-specific rerank over the search's confident matches**, leaving the general
`UnifiedWorkflowSearch` ranking (used for single-workflow routing) unchanged. It composes with the
catalog type-hygiene fix (which makes more candidates have non-empty clean types in the first place).

## Plan (measure-first, offline where possible)
1. **Re-define the curated eval's `expected` as a chainability set** + add an `acceptable:` list of
   valid alternatives per stage; re-measure precision honestly (avoid penalising valid subworkflows).
2. **Confirm in a full env with embeddings ON** (Caveat 1) — one run of `composer_eval_curated.py`.
3. **Prototype the composer-specific rerank** in `decomposed_dag`/`_resolve_task_to_workflow`: among
   the search's top-K confident matches, pick the one maximising {clean non-empty types, context
   type-fit, exec-verified}. Keep it behind the resolver, not in global search ranking.
4. **Re-measure** `composer_eval_curated.py` (A/B/C/D) after each of (1)/(3); gate any change on a lift.

## What this is NOT
- Not a global search-ranking change (that path serves single-workflow routing well — the
  harness-dividend numbers).
- Not a subworkflow penalty (removed as wrong, PR#188).
- Not model capacity/training — it's retrieval + a context-aware rerank over existing candidates.
- Interacts with: the catalog type-hygiene fix (more composable candidates) and the real
  cross-ecosystem representation gaps (counts_matrix vs ExpressionSet — an adapter-step question,
  not a selection one).
