---
name: bioconductor-residualmatrix
description: Provides delayed computation of a matrix of residuals after fitting a linear model to each column of an input matrix. Also supports partial computation of residuals where selected factors are to be preserved in the output matrix. Implements
when_to_use: Use when: Memory-Efficient Residuals: When computing residuals on large sparse matrices (e.g., rsparsematrix) where explicitly calculating a dense matrix of residuals would exhaust memory.; Approximate PCA: When performing randomized SVD or PCA on residuals using BiocSingular::runPCA() without ever materializing the full residual matrix.; Partial Factor Retention: When regressing out uninteresting covariate. Not for: Explicit Dense Matrices: When downstream tools strictly require an explicit, fully materialized dense matrix in memory, use limma::removeBatchEffect() instead.; Small Datasets: For small datasets where memory is not a constraint, standard in-memory m
user-invocable: false
---

# ResidualMatrix

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.22.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** Matrix, S4Vectors, DelayedArray
- **Imports:** Matrix, S4Vectors, DelayedArray
- **Install:** `BiocManager::install("ResidualMatrix")`

## When to Use
- **Memory-Efficient Residuals**: When computing residuals on large sparse matrices (e.g., `rsparsematrix`) where explicitly calculating a dense matrix of residuals would exhaust memory.
- **Approximate PCA**: When performing randomized SVD or PCA on residuals using `BiocSingular::runPCA()` without ever materializing the full residual matrix.
- **Partial Factor Retention**: When regressing out uninteresting covariates while explicitly retaining interesting biological structure using the `keep` argument in `ResidualMatrix()`.
- **Restricted Observation Fitting**: When estimating batch effects using only a subset of control observations (via the `restrict` argument) and applying that regression to all observations.

## When NOT to Use
- **Explicit Dense Matrices**: When downstream tools strictly require an explicit, fully materialized dense matrix in memory, use `limma::removeBatchEffect()` instead.
- **Small Datasets**: For small datasets where memory is not a constraint, standard in-memory matrix operations or `limma` will be faster and simpler.

## Data Requirements
- **Input Matrix**: A matrix-like object (e.g., sparse matrix from the `Matrix` package, or a `DelayedMatrix`).
- **Design Matrix**: A numeric design matrix created via `model.matrix()`.

## Key Parameters
- **design**: A design matrix where residuals are conceptually computed by fitting the linear model to the columns of the input matrix.
- **keep**: An integer vector specifying which coefficients/columns of the `design` matrix should be retained (not regressed out).
- **restrict**: An integer or logical vector specifying a subset of observations (e.g., controls) to use for estimating the model coefficients.
- **center** (FALSE): Logical in `BiocSingular::runPCA()`; should be set to `FALSE` for efficiency since `ResidualMatrix` outputs are already column-centered.

## Best Practices
- Pass the `ResidualMatrix` object directly into `BiocSingular::runPCA()` to leverage efficient matrix multiplication without computing the residuals in memory.
- Use `rowSums()` or column means directly on the `ResidualMatrix` object, as these are optimized to use the delayed matrix multiplication machinery.
- Set `center=FALSE` when running PCA on a `ResidualMatrix` to avoid redundant centering operations.

## Common Pitfalls
- **Loss of Sparsity**: Forcing the `ResidualMatrix` into a standard matrix using `as.matrix()` will explicitly calculate all residuals, destroying sparsity and causing out-of-memory errors; fix by keeping it as a `ResidualMatrix` for downstream delayed operations.
- **Unsupported Operations**: Applying operations that do not have delayed matrix multiplication support will cause the `ResidualMatrix` to collapse into a `DelayedMatrix` for further processing, potentially increasing memory usage; fix by sticking to supported operations like `rowSums()` or `runPCA()`.

## Alternatives
- `limma`: Use `removeBatchEffect()` for standard, in-memory batch correction and residual calculation when memory overhead is not a concern.
- `batchelor`: For single-cell specific batch correction methods like Mutual Nearest Neighbors (MNN).

## Citations
- Lun A (2020). "Using the ResidualMatrix class." Bioconductor Vignette.

## References
- Homepage: https://bioconductor.org/packages/ResidualMatrix
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ResidualMatrix/inst/doc/ResidualMatrix.html
