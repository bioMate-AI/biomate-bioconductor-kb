---
name: bioconductor-transformgampoi
description: Variance-stabilizing transformations help with the analysis of heteroskedastic data (i.e., data where the variance is not constant, like count data). This package provide two types of variance stabilizing transformations: (1) methods based on the delta method (e.g., 'acosh', 'log(x+1)'), (2) model residual based (Pearson and randomized quantile residuals).
when_to_use: Use when: glmGamPoi Quickstart; Single-cell RNA-seq analysis (transformGamPoi); Data normalization and preprocessing (transformGamPoi). Not for: Requires raw count data (not normalized values); Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# transformGamPoi

## Workflows

### Standard Workflow

Apply delta method-based transformations (acosh or shifted logarithm) to stabilize the variance of count data.

```r
library(transformGamPoi)
library(SingleCellExperiment)

# Load the data
sce <- TENxPBMCData::TENxPBMCData("pbmc4k")
sce <- sce[sample(nrow(sce), 1000), sample(ncol(sce), 500)]

# Apply the acosh transformation to the count matrix
assay(sce, "acosh") <- acosh_transform(assay(sce, "counts"))

# Alternatively, apply the shifted log transformation with a specified pseudo-count
y_shiftLog <- shifted_log_transform(assay(sce, "counts"), pseudo_count = 1/(4 * 0.1))
```
*Inputs are a SingleCellExperiment or count matrix; outputs are variance-stabilized values added as an assay or returned as a matrix.*

### Model Residuals Transformation

Apply model residuals-based transformations (Pearson or randomized quantile residuals) to stabilize variance across all genes, including lowly expressed ones.

```r
library(transformGamPoi)
library(SingleCellExperiment)

# Load the data
sce <- TENxPBMCData::TENxPBMCData("pbmc4k")
sce <- sce[sample(nrow(sce), 1000), sample(ncol(sce), 500)]

# Apply the Pearson residuals transformation with clipping
assay(sce, "pearson") <- residual_transform(sce, "pearson", clipping = TRUE, on_disk = FALSE)

# Alternatively, apply the randomized quantile residuals transformation
assay(sce, "rand_quantile") <- residual_transform(sce, "randomized_quantile", on_disk = FALSE)
```
*Inputs are a SingleCellExperiment or count matrix; outputs are Pearson or randomized quantile residuals.*

## When to Use
- When analyzing heteroskedastic count data (e.g., single-cell RNA-seq counts) where variance increases with mean expression.
- To prepare count data for classical statistical methods (like PCA or clustering) that perform best on data with uniform variance.
- When you want to stabilize variance for lowly expressed genes using model residuals (`residual_transform`).

## When NOT to Use
- Do not use on already normalized or log-transformed values; this package requires raw, heteroskedastic count data.
- For differential expression testing directly; use `glmGamPoi` or `DESeq2` which model the count distribution directly.

## Data Requirements
- Raw count matrix-like objects (e.g., `matrix`, `dgCMatrix`, `DelayedArray`, `SummarizedExperiment`, `SingleCellExperiment`).
- Sparsity is preserved for sparse inputs where possible.
- Typically filtered to exclude genes where all counts are zero (e.g., using `rowMeans2(counts(sce)) > 0`).

## Key Parameters
- **overdispersion** (0.1): The Gamma-Poisson overdispersion parameter $\alpha$ used in `acosh_transform`.
- **pseudo_count** (1/(4 * overdispersion)): The pseudo-count $c$ used in `shifted_log_transform`.
- **clipping** (TRUE): Whether to clip extremely large Pearson residuals in `residual_transform`.
- **on_disk** (FALSE): Whether to perform calculations on disk for large datasets in `residual_transform`.

## Best Practices
- Exclude genes with zero counts across all cells using `rowMeans2` before applying transformations.
- Use `acosh_transform` or `shifted_log_transform` to retain sparsity of the input data (ensuring $g(0) = 0$).
- Use randomized quantile residuals (`residual_transform` with `"randomized_quantile"`) to handle the discrete nature of counts and stabilize variance for lowly expressed genes.

## Common Pitfalls
- **Loss of sparsity**: Choosing an offset in log-transformation that shifts zero counts to non-zero values. *Fix*: Use `shifted_log_transform` or `acosh_transform` which are designed to preserve sparsity ($g(0) = 0$).
- **Poor stabilization of lowly expressed genes with delta method**: Delta method-based transformations (like `acosh`) still show increasing variance for low mean expression ($\mu < 0.5$). *Fix*: Use `residual_transform` with Pearson or randomized quantile residuals instead.

## Alternatives
- `scry`: For deviance residuals as a feature selection and dimension reduction tool.
- `sctransform` (Seurat): For regularized negative binomial regression-based normalization.
- `scran`: For pooling-based size factor normalization.

## Citations
- Hafemeister, C. and Satija, R. 2019. "Normalization and variance stabilization of single-cell RNA-seq data using regularized negative binomial regression." Genome Biology.

## References
- Homepage: bioconductor.org/packages/transformGamPoi
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/transformGamPoi/inst/doc/transformGamPoi_Quickstart.html
