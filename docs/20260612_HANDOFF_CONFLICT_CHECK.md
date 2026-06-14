# Cross-branch conflict check — handoff doc vs differentiation work

**Date**: 2026-06-12
**Branches compared**:
- `bioc/per-workflow-analysis` (their handoff, pushed)
- `worktree-agent-aaf4e393b5ea5b614` (my differentiation work, local)
**Their handoff doc**: `docs/20260612_BIOCONDUCTOR_REVISIONS_HANDOFF.md`
**My differentiation doc**: `docs/20260612_AMBIGUOUS_WORKFLOW_DIFFERENTIATION.md`

## Bottom line: no merge conflict, two minor coupling points

The two efforts touch disjoint files and disjoint DB rows. Both can land independently. Two coupling points need handling after merge — neither is blocking.

## File-level conflict surface

| Area | Their changes | My changes | Conflict? |
|---|---|---|---|
| `backend/scripts/` | 7 new scripts (fix_bioc_versions_heredoc.py, add_bioc_dep_bootstrap.py, pwa_*.py, etc.) | 1 new script (differentiate_ambiguous_workflows.py) | No — different filenames |
| `backend/lib/galaxy/` | hot-patched 2 Python files on dev (B-2 executor in nextflow_executor.py, B-4 ranker in unified_workflow_search.py); chain resolver in `resolve_workflow_name_to_path` | telemetry shim (chain_composer/telemetry.py) + 7-line shadow hook in ai_assistant.py | No — disjoint files |
| `backend/biomni_workflows/**/*.nf` | 2,380 `.nf` files changed (heredoc, dep bootstrap, step markers, SE library) | None | No — I didn't touch `.nf` |
| `docs/` | 1 handoff doc | 8 docs this session | No — different filenames |
| Galaxy chains DB | 6 new `bioc_*_v2` chains inserted into `workflow_chains` | None to chains; UPDATEs to `workflows` rows | No — different rows, different tables |
| `workflows` table | None (they modified `.nf` files, not DB rows) | 4 rows updated (deseq2, nf-core/differentialabundance, clusterprofiler, clusterprofiler_gsea); description + annotation_v2 | No — they didn't touch these rows |

Verified `max(annotation_v2_at) = 2026-06-12T20:57:08` (my apply timestamp) — confirms no one wrote to the annotation_v2 column after me.

## Chain coexistence

The 3 chains my cross-check verified (`bulk_rnaseq_consensus_de_bioc`, `scrna_consensus_de_bioc`, `methylation_450k_array_analysis`) are still present with identical step counts. Their 6 new `_v2` chains exist **alongside**:

| Their _v2 chain | Domain | Steps | Apparent purpose |
|---|---|---|---|
| `bioc_bulk_rnaseq_de_v2` | transcriptomics | 3 | parallel to `bulk_rnaseq_consensus_de_bioc` (3 steps) |
| `bioc_scrna_cluster_v2` | single_cell | 2 | smaller scope than `scrna_consensus_de_bioc` (4 steps) |
| `bioc_methylation_dm_v2` | epigenomics | 3 | smaller scope than `methylation_450k_array_analysis` (4 steps) |
| `bioc_chipseq_annotation_v2` | epigenomics | 2 | new (no equivalent in cross-check set) |
| `bioc_variant_annotation_v2` | genomics | 2 | new |
| `bioc_proteomics_de_v2` | proteomics | 2 | new |

Worth flagging to their team: there are now two transcriptomics chains with similar names (`bulk_rnaseq_consensus_de_bioc` vs `bioc_bulk_rnaseq_de_v2`). The composer will retrieve both as candidates; users may see disambiguation results unless one is the clear winner per query. This is exactly the chain-level differentiation problem I called out as deferred work in `docs/20260612_AMBIGUOUS_WORKFLOW_DIFFERENTIATION.md` § "next layer."

## Coupling point 1 — BGE embeddings staleness on my 4 workflows

Their work regenerated BGE dense embeddings for **all 3,310 Bioc workflows** (`galaxy_ai_workflow_embeddings.npz`, 4,005 vectors). That rebuild happened against the workflow descriptions as they existed at the time of rebuild. My 4 description rewrites (deseq2, nf-core/differentialabundance, clusterprofiler, clusterprofiler_gsea) at `2026-06-12T20:57:08` are NOT guaranteed to be in their `.npz` snapshot.

**Effect**: dense retrieval on the 4 workflows uses their *old* descriptions until re-embed. Lexical FTS retrieval (BM25) is unaffected — that reads `description` and `annotation_v2` live.

**Fix**: re-run the embeddings rebuild after merge:
```python
# from unified_workflow_search._build_workflow_embeddings — ~67 s
```

Low priority; doesn't break anything, just slightly stale dense signal on 4 of 3,310 workflows until rebuild.

## Coupling point 2 — BIOC_ prefix resolver + `dmrcate` case mismatch

The `methylation_450k_array_analysis` chain (which my cross-check verified) lists steps `BIOC_minfi`, `BIOC_limma`, `BIOC_DMRcate`, `missmethyl_region_level_gsa`. None of `BIOC_minfi` / `BIOC_limma` / `BIOC_DMRcate` exists as a row in `workflows`; the bare-name rows are `minfi`, `limma`, and **`dmrcate` (lowercase)**.

Their commit `9e4a52b8e` adds `resolve_workflow_name_to_path` to strip the leading `BIOC_` and match the bare name. That handles `BIOC_minfi` → `minfi` and `BIOC_limma` → `limma`. But:

- `BIOC_DMRcate` → strip → `DMRcate` — and the workflow row is `dmrcate` (lowercase). **The strip-prefix fix alone doesn't resolve this one** unless their lookup is case-insensitive.

**Action for their team**: confirm `resolve_workflow_name_to_path` is case-insensitive. If not, add a case-insensitive fallback, OR rename the chain step from `BIOC_DMRcate` to `dmrcate` to match the actual row.

This is independent of my differentiation work; surfacing it because the cross-check I ran on `methylation_450k_array_analysis` masked the case-mismatch (compose_chain returned step names verbatim from the chain row without resolving them).

## Recommendations for merge order

Order doesn't matter — no conflict either way. After both branches land:

1. **Rebuild BGE embeddings** to pick up my 4 description rewrites (one-shot, ~67 s).
2. **Verify** the case-insensitive resolution on `BIOC_DMRcate` → `dmrcate`. Quick `compose_chain('methylation 450k DMR analysis')` followed by an execution dry-run will surface this.
3. **Optional follow-up** (the deferred work in my doc): chain-level description differentiation between `bulk_rnaseq_consensus_de_bioc` and (a) `bulk_rnaseq_de_analysis`, (b) their new `bioc_bulk_rnaseq_de_v2`. Now three chains in the same intent space; clearer per-chain "when to use" language would help disambiguation.

## TL;DR

No conflict. The two efforts are orthogonal: theirs is workflow source + execution + chain catalog expansion; mine is workflow-row description quality. Post-merge follow-ups are an embeddings rebuild and one case-insensitive lookup check.
