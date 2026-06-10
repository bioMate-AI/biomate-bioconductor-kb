---
name: bioconductor-sva
description: The sva package contains functions for removing batch effects and other unwanted variation in high-throughput experiment. Specifically, the sva package contains functions for the identifying and building surrogate variables for high-dimensi
when_to_use: Use when: Surrogate Variable Analysis (SVA): Identifying and adjusting for hidden, unmodeled, or latent sources of variation in high-dimensional datasets using sva and num.sv.; Known Batch Effect Correction (ComBat): Adjusting for known batch effects in normalized gene expression data using ComBat.; RNA-seq Count Correction (ComBat-seq): Removing batch effects from raw RNA-seq count data using ComBat_seq wh. Not for: For single-cell RNA-seq batch correction, use Seurat or batchelor instead because ComBat/sva can overcorrect and destroy single-cell biological heterogeneity.; When the batch effect is completely confounded with the biological variable of interest, d
user-invocable: false
---

# sva

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 3.60.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** mgcv, genefilter, BiocParallel
- **Imports:** matrixStats, limma, edgeR
- **System requirements:** URL
- **Install:** `BiocManager::install("sva")`

## When to Use
- **Surrogate Variable Analysis (SVA)**: Identifying and adjusting for hidden, unmodeled, or latent sources of variation in high-dimensional datasets using `sva` and `num.sv`.
- **Known Batch Effect Correction (ComBat)**: Adjusting for known batch effects in normalized gene expression data using `ComBat`.
- **RNA-seq Count Correction (ComBat-seq)**: Removing batch effects from raw RNA-seq count data using `ComBat_seq` while preserving the integer count structure.
- **Sequencing Data SVA**: Estimating surrogate variables specifically for sequencing data using `svaseq`.
- **Frozen SVA for Prediction**: Removing batch effects for prediction and clustering on new test datasets using `fsva`.

## When NOT to Use
- For single-cell RNA-seq batch correction, use `Seurat` or `batchelor` instead because ComBat/sva can overcorrect and destroy single-cell biological heterogeneity.
- When the batch effect is completely confounded with the biological variable of interest, do not use ComBat/sva because it will remove the biological signal.

## Data Requirements
- **Expression Data**: A matrix of normalized gene expression values (e.g., from `exprs`) or raw integer counts (specifically for `ComBat_seq`).
- **Design Matrix**: A model matrix representing the biological variables of interest (full model) created with `model.matrix`.
- **Batch Covariate**: A vector or factor indicating the known batch for each sample.

## Key Parameters
- **dat**: The gene expression matrix (genes in rows, samples in columns).
- **mod**: Model matrix of interest representing the biological variables to preserve.
- **mod0** (NULL): Null model matrix containing only the adjustment variables.
- **n.sv** (NULL): Number of surrogate variables to estimate; can be estimated using `num.sv`.
- **batch**: Factor or vector specifying the known batch variable.
- **covar_mod** (NULL): Model matrix of covariates to adjust for during `ComBat_seq` run.
- **par.prior** (TRUE): Whether to use parametric empirical Bayesian adjustments in `ComBat`.
- **group** (NULL): Biological variable to preserve in `ComBat_seq`.

## Best Practices
- Always specify the biological model of interest (`mod`) when running `sva` or `ComBat` to prevent the algorithm from accidentally removing the biological signal.
- For downstream differential expression with `limma`, include the estimated surrogate variables as covariates in the design formula (e.g., using `lmFit` and `contrasts.fit`).
- Use `ComBat_seq` instead of standard `ComBat` when working with raw RNA-seq counts to maintain the integer distribution required by count-based differential tools.
- Use `num.sv` to automatically estimate the number of latent factors before running `sva`.

## Common Pitfalls
- *ComBat on raw counts*: Running standard `ComBat` on raw counts; fix this by using `ComBat_seq` for raw counts.
- *Missing biological model*: Failing to include the biological design matrix in `ComBat`, which leads to over-correction; fix this by always passing the `mod` parameter.
- *Confounded designs*: Attempting to correct batch effects when they are completely confounded with the biological group; fix this by avoiding ComBat/SVA entirely.

## Alternatives
- `limma`: Provides `removeBatchEffect` for linear model-based batch correction, ideal for visualization but not for downstream differential testing.
- `ruv` (Remove Unwanted Variation): Uses control genes or replicate samples to estimate and remove unwanted variation.
- `harman`: A PCA-based batch correction method that constrains the correction to prevent over-correction of biological variation.

## Citations
- Leek, J. T., & Storey, J. D. (2007). Capturing heterogeneity in gene expression studies by surrogate variable analysis. *PLoS Genetics*, 3(9), e161.
- Johnson, W. E., Li, C., & Rabinovic, A. (2007). Adjusting batch effects in microarray expression data using empirical Bayes methods. *Biostatistics*, 8(1), 118-127.
- Zhang, Y., Parmigiani, G., & Johnson, W. E. (2020). ComBat-seq: batch effect adjustment in RNA-seq count data using empirical Bayes methods. *NAR Genomics and Bioinformatics*, 2(3), lqaa078.

## References
- Homepage: https://bioconductor.org/packages/sva
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/sva/inst/doc/sva.pdf
