# BioMate Catalog — Deep Dive

**Date**: 2026-06-08
**Companion**: `docs/20260608_CATALOG_AUDIT.md` (composition + shape + counts)

This pass goes past the headline counts to surface segments and qualities that affect design decisions: who's missing from BGE, what's actually in the catch-all "general" bucket, and whether per-pattern BM25 results are semantically sound or just token matches.

## 1. The missing-BGE segment is 96% Bioconductor

Of 3,695 executable workflows, **1,287 (35%) have no BGE embedding**. Breakdown:

| Source | Missing | Share of missing |
|---|---|---|
| bioconductor | 1,229 | 96% |
| nextflow | 29 | 2% |
| biomate | 28 | 2% |
| biomate_curated | 1 | <1% |

By domain (top 8 of missing):
- transcriptomics: 627
- general: 196
- genomics: 162
- epigenomics: 92
- variant_calling: 49
- proteomics: 43
- drug_discovery: 37
- imaging: 22

**Implication**: BGE indexing covered ~60% of the Bioc subspace and stopped. The other 40% of Bioc is only reachable via BM25 / lexical retrieval. That's what the prototype already uses (BM25 in `chain_composer.retrieval`), but the production `unified_workflow_search` uses BGE + FTS hybrid — that path is silently degraded for ~1,229 Bioc workflows.

Sample missing-BGE names (illustrative — these are real packages we cannot semantically retrieve):

- `parody` (univariate outlier detection)
- `phenstat` (phenotype linear-mixed-model analysis)
- `lpnet` (signaling network inference)
- `flowclust_prior_based_clustering` (prior-informed flow clustering)
- `phase2_dose_justification` (Nextflow pharmacology — separate gap)
- `nlmixr2_population_pk` (Nextflow pharmacology)
- `Cryo-EM Conformational Heterogeneity (cryoDRGN)` (biomate-source pipeline)

A BGE backfill pass would close this gap. Not urgent for the prototype (we use BM25), but a real lever for production retrieval.

## 2. The "general" bucket is a domain-classifier miss, not a true catch-all

`domain='general'` has 636 executable workflows. Composition:

| Source | Count |
|---|---|
| bioconductor | 557 |
| nfcore | 68 |
| nfcore_subwf | 11 |

Sample Bioc-general workflows (random 10):

| Name | Description |
|---|---|
| `parody` | Detect outliers in a univariate numeric vector using various parametric and resistant methods. |
| `sketchr` | Subsample a large single-cell dataset using geometric sketching… |
| `kegggraph` | Parse KGML files, calculate node degrees and betweenness centrality… |
| `grmetrics` | Calculate GR metrics and visualize dose-response curves… |
| `basecallqc` | Clean and validate Illumina sample sheets, generate base masks… |
| `lpnet` | Infer a signaling network from steady-state perturbation data… |
| `phenstat` | Perform linear mixed model analysis on quantitative phenotypic data… |
| `flowclust_prior_based_clustering` | Robust clustering incorporating prior knowledge… |
| `biosigner_multi_assay_experiment_analysis` | Parallel feature selection across multiple omics datasets… |
| `scarray_sat` | (Bioconductor module: SCArray.sat) |

**Each of these has a clear domain** that the indexer missed. `parody` is statistics; `sketchr` is single-cell; `kegggraph` is pathway-network; `grmetrics` is pharmacology; `basecallqc` is genomics QC; `lpnet` is systems biology; `phenstat` is phenotype-mapping; etc.

Sample nfcore-general:

| Name | Real domain (from description) |
|---|---|
| `nf-core/riboseq` | transcriptomics (Ribo-seq) |
| `nf-core/pacsomatic` | variant_calling (somatic from PacBio) |
| `nf-core/marsseq` | single_cell (MARS-seq) |
| `nf-core/circdna` | genomics (extrachromosomal circular DNA) |
| `nf-core/callingcards` | genomics |
| `nf-core/proteogenomicsdb` | proteomics |
| `Utils Nfvalidation Plugin` | (truly general — utility) |

**Implication**: A domain re-classification pass over the 636 `general` workflows would correctly route ~500-600 into the right domain. The remaining ~50 are true utilities. Until then, the domain-faceted features (per-domain prompts, per-domain confidence calibration) are blind to a significant chunk of the catalog.

## 3. Per-pattern retrieval quality is high in the top-10; degrades past ~25-30 score

Spot-check of full descriptions for the top-10 candidates per pattern. Counted by hand: how many of the 10 are *semantically* aligned with the pattern (not just BM25 token overlap).

| Pattern | Top-1 | Semantic-fit in top-10 |
|---|---|---|
| `multi_method_consensus` | `piano_consensus_gsa_scoring` (47.1) | 8-9 / 10 |
| `cross_cohort_replication` | `bacon_multiple_sets_and_meta_analysis` (52.0) | 8 / 10 |
| `iterative_refinement` | `ADMET Pred (Legacy)` (38.8) | 6 / 10 |
| `resampling_uncertainty` | `PhyKIT Phylogenetic Metrics` (55.9) | 7-8 / 10 |
| `time_series_longitudinal` | `edge_timecourse_de_analysis` (84.4) | 9 / 10 (top scores very high) |
| `multi_omics_integration` | `scrapper_multimodal_rna_adt_analysis` (85.4) | 9 / 10 |

