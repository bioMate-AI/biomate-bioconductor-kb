---
name: bioconductor-granulator
description: granulator is an R package for the cell type deconvolution of heterogeneous tissues based on bulk RNA-seq data or single cell RNA-seq expression profiles. The package provides a unified testing interface to rapidly run and benchmark multiple state-of-the-art deconvolution methods. Data for the deconvolution of peripheral blood mononuclear cells (PBMCs) into individual immune cell types is provided as well.
when_to_use: Use when: Deconvoluting bulk RNA-seq data with granulator; Differential expression analysis (granulator); Single-cell RNA-seq analysis (granulator). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# granulator

## Workflows

### Standard Workflow

Deconvolute bulk RNA-seq data using multiple reference profiles and benchmark the results against ground truth cell type proportions.

```r
library(granulator)

# Load datasets for deconvolution of PBMC RNA-seq data
load_ABIS()

# Create a list of multiple signature matrices to test simultaneously
sigList <- list(
  ABIS_S0 = sigMatrix_ABIS_S0,
  ABIS_S1 = sigMatrix_ABIS_S1,
  ABIS_S2 = sigMatrix_ABIS_S2,
  ABIS_S3 = sigMatrix_ABIS_S3
)

# Plot signature matrix similarity matrices
plot_similarity(sigMatrix = sigList)

# Deconvolute bulk RNA-seq data using all available methods
decon <- deconvolute(m = bulkRNAseq_ABIS, sigMatrix = sigList)

# Plot cell type proportions for a specific model (e.g., SVR on ABIS_S0)
plot_proportions(deconvoluted = decon, method = 'svr', signature = 'ABIS_S0')

# Plot all estimated cell type proportions across methods and cell types
plot_deconvolute(deconvoluted = decon, scale = TRUE, labels = FALSE)

# Benchmark methods by correlating estimated to measured cell type proportions
bench <- benchmark(deconvoluted = decon, ground_truth = groundTruth_ABIS)

# Plot regression for a specific model
plot_regress(benchmarked = bench, method = 'svr', signature = 'ABIS_S0')

# Plot Pearson correlation between predictions and true proportions
plot_benchmark(benchmarked = bench, metric = 'pcc')

# Perform correlation analysis across selected methods
methods <- c('ols', 'nnls', 'qprog', 'rls', 'svr')
decon_sel <- deconvolute(bulkRNAseq_ABIS, list(ABIS_S2 = sigMatrix_ABIS_S2), methods)
correl <- correlate(deconvoluted = decon_sel)

# Plot correlation heatmap
plot_correlate(correlated = correl, method = "heatmap", legend = TRUE)
```

**Note on inputs/outputs:**
* **Input:** A bulk gene expression matrix (TPM values) and one or more cell-type reference signature matrices.
* **Output:** Estimated cell-type proportions per sample, benchmarking metrics (PCC, CCC, RMSE), and correlation plots comparing deconvolution methods.

## When to Use
* **Bulk Deconvolution:** Estimating cell type proportions in heterogeneous bulk RNA-seq samples (e.g., PBMCs) using `deconvolute()`.
* **Method Benchmarking:** Benchmarking multiple deconvolution algorithms (such as SVR, NNLS, OLS, RLS) against known ground truth proportions using `benchmark()`.
* **Signature Quality Assessment:** Assessing the similarity and quality of reference signature matrices using `plot_similarity()`.
* **Consensus Analysis:** Analyzing the consistency of predictions across different deconvolution methods when ground truth is unavailable using `correlate()`.

## When NOT to Use
* **Differential Expression:** For differential expression analysis directly, use `DESeq2` or `edgeR` because `granulator` only infers cell type proportions (which can then be used as covariates in those packages).
* **Single-Cell Clustering:** For single-cell clustering and cell-type annotation from scratch, use `Seurat` because `granulator` is designed for bulk deconvolution using pre-defined signatures.

## Data Requirements
* **Bulk Expression:** A gene (rows) by sample (columns) matrix containing normalized expression values (e.g., TPM), which can be computed from raw counts using `get_TPM()`.
* **Reference Profiles:** A gene (rows) by cell type (columns) matrix containing normalized cell-type specific expression values (e.g., `sigMatrix_ABIS_S0`).
* **Ground Truth (optional for benchmarking):** A sample (rows) by cell type (columns) matrix of measured cell-type percentages (e.g., from FACS).

## Key Parameters
* **m**: Input bulk expression matrix in `deconvolute()`.
* **sigMatrix**: Reference signature matrix or list of matrices in `deconvolute()`.
* **scale** (`TRUE`): Logical indicating whether to scale proportions to standard scores in `plot_deconvolute()`.
* **metric** ('pcc'): Evaluation metric to plot in `plot_benchmark()`; options include 'pcc', 'ccc', 'adj.r2', and 'rmse'.
* **method** ('heatmap'): Visualization style in `plot_correlate()`.

## Best Practices
* Normalize raw counts to TPM using `get_TPM()` before running deconvolution.
* Test multiple reference profiles at different cell-type resolutions (e.g., collapsing highly similar subtypes) to find the most stable deconvolution performance.
* Use the Condition Number of the signature matrix to evaluate its sensitivity to input data variability before running deconvolution.
* Scale estimated proportions to standard scores using `scale = TRUE` in `plot_deconvolute()` to compare relative changes across methods with different absolute scales.

## Common Pitfalls
* **High Collinearity:** High collinearity between closely related cell types in the reference matrix leads to unstable predictions. *Fix:* Collapse highly similar cell types into broader categories (e.g., using `sigMatrix_ABIS_S2` instead of `sigMatrix_ABIS_S0`).
* **Negative Proportions:** Negative estimated proportions returned by unconstrained methods. *Fix:* Use constrained methods like `nnls` or `qprogwc`, or refine the reference signature matrix.
* **Mismatched Gene Identifiers:** Mismatched gene identifiers between bulk RNA-seq and reference signature matrices. *Fix:* Ensure both matrices use the same gene symbol or Entrez ID format before calling `deconvolute()`.

## Alternatives
* **DESeq2** for differential expression analysis.
* **edgeR** for differential expression analysis of digital gene expression data.
* **limma** for linear modeling of gene expression.
* **Seurat** for single-cell RNA-seq analysis and reference generation.

## Citations
* Monaco, G. et al. (2019). RNA-Seq Signatures Normalized by mRNA Abundance Allow Absolute Deconvolution of Human Immune Cell Types. Cell Reports, 26(6), 1627-1640.
* Newman, A. M. et al. (2015). Robust enumeration of cell subsets from tissue expression profiles. Nature Methods, 12(5), 453-457.

## References
* Homepage: https://bioconductor.org/packages/granulator
* Vignette: https://bioconductor.org/packages/release/bioc/vignettes/granulator/inst/doc/granulator.html
