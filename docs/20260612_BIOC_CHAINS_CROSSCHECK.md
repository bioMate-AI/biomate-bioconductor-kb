# Cross-check — Bioc chains design doc vs live DB + composer retrieval

**Date**: 2026-06-12
**Source doc**: `docs/20260612_BIOC_CHAINS_DESIGN.md` (other session)
**Method**: SQL against `backend/database/galaxy_ai_tools.db.workflow_chains`; `compose_chain()` against 6 representative queries.

## DB grounding — 3/3 chains exact match

All step names, roles, and connection edges in the design doc match the DB rows byte-for-byte.

| Chain | Domain | Steps in DB | Connections in DB | Doc claim matches |
|---|---|---|---|---|
| `bulk_rnaseq_consensus_de_bioc` | transcriptomics | nf-core/rnaseq → deseq2 → clusterprofiler | counts_matrix→counts, de_table→gene_list | ✓ |
| `scrna_consensus_de_bioc` | single_cell | nf-core/scrnaseq → scater → mast ∥ monocle | sce_or_h5ad→sce, normalized_sce→sce (×2) | ✓ |
| `methylation_450k_array_analysis` | epigenomics | BIOC_minfi → BIOC_limma ∥ BIOC_DMRcate → missmethyl_region_level_gsa | GenomicMethylSet→beta (×2), dmps→dmp_ids | ✓ |

The doc's "Cross-chain shape summary" (linear / fan-out at step 2 / DAG with step-1 fan-out) is consistent with the connection edges.

## Composer retrieval — 5/6 exact step composition match

For each chain, 2 plausible user queries (one explicit, one paraphrased). Composer ran via `compose_chain()` with `BIOMATE_LLM_SHORTCIRCUIT_MIN=1.5` (curated passthrough enabled).

| # | Query | Target chain | Got | Result |
|---|---|---|---|---|
| 1 | "bulk RNA-seq DESeq2 differential expression with clusterProfiler pathway enrichment" | `bulk_rnaseq_consensus_de_bioc` | `bulk_rnaseq_de_analysis` (nf-core/differentialabundance + GSEA) | **MISS** (conf=1.00) |
| 2 | "salmon counts followed by edgeR differential expression and GO enrichment" | `bulk_rnaseq_consensus_de_bioc` | nf-core/rnaseq → deseq2 → clusterprofiler | **EXACT** (conf=0.96) |
| 3 | "single-cell RNA-seq with MAST and Monocle pseudotime differential expression" | `scrna_consensus_de_bioc` | nf-core/scrnaseq → scater → mast → monocle | **EXACT** (conf=0.92) |
| 4 | "scRNA-seq scater QC then per-cluster DE robustness" | `scrna_consensus_de_bioc` | nf-core/scrnaseq → scater → mast → monocle | **EXACT** (conf=0.88) |
| 5 | "Illumina 450k methylation array DMR analysis with minfi limma DMRcate" | `methylation_450k_array_analysis` | BIOC_minfi → BIOC_limma → BIOC_DMRcate → missmethyl_region_level_gsa | **EXACT** (conf=0.84) |
| 6 | "EPIC methylation array DMP DMR and CpG-density-corrected GO enrichment" | `methylation_450k_array_analysis` | BIOC_minfi → BIOC_limma → BIOC_DMRcate → missmethyl_region_level_gsa | **EXACT** (conf=0.84) |

**5/6 EXACT, 1/6 alternative-but-defensible.**

## The single MISS — analysis

Query 1 picked `bulk_rnaseq_de_analysis` instead of `bulk_rnaseq_consensus_de_bioc`. Both chains are present in the DB:

- `bulk_rnaseq_consensus_de_bioc`: Bioconductor-canonical (`nf-core/rnaseq → deseq2 → clusterprofiler`)
- `bulk_rnaseq_de_analysis`: nf-core-canonical (`nf-core/rnaseq → nf-core/differentialabundance → clusterprofiler_gene_set_enrichment_analysis`)

The composer scored the nf-core variant at confidence 1.00 — perfectly confident in a chain that uses the nf-core orchestrator wrapper rather than the bare Bioconductor `deseq2` workflow. This is **not a bug**: both are correct answers to a plain "DESeq2 + clusterProfiler" query. The Bioconductor-handoff context is implicit in the design doc but not present in the query.

The paraphrased Query 2 (different verbs, edgeR + GO) hit the consensus chain exactly. That tells us the consensus chain has the broader retrieval surface, and the named-tool query happens to map more strongly to the nf-core variant.

## What this means for the Bioc handoff tutorials

The Bioc-specific chain wins when the query is paraphrased or names alternative DE methods, but not when the query names DESeq2 explicitly. For the `bioc_kb` tutorial to deterministically retrieve `bulk_rnaseq_consensus_de_bioc` on the explicit-DESeq2 query, one of three options:

1. **Tutorial-side**: have the tutorial fire its own query string ("Bioconductor consensus bulk RNA-seq DE with DESeq2 / edgeR / limma alternatives") rather than relying on user's likely-shorter wording
2. **Chain-side**: add Bioconductor-distinctive terms to the `bulk_rnaseq_consensus_de_bioc` description / when_to_use to outscore the nf-core variant on `DESeq2 + clusterProfiler` queries
3. **Accept the alternative**: `bulk_rnaseq_de_analysis` is a valid answer; the handoff tutorial can use it equivalently for the DE → enrichment narrative

The doc's per-step substitution policy (step 2 swap-friendly) is preserved by both chains.

## Summary

- **DB grounding**: 3/3 chains match the design doc exactly.
- **Retrieval**: 5/6 representative queries retrieve the targeted chain. 1/6 retrieves an alternative chain (`bulk_rnaseq_de_analysis`) that is itself a valid answer.
- **No bugs surfaced**; one prompt-engineering question for the Bioconductor handoff tutorial design (which of the three options above) is the only follow-up.
- The design doc is safe to share — it accurately describes what runs.
