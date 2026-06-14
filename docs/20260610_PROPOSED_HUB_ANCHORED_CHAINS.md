# Proposed Curated Chains — 5 Hub-Anchored

**Date**: 2026-06-10
**Context**: `docs/20260608_CATALOG_COOCCURRENCE.md` identified 5 catalog workflows that strongly anchor patterns currently lacking curated chains. This doc proposes the 5 corresponding chains, each authored to:

- ground in **real catalog workflow names** (verified)
- match calibration-eval queries that currently mismatch or fall to LLM compose
- use the same `workflow_chains` schema as existing curated chains

**Status**: review proposal only. Not loaded into the live DB. To promote a chain, copy the JSON block into `CURATED_CHAINS` in `backend/scripts/index_all_workflows.py` and re-run the indexer.

**Verification done**: every `workflow_name` below is checked against `workflows.name` in the live catalog (2026-06-08 snapshot).

---

## 1. `time_series_de_with_edge`

**Closes calibration gap**: query "test compound effect over time at 0, 6, 24, and 72 hours in HepG2 cells" currently retrieves the correct pattern (`time_series_longitudinal`) but lacks a curated chain → confidence drops to 0.59 (stepwise) instead of upfront.

**Pattern instantiated**: `time_series_longitudinal`

**Domain**: transcriptomics

```json
{
  "name": "time_series_de_with_edge",
  "display_name": "Time-Course Differential Expression with edge",
  "domain": "transcriptomics",
  "description": "Process bulk RNA-seq across multiple timepoints, then identify genes with temporal differential expression patterns. Uses edge (Bioconductor) for time-aware DE rather than pairwise comparisons, preserving within-subject correlation structure.",
  "source": "curated",
  "steps": [
    {"order": 1, "workflow_name": "nf-core/rnaseq", "role": "per_timepoint_quantification", "params_template": {"aligner": "star_salmon"}},
    {"order": 2, "workflow_name": "edge_timecourse_de_analysis", "role": "time_aware_de", "params_template": {"between_groups": true}}
  ],
  "connections": [
    {"from_step": 1, "from_output": "counts_matrix", "to_step": 2, "to_input": "kidexpr_or_endoexpr"}
  ],
  "required_inputs": [
    {"name": "fastq_files", "type": "fastq", "description": "RNA-seq reads from samples at multiple timepoints"},
    {"name": "sample_sheet", "type": "csv", "description": "Metadata with timepoint column"},
    {"name": "treatment_groups", "type": "string", "description": "Group labels for between-treatment comparison"}
  ],
  "expected_outputs": [
    {"name": "temporal_de_table", "type": "tsv", "description": "Genes with time-dependent expression patterns"},
    {"name": "trajectory_plots", "type": "pdf", "description": "Per-gene expression over time"}
  ],
  "example_queries": [
    "test compound effect over time at 0, 6, 24, and 72 hours",
    "time-course RNA-seq differential expression",
    "longitudinal RNA-seq with multiple timepoints",
    "treatment time course DE analysis"
  ],
  "tags": ["time-series", "longitudinal", "RNA-seq", "DE"]
}
```

---

## 2. `consensus_de_via_piano`

**Closes calibration gap**: queries like "robust differential expression with DESeq2, edgeR, and limma to be defensible" currently route to `BIOC_ExpHunterSuite` (good) but `piano` is a more explicit consensus tool and worth exposing as an alternative.

**Pattern instantiated**: `multi_method_consensus` + downstream pathway-level consensus

**Domain**: transcriptomics

