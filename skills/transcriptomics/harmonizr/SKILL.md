---
name: bioconductor-harmonizr
description: An implementation, which takes input data and makes it available for proper batch effect removal by ComBat or Limma. The implementation appropriately handles missing values by dissecting the input matrix into smaller matrices with sufficient data to feed the ComBat or limma algorithm. The adjusted data is returned to the user as a rebuild matrix. The implementation is meant to make as much data available as possible with minimal data loss.
when_to_use: Use when: An implementation, which takes input data and makes it available for proper batch effect removal by ComBat or Limma; HarmonizR_Vignette. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# HarmonizR

## Workflows

### Standard Workflow

Perform batch effect correction on a data frame containing missing values using ComBat or limma.

```r
library(HarmonizR)

# 1. Prepare the input data frame and sample description data frame
df <- data.frame(matrix(rnorm(n = 3*6), ncol = 6))
colnames(df) <- c("A", "B", "C", "D", "E", "F")
rownames(df) <- c("F1", "F2", "F3")

batch <- rep(1:3, each = 2)
des <- data.frame(ID = colnames(df), sample = 1:6, batch = batch)

# 2. Run harmonizR and write results
result <- harmonizR(df, des, output_file = FALSE, cores = 1)
```
*Input: A data frame of features with potential missing values and a sample description data frame; Output: A batch-corrected data frame.*

## When to Use
- To perform batch effect correction on high-throughput biological datasets (especially proteomics) containing missing values using `harmonizR()`.
- To run ComBat or limma batch correction algorithms on dissected matrices to maximize feature rescue.
- To correct batch effects in a `SummarizedExperiment` object containing batch metadata in `colData`.

## When NOT to Use
- For datasets with absolutely no missing values, you can use `sva::ComBat` or `limma::removeBatchEffect` directly because `HarmonizR`'s matrix dissection overhead is unnecessary.
- For non-log-transformed data where a log transformation is not appropriate, because `HarmonizR` assumes log-transformed input for plotting and standard processing.

## Data Requirements
- **Input Format**: A `data.frame`, `matrix`, or `SummarizedExperiment` object.
- **Structure**: Features (e.g., proteins, genes) as rows and samples as columns. A separate description data frame mapping sample IDs to batch numbers is required unless using a `SummarizedExperiment` with batch info in `colData`.
- **Normalization State**: Log-transformed continuous values (e.g., log2 intensity) are assumed and recommended.

## Key Parameters
- **data_as_input** (NULL): Path to raw data or a data frame/matrix of features.
- **description_as_input** (NULL): Path to description file or a data frame mapping samples to batches.
- **algorithm`** ("ComBat"): Batch correction algorithm to use, either `"ComBat"` or `"limma"`.
- **ComBat_mode** (1): Integer (1 to 4) specifying ComBat prior settings (e.g., parametric vs. non-parametric, mean-only).
- **plot** (NULL): Type of diagnostic plot to generate, e.g., `"samplemeans"`, `"featuremeans"`, or `"CV"`.
- **output_file** ("cured_data"): Name or path of the output `.tsv` file.
- **cores** (all available): Number of CPU cores to use for parallel execution.
- **ur** (TRUE): Logical indicating whether to apply unique removal of combinations for increased feature rescue.

## Best Practices
- Keep the unique removal parameter `ur = TRUE` enabled to maximize the rescue of features across batches.
- Log-transform your data before running `harmonizR()` to ensure correct behavior of the underlying ComBat/limma algorithms and plotting functions.
- Use the `block` parameter to group batches together during matrix dissection to reduce runtime on large datasets.

## Common Pitfalls
- **Plotting un-logged data**: Fix by log-transforming the input matrix prior to running `harmonizR()` with plotting enabled.
- **Extremely long runtimes on datasets with many batches**: Fix by setting the `block` parameter to an integer greater than 1 to pack batches together during dissection.
- **Missing batch metadata**: Fix by ensuring the description data frame contains `ID`, `sample`, and `batch` columns matching the input matrix column names.

## Alternatives
- `sva` (specifically `ComBat`) for batch correction when there are no missing values.
- `limma` (specifically `removeBatchEffect`) for linear model-based batch correction without missing values.

## Citations
- Schlumbohm et al. 2022, Nature Communications (for the HarmonizR framework).

## References
- Homepage: bioconductor.org/packages/HarmonizR
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/HarmonizR/inst/doc/HarmonizR_Vignette.html
