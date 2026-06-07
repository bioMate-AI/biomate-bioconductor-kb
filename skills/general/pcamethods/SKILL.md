---
name: bioconductor-pcamethods
description: Provides Bayesian PCA, Probabilistic PCA, Nipals PCA, Inverse Non-Linear PCA and the conventional SVD PCA. A cluster based method for missing value estimation is included for comparison. BPCA, PPCA and NipalsPCA may be used to perform PCA o
when_to_use: Use when: Handling Outliers: When performing PCA on metabolite or microarray data corrupted with extreme values using a robust singular value decomposition (method="robustPca").; Missing Value Imputation: When estimating missing values (NA) in incomplete datasets using Probabilistic PCA (method="ppca") or Nipals (method="nipals").; Algorithm Comparison: When comparing multiple PCA formulations (e.g., "svd",. Not for: Sparse Single-Cell Data: For single-cell RNA-seq data with high dropout rates, use scry or GLM-PCA instead because they model the count distribution directly.; Complete Datasets: For standard, complete matrices without missing values or outliers, use
user-invocable: false
---

# pcaMethods

## When to Use
- **Handling Outliers**: When performing PCA on metabolite or microarray data corrupted with extreme values using a robust singular value decomposition (`method="robustPca"`).
- **Missing Value Imputation**: When estimating missing values (`NA`) in incomplete datasets using Probabilistic PCA (`method="ppca"`) or Nipals (`method="nipals"`).
- **Algorithm Comparison**: When comparing multiple PCA formulations (e.g., "svd", "ppca", "bpca", "svdImpute", "nipals", "nlpca") on the same `ExpressionSet` or matrix using a unified `pca()` interface.

## When NOT to Use
- **Sparse Single-Cell Data**: For single-cell RNA-seq data with high dropout rates, use `scry` or `GLM-PCA` instead because they model the count distribution directly.
- **Complete Datasets**: For standard, complete matrices without missing values or outliers, use base R's `prcomp` or `irlba` because they are faster and computationally lighter.

## Data Requirements
- **Input Format**: A numeric matrix, `data.frame`, or an `ExpressionSet` (from the `Biobase` package).
- **Missing Values**: Missing data should be represented as `NA`.
- **Normalization**: Data is typically mean-centered and scaled (e.g., using the `prep()` function with `scale="none"` and `center=TRUE`) prior to running PCA.

## Key Parameters
- **method** ("svd"): The PCA algorithm to use (e.g., "svd", "robustPca", "ppca", "bpca", "svdImpute", "nipals", "nlpca").
- **nPcs** (2): Number of principal components to calculate.
- **center** (TRUE): Logical indicating whether to mean-center the variables.
- **scale** ("none"): Scaling method to apply in the `prep()` function.
- **maxSteps** (1000): Maximum number of iterations for iterative algorithms like NLPCA.
- **fold** (10): Number of folds for cross-validation when using the `Q2()` function.
- **evalPcs** (1:5): The principal components to evaluate when estimating error with `kEstimate()`.
- **em** ("nrmsep"): The error metric to use during cross-validation in `kEstimate()`.

## Best Practices
- **Pre-processing**: Always pre-process data using the `prep()` function to handle centering and scaling before running `pca()`.
- **Determine Components**: Use cross-validation via the `Q2()` function to evaluate the optimal number of principal components to retain.
- **Outlier Management**: When dealing with extreme outliers, set them to `NA` and use `method="ppca"`, or use `method="robustPca"` directly on the complete data.
- **Error Estimation**: Estimate imputation error using `kEstimate()` with cross-validation to ensure the chosen method and number of PCs are appropriate.

## Common Pitfalls
- **Failing to Center Before Outlier Injection**: Creating artificial outliers for testing on un-centered data, which shifts original means and prevents objective comparison. *Fix: Use `scale(..., center=TRUE, scale=FALSE)` before injecting outliers.*
- **PPCA Instability**: PPCA failing to converge or misestimating values in rare cases. *Fix: Use a `while` loop checking if `sum(abs(Q2)) > 1` to re-run the `Q2()` function if PPCA becomes unstable.*
- **Non-Numeric Input**: Passing a matrix containing character columns or factors to `pca()`, causing the algorithms to fail. *Fix: Ensure the input matrix or `ExpressionSet` contains only numeric values.*

## Alternatives
- **missMDA**: For PCA and imputation on incomplete datasets using regularized iterative PCA.
- **impute**: For K-Nearest Neighbors imputation (`impute.knn`) of missing microarray data.
- **FactoMineR**: For advanced exploratory multivariate data analysis on complete datasets.
- **irlba**: For fast, truncated SVD and PCA on extremely large, sparse matrices.

## Citations
- Liu, L., Hawkins, D.M., Ghosh, S. and Young, S.S. Robust singular value decomposition analysis of microarray data. *PNAS*, 2003;100:13167–13172.
- Hawkins, D.M., Liu, L. and Young, S.S. Robust Singular Value Decomposition. *National Institute of Statistical Sciences*, 2001, Tech Report 122.

## References
- Homepage: https://bioconductor.org/packages/pcaMethods
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/pcaMethods/inst/doc/pcaMethods.pdf
