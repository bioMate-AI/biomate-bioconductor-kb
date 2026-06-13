# Catalog quality sweep — workflow + chain descriptions

**Date**: 2026-06-12
**Companion**: `docs/20260612_AMBIGUOUS_WORKFLOW_DIFFERENTIATION.md` (pilot — 4 workflows)
**Trigger**: user direction "continue check descriptions of tools and workflow, chains"

## Scale audit results

Across the live DB (`backend/database/galaxy_ai_tools.db`):

| Pattern | Workflows (n=4,005) | Chains (n=53) |
|---|---|---|
| Empty description | 0 | 0 |
| Description < 100 chars | 1,017 (25.4%) | n/a |
| Description < 150 chars | 2,656 (66.3%) | n/a |
| Description < 200 chars | n/a | 19 (35.8%) |
| Empty `annotation_v2` | 781 (19.5%) | n/a |
| `annotation_v2` populated (>50 chars) | 3,224 (80.5%) | n/a |
| **Copy-paste `annotation_v2` clusters** (≥2 workflows with identical text) | multiple 8–9-way clusters | n/a |

Top copy-paste clusters (each cluster = workflows sharing identical `annotation_v2`):

| Cluster | Size | Example members |
|---|---|---|
| `epialleler_*` family | 9 | epialleler, epialleler_long_read_methylation_analysis, epialleler_methylation_bimodality_ecdf, … |
| `knowyourcg_*` family | 9 | knowyourcg, knowyourcg_continuous_data_sea, knowyourcg_continuous_enrichment_sea, … |
| `phyloprofile_*` family | 8 | phyloprofile, phyloprofile_core_gene_identification, phyloprofile_distribution_analysis, … |

These clusters share the parent Bioc package's vignette text; the sub-workflows are functionally distinct (different roles within the package) but indistinguishable to the retriever. Real fix: each sub-workflow needs role-specific `annotation_v2.when_to_use`.

## What was fixed in this pass — the 3 ambiguous transcriptomics chains

The audit found that of 10 transcriptomics 3-step chains, **only 3 share the same intent** ("bulk RNA-seq → DE → enrichment"). The other 7 are well-differentiated by assay (CAGE-seq, GeoMx, small-RNA), method family (Piano, EGSEA, ExpHunterSuite), or data source (recount2).

The 3 ambiguous chains and their new "Use this when..." differentiation:

| Chain | Distinguishing axis |
|---|---|
| `bulk_rnaseq_de_analysis` | nf-core production pipeline — one-click multi-method DE + GSEA + HTML report from raw FASTQ |
| `bulk_rnaseq_consensus_de_bioc` | Bioconductor-canonical bare-R path with swappable DE methods (edgeR/limma alternatives) + R Markdown narrative |
| `bioc_bulk_rnaseq_de_v2` | Pure-downstream from a pre-computed count matrix (no upstream FASTQ) |

Each description now explicitly says when to pick *this* chain AND when to pick each of the other two instead. Lengths grew from ~150 to ~600–750 chars.

## Post-apply retrieval verification

| Query | Expected | Result |
|---|---|---|
| "DESeq2 differential expression and clusterProfiler pathway enrichment" (the original MISS from cross-check) | `bulk_rnaseq_consensus_de_bioc` | **EXACT** (was MISS yesterday — now fixed at conf 1.00) |
| "Bioconductor consensus DE with DESeq2 and clusterProfiler ORA on bulk RNA-seq" | `bulk_rnaseq_consensus_de_bioc` | EXACT |
| "nf-core pipeline for bulk RNA-seq DE with GSEA HTML report" | `bulk_rnaseq_de_analysis` | EXACT |
| "differential expression on a pre-computed count matrix with downstream Bioc enrichment" | `bioc_bulk_rnaseq_de_v2` | MISS (picks nf-core chain — `nf-core/differentialabundance` description ALSO mentions "pre-computed count matrix", so still ambiguous) |

**3/4 disambiguate correctly. The previously-MISS explicit-DESeq2 case is now EXACT.**

The remaining MISS on the count-matrix query is fixable in a follow-up: tighten `bioc_bulk_rnaseq_de_v2` description to lead with "Downstream-only" / "No upstream FASTQ processing" to outscore the nf-core chain on that axis. Not done in this pass.

## Files

- `backend/scripts/differentiate_ambiguous_chains.py` — script for chain-level diffs (atomic, dry-run by default, row-level JSON backup)
- `backend/database/differentiate_ambiguous_chains_backup_20260612T213314.json` — backup of the 3 chain rows pre-update

## What remains (deferred — explicitly NOT done in this pass)

The honest scope picture:

| Work item | Effort | Why not now |
|---|---|---|
| Differentiate the 781 workflows with empty `annotation_v2` | days–weeks (mostly LLM-assisted authoring) | High-leverage but not a one-shot job; needs a curation strategy |
| Differentiate the 3 large copy-paste clusters (`epialleler_*`, `knowyourcg_*`, `phyloprofile_*`) | ~2 hours per cluster of manual work | Highest per-cluster leverage; the 8–9-way clusters are clear evidence of broken disambiguation. Recommend as the next concrete fix |
| Fix remaining `bioc_bulk_rnaseq_de_v2` MISS on count-matrix query | ~15 min | Tractable; not blocking |
| Tighten the 1,017 workflows with description <100 chars | weeks of curation | Diminishing returns past the high-leverage clusters; many are genuinely concise and fine |

## Recommendation for next pass

Most-bang-for-buck next step: **the `phyloprofile_*` cluster (8 sub-workflows)**. Each sub-workflow has a distinct role within the PhyloProfile Bioc package:

- `phyloprofile` — umbrella / orchestrator
- `phyloprofile_core_gene_identification` — core gene set
- `phyloprofile_distribution_analysis` — taxonomic distribution
- `phyloprofile_domain_architecture_plot` / `_plotting` — domain visualization
- `phyloprofile_downstream_profile_analysis` — downstream analysis
- `phyloprofile_gene_age_estimation` — gene age inference
- `phyloprofile_group_comparison` — comparative phylogenetics
- `phyloprofile_profile_clustering` — profile clustering

Each role is distinct; current `annotation_v2.when_to_use` is identical across all 8. Drafting role-specific `when_to_use` for each is ~2 hours and would resolve the cluster's disambiguation completely.

The `epialleler_*` and `knowyourcg_*` clusters follow the same shape and are similarly tractable. Doing all three (~25 workflows) is a half-day of work and would close the largest open disambiguation surface in the catalog.

## TL;DR

Audit: 4,005 workflows, 53 chains. Real ambiguity surface is much smaller than the raw "short description" count suggests — most short descriptions are fine. The two structural problems that matter are:

1. **Chain ambiguity** in the bulk RNA-seq trio — **fixed this pass**; original cross-check MISS now resolves correctly
2. **Copy-paste `annotation_v2` clusters** — three 8–9-way clusters identified, fix path documented, ~half-day of work to close all three

The pilot pattern from `docs/20260612_AMBIGUOUS_WORKFLOW_DIFFERENTIATION.md` scales: detection SQL → human-authored differentiation → atomic apply with backup → retrieval verification.