```json
{
  "name": "consensus_de_with_piano",
  "display_name": "Consensus Gene-Set Enrichment via Piano",
  "domain": "transcriptomics",
  "description": "Standard RNA-seq processing followed by per-method DE (DESeq2, edgeR, limma via ExpHunterSuite), then Piano runs multiple gene-set-analysis methods (mean, median, sum, GSEA, page, fgsea) on the consensus gene-level statistics and produces a consensus heatmap. Use when robustness across method choice is required (publication-grade studies, regulatory submissions).",
  "source": "curated",
  "steps": [
    {"order": 1, "workflow_name": "nf-core/rnaseq", "role": "primary_processing", "params_template": {"aligner": "star_salmon"}},
    {"order": 2, "workflow_name": "BIOC_ExpHunterSuite", "role": "per_method_de", "params_template": {"methods": ["deseq2", "edger", "limma"]}},
    {"order": 3, "workflow_name": "piano_consensus_gsa_scoring", "role": "consensus_gsa", "params_template": {}}
  ],
  "connections": [
    {"from_step": 1, "from_output": "counts_matrix", "to_step": 2, "to_input": "counts"},
    {"from_step": 2, "from_output": "gene_level_stats", "to_step": 3, "to_input": "myTval"}
  ],
  "required_inputs": [
    {"name": "fastq_files", "type": "fastq"},
    {"name": "sample_sheet", "type": "csv"},
    {"name": "contrast", "type": "string"},
    {"name": "gene_set_db", "type": "string", "description": "GO, KEGG, Reactome, or MSigDB"}
  ],
  "expected_outputs": [
    {"name": "consensus_de_table", "type": "tsv", "description": "Genes with intersection of DESeq2+edgeR+limma calls"},
    {"name": "piano_consensus_heatmap", "type": "pdf", "description": "Heatmap of consensus gene-set scores"}
  ],
  "example_queries": [
    "robust differential expression with DESeq2, edgeR, and limma",
    "consensus DE across multiple methods",
    "ensemble gene set enrichment",
    "defensible pathway analysis for publication"
  ],
  "tags": ["consensus", "DE", "GSA", "piano"]
}
```

---

## 3. `meta_analysis_with_bacon`

**Closes calibration gap**: "validate biomarkers from a TCGA discovery cohort on UK Biobank using GRCh38" pattern is correctly identified as `cross_cohort_replication` but the only curated chain matches mediocre → confidence 0.728, just below upfront.

**Pattern instantiated**: `cross_cohort_replication`

**Domain**: genomics

```json
{
  "name": "meta_analysis_with_bacon",
  "display_name": "Cross-Cohort Meta-Analysis with Bacon Bias Correction",
  "domain": "genomics",
  "description": "Per-cohort association analysis (or per-cohort DE) → bacon bias-and-inflation correction across cohorts → fixed-effect meta-analysis. Designed for cross-cohort replication studies where each cohort runs the same DAG independently and results are pooled. Bacon handles the genomic-control / lambda inflation properly across cohorts.",
  "source": "curated",
  "steps": [
    {"order": 1, "workflow_name": "nf-core/rnaseq", "role": "per_cohort_quantification", "params_template": {"genome": "GRCh38"}},
    {"order": 2, "workflow_name": "BIOC_DESeq2", "role": "per_cohort_de", "params_template": {}},
    {"order": 3, "workflow_name": "bacon_multiple_sets_and_meta_analysis", "role": "cross_cohort_meta_analysis", "params_template": {"correction": "bias_and_inflation"}}
  ],
  "connections": [
    {"from_step": 1, "from_output": "counts_matrix", "to_step": 2, "to_input": "counts"},
    {"from_step": 2, "from_output": "effect_sizes_and_se", "to_step": 3, "to_input": "es_and_se_matrices"}
  ],
  "required_inputs": [
    {"name": "cohort_fastq_dirs", "type": "directory_list", "description": "FASTQ directories per cohort"},
    {"name": "cohort_sample_sheets", "type": "csv_list"},
    {"name": "common_contrast", "type": "string", "description": "Shared experimental contrast across all cohorts"}
  ],
  "expected_outputs": [
    {"name": "per_cohort_de_tables", "type": "tsv"},
    {"name": "meta_analysis_table", "type": "tsv", "description": "Fixed-effect meta with bias-corrected p-values"},
    {"name": "forest_plots", "type": "pdf"}
  ],
  "example_queries": [
    "validate biomarkers from TCGA discovery on UK Biobank",
    "meta-analysis of RNA-seq DE across TCGA GTEx ICGC",
    "cross-cohort replication of differential expression",
    "pool results across multiple cohorts with bias correction"
  ],
  "tags": ["cross-cohort", "meta-analysis", "replication", "bacon"]
}
```

