---
name: bioconductor-biobase
description: Functions that are needed by many other packages or which replace R functions.
when_to_use: Use when: Coordinating high-throughput genomic data (e.g., microarray expression values) and phenotype metadata into a single, structured ExpressionSet object.; Evaluating statistical functions across sample strata defined by covariates using esApply.; Updating older, serialized instances of Bioconductor objects to their current class representations using updateObject().. Not for: For modern single-cell or range-based sequencing data, use SummarizedExperiment or SingleCellExperiment instead because they natively support genomic coordinates and scale better to sparse, multi-assay datasets.; For purely tabular data manipulation,
user-invocable: false
---

# Biobase

Functions that are needed by many other packages or which replace R functions.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.72.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics
- **Install:** `BiocManager::install("Biobase")`

## When to Use
- Coordinating high-throughput genomic data (e.g., microarray expression values) and phenotype metadata into a single, structured `ExpressionSet` object.
- Evaluating statistical functions across sample strata defined by covariates using `esApply`.
- Updating older, serialized instances of Bioconductor objects to their current class representations using `updateObject()`.

## When NOT to Use
- For modern single-cell or range-based sequencing data, use `SummarizedExperiment` or `SingleCellExperiment` instead because they natively support genomic coordinates and scale better to sparse, multi-assay datasets.
- For purely tabular data manipulation, use `dplyr` or `data.table` instead because `eSet` objects enforce strict matrix dimensions and metadata alignment that complicate simple tidy-data workflows.

## Data Requirements
- High-throughput data matrices (e.g., expression values) where rows represent features and columns represent samples.
- Sample covariates formatted as an `AnnotatedDataFrame`.
- Feature covariates formatted as an `AnnotatedDataFrame`.
- Normalization state: Typically normalized quantitative data (e.g., log-expression), though raw matrices can be stored.

## Key Parameters
- **assayData** (assayDataNew()): High-throughput data stored as a list, environment, or lockedEnvironment containing identically sized matrices.
- **phenoData** (AnnotatedDataFrame()): Sample covariates matching the column names of `assayData`.
- **featureData** (AnnotatedDataFrame()): Feature covariates matching the row names of `assayData`.
- **experimentData** (MIAME()): Experimental description and metadata.
- **annotation** (character()): Label identifying the associated annotation package.

## Best Practices
- Use accessor functions like `exprs()` and `pData()` to retrieve or assign data rather than accessing slots directly.
- Ensure that all matrices within `assayData` have identical row and column dimensions, and that `featureNames` and `sampleNames` match across all slots.
- Call `validObject()` after making structural modifications to an `eSet` to guarantee that the object remains internally consistent.
- Use `storageMode()` to check or set how `assayData` is stored, preferring `lockedEnvironment` to prevent accidental side-effects while maintaining memory efficiency.

## Common Pitfalls
- Modifying a `lockedEnvironment` directly causes an error; fix this by extracting the element, modifying it, and reassigning it, or using replacement methods like `exprs(obj) <- value`.
- Variable shadowing occurs when applying functions with `esApply`; fix this by ensuring the applied function correctly references the covariate names populated from the `pData` dataframe.
- Objects become transiently invalid during manual slot modification; fix this by calling `validObject()` after updates to ensure dimensional consistency across `assayData` and `phenoData`.

## Alternatives
- `SummarizedExperiment`: The modern Bioconductor standard for containerizing genomic data, supporting coordinate-based genomic ranges.
- `oligo`: Provides alternative, specialized class implementations for handling SNP and exon array data.
- `MultiAssayExperiment`: For integrating multiple different omics assays on the same set of biological specimens.

## Citations
- R. Gentleman, V. Carey, M. Morgan, S. Falcon and H. Khan. "esApply Introduction".
- Martin T. Morgan and H. Khan. "Biobase development and the new eSet".

## References
- Homepage: https://bioconductor.org/packages/Biobase
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Biobase/inst/doc/ExpressionSetIntroduction.pdf