Examples of true fits (descriptions speak for themselves):

- `piano_consensus_gsa_scoring` — *"Run multiple GSA methods on the same dataset and combine their results into a consensus score and heatmap."* — textbook multi-method consensus.
- `mcbiclust_multi_run_bicluster_analysis` — *"Run the stochastic MCbiclust algorithm multiple times to identify multiple distinct correlation patterns and consensus biclusters."* — consensus.
- `bacon_multiple_sets_and_meta_analysis` — *"Correct bias and inflation across multiple cohorts and perform a fixed-effect meta-analysis."* — textbook cross-cohort.
- `aldex2_sensitivity_analysis` — *"Assess how differential abundance results change across a range of scale uncertainty (gamma) values."* — resampling uncertainty.
- `edge_timecourse_de_analysis` — *"Time-course DE analysis with edge."* — perfect for time-series.

Examples of weak fits (token match, not semantic match):

- `DEFormats` (multi_method_consensus #4) — actually a *format converter* between DE tools. Surfaces because of "DESeq2", "edgeR", "limma" mentions in its description, not because it itself does consensus.
- `singler` (cross_cohort_replication #7) — single-cell annotation; matched on "cohort" / "reference" tokens.

**Implication**: a natural quality cutoff appears around BM25 score 25-30. Above that, candidates are usually right; below, false-positive rate climbs. This is a useful operational threshold for downstream filtering.

## 4. Iterative_refinement is the most-abstract pattern

Top-10 for `iterative_refinement` has the lowest fit (6/10) and the lowest top-1 score (38.8). Why: the pattern's `When` text describes a behavioral shape ("QC gate triggers param adjustment and retry") rather than canonical tool names. Few catalog descriptions explicitly use language like "iterative", "retry", "auto-loop".

Two ways to improve:

1. **Reword the pattern's `When` text** to include domain-specific iteration vocabulary: "force-field optimization", "refinement step", "convergence", "re-pick particles", "auto-tune parameters".
2. **Add a curated chain** that instantiates iterative refinement explicitly — `admet_autoloop_canonical` would re-anchor BM25 in real catalog territory.

## 5. Curated chain reach revisited

`workflow_chains` has 29 entries. Step names referenced: 69 unique. Of those, 16 exist in the catalog. The rest are placeholder names (`pocket_detection_druggability`, `biomarker_feature_selection`) that don't have a row in `workflows`.

That means even the "curated" chains are partially un-grounded. ~77% of curated chain step names point at things that aren't real catalog workflows. The verifier handles this by treating curated step names as known regardless of whether they're in `workflows` — but it's a debt that should be cleared if we ever want to actually execute these chains.

## 6. What this audit implies for the next decisions

### Library / catalog work (no code)
1. **Domain re-classification pass** over the 636 `general` workflows. Most could be auto-relabeled via LLM judge on the description; should land ~500 into proper domains.
2. **Curated-chain step grounding** — for each of the 53 placeholder step names, find or author a real catalog workflow.
3. **Pattern `When` enrichment for `iterative_refinement`** — add domain-specific iteration vocabulary.

### Indexer work (more invasive)
4. **Bioc `output_types` re-extraction** — 82% are stubs. Recompute from each package's actual `process output` block; OR replace the stub with explicit `["object/rds"]` (less noise).
5. **biomni_nextflow `input_types` re-extraction** — 29% have params-as-types; fix `extract_biomni_input_output` at `index_all_workflows.py:309` to read from `process input:` not `params.*`.
6. **BGE backfill** for the 1,287 missing workflows — extends production retrieval coverage.

### Prototype-level (already partially in place)
7. **Quality cutoff at BM25 score ≥ 30** for candidate workflows passed to the LLM. Reduces noise without dropping coverage.
8. **Per-pattern canonical lists** with the top-N at score ≥ 30 used as compose-time "known good" anchors.

### What NOT to invest in right now
- **Usage-data-driven calibration** — `tool_usage_patterns` and `session_workflows` are empty; we can't drive it from data we don't have. Synthetic eval (`eval_queries.jsonl`) is the only knob until production telemetry is wired.
- **Tool-pair cross-edges** — `tool_compatibility` is one-directional (input only); cannot synthesize chains from it.

## Reproducibility

```bash
cd /home/yzhang/biomate/.claude/worktrees/agent-aaf4e393b5ea5b614
export PYTHONPATH=$PWD/backend/lib
python -m galaxy.ai.chain_composer.catalog_audit --output docs/20260608_CATALOG_AUDIT.md
# Deep-dive findings in this doc were produced by ad-hoc Python scripts;
# the audit module is the authoritative re-runnable artifact.
```