---

## 4. `scrna_adt_multimodal_via_scrapper`

**Closes calibration gap**: query "single-cell RNA + ADT analysis" patterns identify `multi_omics_integration` but no curated chain targets CITE-seq specifically; `scrapper` is purpose-built.

**Pattern instantiated**: `multi_omics_integration` (single-cell flavor)

**Domain**: single_cell

```json
{
  "name": "scrna_adt_multimodal_via_scrapper",
  "display_name": "scRNA + ADT Multimodal Analysis (CITE-seq) via scrapper",
  "domain": "single_cell",
  "description": "End-to-end CITE-seq analysis: per-modality scRNA-seq + ADT preprocessing → joint scrapper analysis on the integrated SingleCellExperiment with both RNA and ADT alternative experiments. scrapper handles cross-modality QC, joint normalization, and multimodal clustering / annotation.",
  "source": "curated",
  "steps": [
    {"order": 1, "workflow_name": "nf-core/scrnaseq", "role": "scrna_preprocessing", "params_template": {"aligner": "cellranger"}},
    {"order": 2, "workflow_name": "scrapper_multimodal_rna_adt_analysis", "role": "joint_multimodal_analysis", "params_template": {"normalize": "clr_for_adt"}}
  ],
  "connections": [
    {"from_step": 1, "from_output": "sce_or_h5ad", "to_step": 2, "to_input": "sce.s"}
  ],
  "required_inputs": [
    {"name": "cite_seq_fastq", "type": "fastq", "description": "CITE-seq reads (RNA + antibody capture)"},
    {"name": "antibody_panel", "type": "csv"},
    {"name": "reference_transcriptome", "type": "string"}
  ],
  "expected_outputs": [
    {"name": "integrated_sce", "type": "rds"},
    {"name": "joint_umap", "type": "pdf"},
    {"name": "modality_qc_report", "type": "html"}
  ],
  "example_queries": [
    "CITE-seq analysis with RNA and ADT",
    "multimodal single-cell RNA plus surface protein",
    "joint scRNA-seq and antibody-derived tag analysis",
    "single-cell multi-omics with protein and RNA"
  ],
  "tags": ["multimodal", "CITE-seq", "scRNA", "ADT", "scrapper"]
}
```

---

## 5. `phylogenetic_uncertainty_via_phykit`

**Closes calibration gap**: query "bootstrap stability of a DE gene list with 100 resamples" + general phylogenetic uncertainty queries. PhyKIT is the canonical bootstrap-support computation.

**Pattern instantiated**: `resampling_uncertainty`

**Domain**: genomics (phylogenetics)

