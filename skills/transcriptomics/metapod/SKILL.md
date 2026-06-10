---
name: bioconductor-metapod
description: Implements a variety of methods for combining p-values in differential analyses of genome-scale datasets. Functions can combine p-values across different tests in the same analysis (e.g., genomic windows in ChIP-seq, exons in RNA-seq) or fo
when_to_use: Use when: Genomic Window Aggregation: Combining p-values across adjacent genomic windows in ChIP-seq (e.g., inside csaw) using grouped functions like groupedSimes.; Multi-Batch Marker Detection: Merging statistics from multiple batches or pairwise comparisons during marker gene detection (e.g., inside scran) using parallel functions like parallelSimes.; Consensus Direction Summarization: Determining the ove. Not for: For simple multiple testing correction on a single flat list of independent p-values, use base R's p.adjust instead because metapod is designed for hierarchical or multi-test aggregation.; For combining raw effect sizes or variances directly across i
user-invocable: false
---

# metapod

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.20.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** Rcpp
- **System requirements:** C++11
- **Install:** `BiocManager::install("metapod")`

## When to Use
- **Genomic Window Aggregation**: Combining p-values across adjacent genomic windows in ChIP-seq (e.g., inside `csaw`) using grouped functions like `groupedSimes`.
- **Multi-Batch Marker Detection**: Merging statistics from multiple batches or pairwise comparisons during marker gene detection (e.g., inside `scran`) using parallel functions like `parallelSimes`.
- **Consensus Direction Summarization**: Determining the overall direction of effect (up, down, or mixed) across multiple tests using `summarizeParallelDirection` or `summarizeGroupedDirection`.

## When NOT to Use
- For simple multiple testing correction on a single flat list of independent p-values, use base R's `p.adjust` instead because `metapod` is designed for hierarchical or multi-test aggregation.
- For combining raw effect sizes or variances directly across independent studies, use **metafor** instead because `metapod` operates strictly on p-values and their directions.

## Data Requirements
- **Input Format**: A numeric vector of p-values with a grouping factor (for `grouped*` functions) or a list of parallel numeric vectors of p-values (for `parallel*` functions).
- **Normalization State**: P-values must be properly calibrated (uniform under the null hypothesis).
- **Minimum Size**: At least 2 p-values per group or parallel list to combine.

## Key Parameters
- **method** ("simes"): The method used to combine p-values in wrapper functions like `combineGroupedPValues` (e.g., `"simes"`, `"holm-min"`).
- **log.p** (FALSE): Logical indicating whether the input p-values are log-transformed and whether to return log-transformed output.
- **influential**: A logical vector (returned by combining functions) passed to `summarizeParallelDirection` to only consider tests that contributed to the final p-value.
- **weights**: Numeric vector of weights to apply to individual tests (supported by Simes, Stouffer, and Holm-min methods).

## Best Practices
- Use Simes' method (`parallelSimes` or `groupedSimes`) when you expect dependencies between tests (e.g., overlapping genomic windows) as it is robust to such dependencies.
- Set `log.p = TRUE` when dealing with extremely small p-values to prevent underflow to zero during calculation.
- Use `summarizeParallelDirection` or `summarizeGroupedDirection` on the `influential` tests to avoid noise from non-significant tests when determining the consensus log-fold change direction.

## Common Pitfalls
- **Assuming Independence Incorrectly**: Using Fisher's method (`groupedFisher` or `parallelFisher`) on highly correlated tests. *Fix*: Switch to Simes' method or the minimum Holm approach (`groupedHolmMin`), which do not require independence.
- **Underflow of P-values**: Generating zero p-values due to numerical limits when combining highly significant tests. *Fix*: Pass log-transformed p-values and set `log.p = TRUE`.
- **Misinterpreting Direction Counts**: Using `countParallelDirection` without understanding that it applies Benjamini-Hochberg or Holm corrections internally. *Fix*: Read the documentation for `countParallelDirection` carefully, or use `summarizeParallelDirection` for a simpler consensus.

## Alternatives
- **poolr**: For combining p-values while accounting for correlation using various methods.
- **survcomp**: Contains classical p-value combining methods (Fisher, Stouffer) but lacks genomic-specific optimizations and grouped/parallel vector handling.
- **metafor**: For traditional meta-analysis combining effect sizes and standard errors rather than just p-values.

## Citations
- Lun, A. T. L. (2021). metapod: Meta-Analyses on P-Values of Differential Analyses. R package.

## References
- Homepage: https://bioconductor.org/packages/metapod
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/metapod/inst/doc/metapod.html
