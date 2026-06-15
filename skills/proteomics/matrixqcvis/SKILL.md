---
name: bioconductor-matrixqcvis
description: Data quality assessment is an integral part of preparatory data analysis to ensure sound biological information retrieval. We present here the MatrixQCvis package, which provides shiny-based interactive visualization of data quality metrics at the per-sample and per-feature level. It is broadly applicable to quantitative omics data types that come in matrix-like format (features x samples). It enables the detection of low-quality samples, drifts, outliers and batch effects in data sets. Visualiz
when_to_use: Use when: Shiny-based interactive data quality exploration of omics data; Metabolomics data analysis (MatrixQCvis); Proteomics quantification (MatrixQCvis); Quality control and preprocessing (MatrixQCvis). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# MatrixQCvis

## Workflows

### Standard Workflow

Data quality assessment is an integral part of preparatory data analysis to ensure sound biological information retrieval. We present here the MatrixQCvis package, which provides shiny-based interactive visualization of data quality metrics at the per-sample and per-feature level. It is broadly applicable to quantitative omics data types that come in matrix-like format (features x samples). It enables the detection of low-quality samples, drifts, outliers and batch effects in data sets. Visualiz

**Steps:**
1. Samples measured/missing barplot
2. Feature missingness histogram
3. Feature missingness by condition
4. UpSet plot of missingness across conditions
5. Normalization
6. Batch correction (default to none)
7. Transformation (vsn with log2 fallback)
8. Imputation (MinDet with minimum value fallback)
9. CV comparison across processing stages
10. Boxplot/Violin plot of processed values
11. Drift Plot
12. Distance Matrix Heatmap

```r
library(MatrixQCvis)
library(SummarizedExperiment)
# Assuming 'se' is a SummarizedExperiment object
se_sds <- apply(assay(se), 1, sd, na.rm = TRUE)
se <- se[!is.na(se_sds) & se_sds > 0, ]
# Start the interactive Shiny application
# qc <- shinyQC(se)
```
Input: A `SummarizedExperiment` object. Output: An interactive Shiny application that returns a processed `SummarizedExperiment` object upon exit.

## When to Use
- Shiny-based interactive quality control and visualization of quantitative omics datasets (proteomics, metabolomics, transcriptomics).
- Detecting low-quality samples, instrument drifts, outliers, and batch effects.
- Performing simple differential expression analysis using moderated t-tests (`limma`) or Wald tests (`proDA`) directly within the Shiny interface.

## When NOT to Use
- For non-matrix-like data or raw sequencing reads (e.g., FASTQ files), use packages like `ShortRead` or `FastQC`.
- For complex multi-factor batch correction or advanced linear modeling outside of interactive exploration, use `limma` or `sva` directly.

## Data Requirements
- A `SummarizedExperiment` object where `rownames(se)` are feature names, `colnames(se)` are sample names, and `colnames(se)`, `colnames(assay(se))`, and `rownames(colData(se))` are all identical.
- Features with standard deviation of 0 should be filtered out before analysis.

## Key Parameters
- **se**: A `SummarizedExperiment` object containing the quantitative assay matrix and metadata.

## Best Practices
- Filter out features with a standard deviation of 0 using `apply(assay(se), 1, sd, na.rm = TRUE)` before launching `shinyQC`.
- Consult dimension reduction plots (PCA, PCoA, tSNE, UMAP) before performing batch correction, rather than relying solely on value distributions.
- Verify that sample names across `colnames(se)`, `colnames(assay(se))`, and `rownames(colData(se))` are identical to prevent errors.

## Common Pitfalls
- Launching `shinyQC` with `rownames(se)` or `colnames(se)` set to `NULL`: Ensure feature and sample names are properly assigned.
- Performing batch correction based solely on boxplots/violin plots: Always inspect dimension reduction plots first to avoid over-correction.

## Alternatives
- `limma` for non-interactive batch correction and differential expression.
- `proDA` for intensity-dependent probabilistic modeling of missing values in label-free proteomics.
- `sva` for ComBat-based batch effect correction.

## Citations
- Ahlman-Eltze and Anders 2019, proDA (differential abundance analysis)
- Ritchie et al. 2015, limma (moderated t-tests)

## References
- Homepage: bioconductor.org/packages/MatrixQCvis
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MatrixQCvis/inst/doc/MatrixQCvis.html