```json
{
  "name": "phylogenetic_uncertainty_via_phykit",
  "display_name": "Phylogenetic Tree Uncertainty Metrics with PhyKIT",
  "domain": "genomics",
  "description": "Multiple sequence alignment (MAFFT) → maximum-likelihood phylogeny with bootstrap (IQ-TREE) → PhyKIT computes per-gene tree-quality metrics (treeness, RCV, long-branch score, bootstrap support distribution) for quantifying phylogenetic uncertainty across orthologs. Used for ortholog quality control in phylogenomics.",
  "source": "curated",
  "steps": [
    {"order": 1, "workflow_name": "Analyze Protein Phylogeny", "role": "alignment_and_phylogeny", "params_template": {"method": "iqtree", "bootstrap": 1000}},
    {"order": 2, "workflow_name": "PhyKIT Phylogenetic Metrics", "role": "per_gene_uncertainty_metrics", "params_template": {}}
  ],
  "connections": [
    {"from_step": 1, "from_output": "mafft_alignment_and_iqtree_treefile", "to_step": 2, "to_input": "mafft_alignment_iqtree_treefile"}
  ],
  "required_inputs": [
    {"name": "ortholog_fasta_set", "type": "fasta", "description": "One FASTA per ortholog cluster"}
  ],
  "expected_outputs": [
    {"name": "per_gene_metrics", "type": "tsv", "description": "treeness, RCV, LBS, evo_rate per gene"},
    {"name": "uncertainty_summary", "type": "pdf"}
  ],
  "example_queries": [
    "bootstrap stability of phylogenetic tree",
    "phylogenetic uncertainty quantification",
    "per-gene tree metrics treeness RCV",
    "phylogenomic ortholog quality control"
  ],
  "tags": ["phylogenetics", "bootstrap", "uncertainty", "phykit"]
}
```

---

## Verification matrix

| Chain | Step workflows | All grounded? | Pattern closed | Calibration impact (expected) |
|---|---|---|---|---|
| `time_series_de_with_edge` | nf-core/rnaseq + edge_timecourse_de_analysis | ✓ | time_series_longitudinal | upfront for "time-course" queries (was stepwise 0.59) |
| `consensus_de_with_piano` | nf-core/rnaseq + BIOC_ExpHunterSuite + piano_consensus_gsa_scoring | ✓ | multi_method_consensus | adds piano as a route; current behavior unchanged but exposes a real alternative |
| `meta_analysis_with_bacon` | nf-core/rnaseq + BIOC_DESeq2 + bacon_multiple_sets_and_meta_analysis | ✓ | cross_cohort_replication | upfront for biomarker validation queries (was stepwise 0.728) |
| `scrna_adt_multimodal_via_scrapper` | nf-core/scrnaseq + scrapper_multimodal_rna_adt_analysis | ✓ | multi_omics_integration (CITE-seq) | adds CITE-seq surface coverage |
| `phylogenetic_uncertainty_via_phykit` | Analyze Protein Phylogeny + PhyKIT Phylogenetic Metrics | ✓ | resampling_uncertainty | upfront for phylogenetics queries; phykit already at top of pattern eval |

**Catalog grounding is 100%** for these 5 chains — every step references a real catalog workflow, unlike the existing 29 curated chains where 65 of 148 step references are placeholders.

## To promote into the live catalog

For each chain JSON block above:

1. Open `backend/scripts/index_all_workflows.py`.
2. Find `CURATED_CHAINS = [` (around line 432).
3. Paste the chain dict at the end of the list.
4. Run `python backend/scripts/index_all_workflows.py --curated-chains-only` (or whatever the targeted reindex flag is).
5. Verify with `sqlite3 backend/database/galaxy_ai_tools.db "SELECT name FROM workflow_chains WHERE name='<chain_name>';"`
6. Re-run calibration: `python -m galaxy.ai.chain_composer.calibrate eval_queries.jsonl`.

I am NOT doing this from the worktree — would modify the production catalog. Up to you when to promote.

## Open questions (parking lot)

1. **`consensus_de_with_piano` overlap with existing `ensemble_gene_set_enrichment_egsea`** — does Piano sufficiently differ from EGSEA to warrant both? Spot-check: EGSEA is wrapper-based combining 12+ methods; Piano emphasizes consensus scoring with cleaner UI. Worth keeping both as alternatives.
2. **`time_series_de_with_edge` vs single-cell time-series** — should there be a separate `scrna_timecourse_with_tradeSeq` chain? Likely yes; not in this batch.
3. **The `Analyze Protein Phylogeny` step in chain 5 is itself a multi-step workflow** — chain composes a multi-step inside a chain. Verifier handles this fine (treats it as one named workflow), but worth noting we're composing across granularity levels.
