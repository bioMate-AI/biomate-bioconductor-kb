---
name: bioconductor-genefilter
description: Some basic functions for filtering genes.
when_to_use: Use when: Filtering genes from a microarray or expression dataset according to specific or non-specific filtering mechanisms using genefilter.; Selecting genes that have an expression measure above a certain threshold in at least a minimum number of samples using kOverA.; Finding genes that are close to specific genes of interest based on distance measures using genefinder.; Performing independent filtering. Not for: For modern RNA-seq count-based differential expression; use DESeq2 or edgeR built-in filtering because they are optimized for negative binomial distributions.; For single-cell RNA-seq data; use scran or Seurat because they handle high sparsity and dr
user-invocable: false
---

# genefilter

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.94.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** AnnotationDbi, annotate, Biobase, survival
- **Imports:** MatrixGenerics, AnnotationDbi, annotate, Biobase, survival
- **System requirements:** URL
- **Install:** `BiocManager::install("genefilter")`

## When to Use
- Filtering genes from a microarray or expression dataset according to specific or non-specific filtering mechanisms using `genefilter`.
- Selecting genes that have an expression measure above a certain threshold in at least a minimum number of samples using `kOverA`.
- Finding genes that are close to specific genes of interest based on distance measures using `genefinder`.
- Performing independent filtering to adjust p-values and increase power using `filtered_p` and `filtered_R`.

## When NOT to Use
- For modern RNA-seq count-based differential expression; use `DESeq2` or `edgeR` built-in filtering because they are optimized for negative binomial distributions.
- For single-cell RNA-seq data; use `scran` or `Seurat` because they handle high sparsity and dropout rates better than basic variance/mean filters.

## Data Requirements
- Input expression data typically provided as an `ExpressionSet` object (e.g., from the `Biobase` package) or a numeric matrix.
- Covariates or sample metadata (e.g., factors with two levels) for specific filtering like `ttest`.

## Key Parameters
- **k** (5): The minimum number of samples required to exceed the threshold in `kOverA`.
- **A** (200): The expression measure threshold in `kOverA`.
- **method** ("euc"): The distance measure used in `genefinder` (e.g., `"euc"`, `"maximum"`, `"manhattan"`).
- **scale** ("none"): Controls the scaling of the rows in `genefinder` (e.g., `"none"`, `"range"`, `"zscore"`).
- **theta** (0.5): The filtering fraction/threshold used in `filtered_p` and `filtered_R`.
- **p** (0.1): The p-value threshold used in `ttest` for specific filtering.

## Best Practices
- Assemble individual filtering criteria (like `kOverA` or `ttest`) into a combined filtering function using `filterfun` before applying it with `genefilter`.
- Use `rowSds`, `rowVars`, or `rowttests` for fast row-wise statistical calculations on expression matrices.
- Visualize the effect of filtering on multiple testing adjustments using `rejection_plot` or `filter_volcano`.

## Common Pitfalls
- **Biased multiple testing**: Using a specific filter (e.g., differential expression p-values) before applying multiple testing correction. *Fix*: Use non-specific filters (like overall variance via `rowVars`) for independent filtering.
- **Scale dominance in distance metrics**: Finding nearest genes with `genefinder` without scaling can be dominated by overall expression magnitude. *Fix*: Set `scale="zscore"` or `scale="range"` in `genefinder` to normalize row variances.
- **Slow row-wise operations**: Using `apply` with standard `t.test` or `var` on large matrices. *Fix*: Use the optimized `rowttests`, `rowSds`, and `rowVars` functions provided by the package.

## Alternatives
- `DESeq2`: For RNA-seq independent filtering integrated directly into the results extraction.
- `edgeR`: Provides `filterByExpr` which is specifically designed for count-based library size adjustments.
- `matrixStats`: For fast row/column-wise statistics if filtering functions are not needed.

## Citations
- Bourgon R, Gentleman R, Huber W. (2010). "Independent filtering increases power for detecting differentially expressed genes." *Proceedings of the National Academy of Sciences*.

## References
- Homepage: bioconductor.org/packages/genefilter
- Vignette: vignette_0_5fb6bf3b.txt
