# Bioc Output-Type Re-Inference — Deterministic Proposal

Replaces a $14 / 6-hour LLM-judge run with deterministic parsing of workflow_json header comments + annotation_v2.when_to_use.

## Aggregate

- Workflows considered: **2,770**
- Method: deterministic keyword rules (zero LLM cost, ~10s wall clock)
- High-specificity (≥2 kinds matched, conf 0.95): **1,159** (41%)
- Single-match (conf 0.85): **963**
- No keyword match → `general_rds` (conf 0.4): **648**

## Inferred output kind distribution

| Kind | Count |
|---|---|
| `visualizations` | 1,293 |
| `general_rds` | 648 |
| `de_table` | 487 |
| `normalized_data` | 345 |
| `cluster_assignments` | 288 |
| `enrichment_results` | 199 |
| `copy_number_segments` | 138 |
| `consensus_score` | 93 |
| `gwas_summary_statistics` | 89 |
| `counts_matrix` | 87 |
| `expression_matrix` | 87 |
| `network_graph` | 79 |
| `summarizedexperiment` | 76 |
| `singlecellexperiment` | 74 |
| `feature_selection` | 60 |
| `pathway_results` | 59 |
| `differential_abundance` | 44 |
| `annotated_genes` | 41 |
| `phylogenetic_tree` | 38 |
| `mutational_signatures` | 25 |
| `pseudotime_trajectory` | 22 |
| `seurat_object` | 21 |
| `qc_report` | 17 |
| `vcf` | 15 |
| `burden_test_results` | 13 |
| `cell_type_annotations` | 4 |

## Samples per kind

### → `visualizations`
- `a4` (conf 0.95): *Perform unsupervised exploration, filter low-variance genes, detect differential expressio*
- `a4_log_ratio_analysis` (conf 0.95): *Compute and visualize log ratios of gene expression relative to a control or reference gro*
- `a4_microarray_class_prediction` (conf 0.95): *Build and evaluate classification models using PAM, Random Forest, LASSO, and Logistic Reg*

### → `general_rds`
- `abseqr` (conf 0.40): *Generate individual and comparative quality, abundance, productivity, and diversity report*
- `abseqr_custom_downstream_comparison` (conf 0.40): *Combine and compare specific samples from different runs or subsets using the S4 plus oper*
- `abseqr_multi_directory_comparison` (conf 0.40): *Compare all samples across two entirely different abseqPy output directories.*

### → `de_table`
- `a4` (conf 0.95): *Perform unsupervised exploration, filter low-variance genes, detect differential expressio*
- `a4_log_ratio_analysis` (conf 0.95): *Compute and visualize log ratios of gene expression relative to a control or reference gro*
- `a4_microarray_class_prediction` (conf 0.95): *Build and evaluate classification models using PAM, Random Forest, LASSO, and Logistic Reg*

### → `normalized_data`
- `absseq_variance_stabilization_and_pca` (conf 0.95): *Stabilize count variances across expression levels using the aFold model and perform Princ*
- `affyplm` (conf 0.85): *Fit probe-level models to Affymetrix microarray data and perform comprehensive quality con*
- `affyplm_flexible_threestep_preprocessing` (conf 0.95): *Preprocess AffyBatch microarray data using a flexible three-step framework (custom backgro*

### → `cluster_assignments`
- `alpsnmr` (conf 0.95): *Process raw 1D NMR spectra using the modern peak clustering workflow to generate a clean, *
- `anf` (conf 0.85): *Perform spectral clustering on a single feature matrix by constructing an affinity matrix *
- `anf_multi_view_affinity_network_fusion` (conf 0.85): *Fuse multiple affinity matrices representing different views (e.g., multi-omic data) and p*

### → `enrichment_results`
- `a4_pathway_enrichment_mlp` (conf 0.95): *Perform pathway enrichment analysis using the Mean Log P (MLP) method.*
- `amaretto` (conf 0.95): *Download TCGA multi-omics data, preprocess it, run the AMARETTO algorithm to identify driv*
- `apl_step_by_step_apl` (conf 0.95): *Perform a detailed step-by-step Association Plot analysis, including Correspondence Analys*

### → `copy_number_segments`
- `ace` (conf 0.95): *Run the full absolute copy number estimation pipeline on a directory of BAM or RDS files t*
- `ace_batch_post_analysis` (conf 0.85): *Automate segment adjustment and variant linking across a large dataset using a pre-defined*
- `ace_single_sample_refinement` (conf 0.95): *Perform detailed model fitting, standard adjustment, and visualization for a single sample*

### → `consensus_score`
- `airpart` (conf 0.95): *Identify genes with differential cell-type-specific allelic imbalance and partition cell t*
- `asset` (conf 0.95): *Perform subset-based meta-analysis of summary-level association statistics across multiple*
- `awfisher` (conf 0.95): *Combine p-values from multiple independent studies to perform adaptively weighted Fisher's*
