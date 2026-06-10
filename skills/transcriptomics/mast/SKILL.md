---
name: bioconductor-mast
description: Methods and models for handling zero-inflated single cell assay data.
when_to_use: Use when: Zero-Inflated scRNA-seq DE: Performing differential expression analysis on single-cell RNA-seq data using a Hurdle model (zlm) to account for bimodal expression patterns.; Data Filtering: Filtering outlier cells and wells where discrete and continuous parts of the signal deviate significantly, visualized via plotSCAConcordance and applied via mast_filter.; Two-Sample Testing: Conducting combined n. Not for: Raw Integer Counts: For un-normalized, raw integer counts; use zinbwave instead because MAST expects log-transformed, approximately scale-normalized data.; Basic QC and Visualization: For simple quality control metric calculation without differential
user-invocable: false
---

# MAST

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.38.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** SingleCellExperiment
- **Imports:** Biobase, BiocGenerics, S4Vectors, data.table, ggplot2, plyr, stringr, abind, reshape2, SummarizedExperiment, progress, Matrix
- **Install:** `BiocManager::install("MAST")`

## When to Use
- **Zero-Inflated scRNA-seq DE**: Performing differential expression analysis on single-cell RNA-seq data using a Hurdle model (`zlm`) to account for bimodal expression patterns.
- **Data Filtering**: Filtering outlier cells and wells where discrete and continuous parts of the signal deviate significantly, visualized via `plotSCAConcordance` and applied via `mast_filter`.
- **Two-Sample Testing**: Conducting combined normal theory/binomial tests between pairs of groups using the `LRT` function.

## When NOT to Use
- **Raw Integer Counts**: For un-normalized, raw integer counts; use `zinbwave` instead because MAST expects log-transformed, approximately scale-normalized data.
- **Basic QC and Visualization**: For simple quality control metric calculation without differential expression; use `scater` instead because it provides dedicated functions for QC and PCA plotting.

## Data Requirements
- **Input Format**: A `SingleCellAssay` object, which can be constructed from a `data.frame` (`FromFlatDF`), a matrix (`FromMatrix`), or upcast from a `SingleCellExperiment` (`SceToSingleCellAssay`).
- **Normalization State**: Log-transformed, scale-normalized data that has been thresholded (e.g., $\log_2(\text{TPM} + 1)$).
- **Structure**: Supports dense matrices, sparse `Matrix` objects, and `HDF5Array` backends for out-of-memory data.

## Key Parameters
- **sca**: The `SingleCellAssay` object containing the expression data and metadata.
- **formula**: Symbolic notation specifying the covariates for the Hurdle model in `zlm` (e.g., `~ Population + Subject.ID`).
- **method**: The modeling function wrapper used in `zlm` (e.g., `'glmer'` for mixed models or `'glm'`).
- **ebayes**: Logical in `zlm` indicating whether to use an empirical Bayes adjustment for the dispersion estimate.
- **useContinuousBayes**: Logical in `zlm` to employ Bayesian linear regression for the continuous component.
- **exprs_value**: Character string indicating which assay slot contains the log-like data to operate on (e.g., `'logcounts'`).

## Best Practices
- Upcast existing `SingleCellExperiment` objects to `SingleCellAssay` using `SceToSingleCellAssay` to ensure compatibility and validity checks.
- Explicitly name the assay slot containing log-like data (e.g., `exprs_value = 'logcounts'`) when calling `zlm` if it is not the default.
- Enable multicore support to speed up model fitting by setting `options(mc.cores=4)` before running `zlm`.
- Use `burdenOfFiltering` and `plotSCAConcordance` to visualize the impact of filtering criteria before applying them.

## Common Pitfalls
- **Providing Raw Counts**: Passing raw integer counts to `zlm` leads to suboptimal model performance; *Fix*: Ensure the input assay contains log-transformed, scale-normalized data (e.g., log2 TPM + 1).
- **Memory Exhaustion**: Running linear models on extremely large datasets exceeds RAM; *Fix*: Store the data using a sparse `Matrix` or `HDF5Array` backend and pass it to `FromMatrix`.
- **Missing Assay Detection**: MAST fails to find the correct expression values if the assay is uniquely named; *Fix*: Ensure the assay name matches MAST's default log-like names (e.g., `'et'`, `'logcounts'`) or specify it explicitly.

## Alternatives
- **zinbwave**: Uses zero-inflated negative binomial models directly on integer count data rather than requiring log-transformed inputs.
- **scater**: Focuses on pre-processing, quality control, and visualization of scRNA-seq data rather than complex hurdle-model differential expression.
- **SCnorm**: Designed specifically for the robust normalization of single-cell RNA-seq data rather than statistical testing.

## Citations
- Finak, Greg, Andrew McDavid, Masanao Yajima, Jingyuan Deng, Vivian Gersuk, Alex K Shalek, Chloe K Slichter, et al. 2015. “MAST: A Flexible Statistical Framework for Assessing Transcriptional Changes and Characterizing Heterogeneity in Single-Cell RNA Sequencing Data.” Genome Biol. 16 (1): 1–13.
- McDavid, Andrew, Lucas Dennis, Patrick Danaher, Greg Finak, Michael Krouse, Alice Wang, Philippa Webster, Joseph Beechem, and Raphael Gottardo. 2014. “Modeling Bi-Modality Improves Characterization of Cell Cycle on Gene Expression in Single Cells.” PLoS Comput. Biol. 10 (7): e1003696.

## References
- Homepage: https://bioconductor.org/packages/MAST
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MAST/inst/doc/MAST-Intro.html
