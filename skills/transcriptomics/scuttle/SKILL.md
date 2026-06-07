---
name: bioconductor-scuttle
description: Provides basic utility functions for performing single-cell analyses, focusing on simple normalization, quality control and data transformations. Also provides some helper functions to assist development of other packages.
when_to_use: Use when: Quality Control Metrics: When you need to compute basic feature-level statistics (mean counts, detection rates) using perFeatureQCMetrics or calculateAverage.; Gene Identifier Conversion: When you need to replace stable Ensembl identifiers with unique, non-missing gene symbols using uniquifyFeatureNames.; Data Extraction for Visualization: When you need to extract expression profiles and metadata . Not for: For state-of-the-art single-cell pipelines: Use scran instead because many of scuttle's low-level utilities are legacy functions that have been superseded by more efficient implementations in other packages.; For complex clustering: Use quickCluster 
user-invocable: false
---

# scuttle

Provides basic utility functions for performing single-cell analyses, focusing on simple normalization, quality control and data transformations. Also provides some helper functions to assist development of other packages.

## When to Use
- **Quality Control Metrics**: When you need to compute basic feature-level statistics (mean counts, detection rates) using `perFeatureQCMetrics` or `calculateAverage`.
- **Gene Identifier Conversion**: When you need to replace stable Ensembl identifiers with unique, non-missing gene symbols using `uniquifyFeatureNames`.
- **Data Extraction for Visualization**: When you need to extract expression profiles and metadata into a standard `data.frame` for `ggplot` or `model.matrix` using `makePerCellDF` or `makePerFeatureDF`.
- **Scaling Normalization**: When removing composition biases using median-based normalization (`medianSizeFactors`), pooling normalization (`computePooledFactors`), or spike-in normalization (`computeSpikeFactors`).

## When NOT to Use
- **For state-of-the-art single-cell pipelines**: Use `scran` instead because many of `scuttle`'s low-level utilities are legacy functions that have been superseded by more efficient implementations in other packages.
- **For complex clustering**: Use `quickCluster` from `scran` instead because `scuttle` relies on external packages for the clustering step required prior to pooled normalization.

## Data Requirements
- **Input Format**: A `SingleCellExperiment` object.
- **Data Type**: Raw count matrices (e.g., `assay.type="counts"`).
- **Annotations**: Row names should ideally be stable identifiers (like Ensembl IDs) that can be mapped to symbols.

## Key Parameters
- **subsets** (`list(Empty=1:10)`): Used in `perFeatureQCMetrics` to define control sets (e.g., empty wells) for calculating ratio metrics.
- **assay.type** (`"counts"`): Specifies which assay to extract data from in `makePerCellDF` and `makePerFeatureDF`.
- **features** (`"Tspan12"`): Specifies the specific genes to extract expression data for in `makePerCellDF`.
- **cells** (`c(...)`): Specifies the specific cells to extract expression profiles for in `makePerFeatureDF`.
- **clusters** (`clusters`): Used in `computePooledFactors` to apply normalization within predefined clusters before adjusting across clusters.

## Best Practices
- Publish unfiltered count matrices with stable identifiers (e.g., Ensembl IDs) rather than filtered matrices with gene symbols, as filtered features cannot be recovered for data integration.
- Use `uniquifyFeatureNames` to safely convert Ensembl IDs to gene symbols for interactive analysis, ensuring duplicates are appended with identifiers and missing symbols are replaced.
- Perform a rough clustering (e.g., using `scran::quickCluster`) prior to running `computePooledFactors` on heterogeneous populations to avoid violating the assumption that most genes are non-DE.

## Common Pitfalls
- **Negative size factor estimates**: Low-quality cells with very few expressed genes can produce negative size factors during normalization; fix this by performing strict quality control to remove damaged cells before running `computePooledFactors`.
- **Duplicated row names**: Blindly replacing stable IDs with gene symbols can create duplicate row names; fix this by wrapping the replacement in `uniquifyFeatureNames`.
- **Violating non-DE assumptions**: Running `computePooledFactors` globally on a highly heterogeneous dataset can distort scaling factors; fix this by supplying a `clusters` argument to normalize within subpopulations first.

## Alternatives
- **scran**: Provides more advanced and actively maintained implementations of single-cell utilities, including the `quickCluster` function required for pooled normalization.
- **DESeq2**: Provides the original median ratio normalization approach that `medianSizeFactors` adapts for single-cell data.

## Citations
- McCarthy, D. J., Campbell, K. R., Lun, A. T., & Wills, Q. F. (2017). Scater: pre-processing, quality control, normalization and visualization of single-cell RNA-seq data in R. *Bioinformatics*, 33(8), 1179-1186.

## References
- Homepage: https://bioconductor.org/packages/scuttle
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/scuttle/inst/doc/QC.html
