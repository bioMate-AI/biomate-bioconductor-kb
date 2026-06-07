---
name: bioconductor-glmgampoi
description: Fit linear models to overdispersed count data. The package can estimate the overdispersion and fit repeated models for matrix input. It is designed to handle large input datasets as they typically occur in single cell RNA-seq experiments.
when_to_use: Use when: Fitting Gamma-Poisson (negative binomial) generalized linear models on high-dimensional count data using glm_gp().; Performing differential expression analysis on single-cell RNA-seq data using quasi-likelihood ratio testing via test_de().; Aggregating single-cell counts into pseudobulk samples for multi-condition comparisons using pseudobulk().; Processing massive datasets (e.g., millions of cell. Not for: For standard bulk RNA-seq with small sample sizes, use DESeq2 or edgeR instead because they are classical methods heavily optimized for low-replicate bulk data.; For normalized or log-transformed data, use standard linear models instead because glmGa
user-invocable: false
---

# glmGamPoi

## When to Use
- Fitting Gamma-Poisson (negative binomial) generalized linear models on high-dimensional count data using `glm_gp()`.
- Performing differential expression analysis on single-cell RNA-seq data using quasi-likelihood ratio testing via `test_de()`.
- Aggregating single-cell counts into pseudobulk samples for multi-condition comparisons using `pseudobulk()`.
- Processing massive datasets (e.g., millions of cells) efficiently by setting `on_disk = TRUE` to avoid memory limits.

## When NOT to Use
- For standard bulk RNA-seq with small sample sizes, use `DESeq2` or `edgeR` instead because they are classical methods heavily optimized for low-replicate bulk data.
- For normalized or log-transformed data, use standard linear models instead because `glmGamPoi` requires raw count data to fit Gamma-Poisson models.

## Data Requirements
- A raw count matrix (dense `matrix`, sparse matrix, or on-disk `HDF5Array`).
- A `SingleCellExperiment` or `SummarizedExperiment` object containing unnormalized integer counts.

## Key Parameters
- **design**: Formula or model matrix specifying the experimental design (e.g., `~ 1` or `~ condition*cell + ind`).
- **on_disk**: Boolean indicating whether to force the calculation to happen on-disk (e.g., `TRUE` or `FALSE`).
- **size_factor**: Method to calculate size factors (e.g., `"ratio"`).
- **reference_level**: String specifying the baseline level for factors in the design formula.
- **contrast**: The specific comparison to test in `test_de()` (e.g., using the `cond()` function or coefficient arithmetic).
- **group_by**: Used in `pseudobulk()` with `vars()` to quote the grouping columns from `colData`.
- **sort_by**: Column to sort the differential expression results by in `test_de()` (e.g., `pval`).

## Best Practices
- Filter out genes with very low counts (e.g., `rowSums(counts) > 5`) before fitting the model to improve performance and reliability.
- Use `pseudobulk()` to aggregate single-cell data by individual/replicate before running `glm_gp()` to ensure reliable statistical tests and avoid underestimating variance.
- Use the `cond()` function within `test_de()` to cleanly specify complex contrasts (e.g., `cond(cell = "B cells", condition = "stim") - cond(...)`).

## Common Pitfalls
- **Overly optimistic p-values**: Applying `test_de()` directly to single-cell data without pseudobulking treats cells from the same sample as independent replicates; fix this by aggregating data with `pseudobulk()` first.
- **Empty factor levels**: `glm_gp()` will complain if factor levels have no observations; fix this by calling `droplevels()` on the metadata columns before fitting.
- **Deprecated pseudobulk workflow**: Using the `pseudobulk_by` argument inside `test_de()` is deprecated and wastes computation time; fix this by calling `pseudobulk()` *before* `glm_gp()`.

## Alternatives
- `DESeq2`: A classical method for bulk RNA-seq differential expression, though significantly slower on large single-cell datasets.
- `edgeR`: Another classical method for RNA-seq that uses negative binomial models, but `glmGamPoi` is optimized to be faster for single-cell data.

## Citations
- Kang et al. (2018). Multiplexed droplet single-cell RNA-sequencing using natural genetic variation. Nature Biotechnology, 36(1), 89-94.

## References
- Homepage: https://bioconductor.org/packages/glmGamPoi
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/glmGamPoi/inst/doc/glmGamPoi.html
