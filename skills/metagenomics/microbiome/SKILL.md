---
name: bioconductor-microbiome
description: Utilities for microbiome analysis.
when_to_use: Use when: Facilitating phyloseq-based exploration and analysis of taxonomic profiling data.; Performing manipulation, statistical analysis, and visualization of taxonomic profiling data.; Standardizing analyses and developing best practices for targeted microbiome analysis.. Not for: For new projects or multi-omics data analysis, use the miaverse project instead, as microbiome development has been discontinued.; For workflows based on the new TreeSummarizedExperiment data container, use miaverse packages instead of microbiome.
user-invocable: false
---

# microbiome

## When to Use
- Facilitating `phyloseq`-based exploration and analysis of taxonomic profiling data.
- Performing manipulation, statistical analysis, and visualization of taxonomic profiling data.
- Standardizing analyses and developing best practices for targeted microbiome analysis.

## When NOT to Use
- For new projects or multi-omics data analysis, use the `miaverse` project instead, as `microbiome` development has been discontinued.
- For workflows based on the new `TreeSummarizedExperiment` data container, use `miaverse` packages instead of `microbiome`.

## Data Requirements
- Taxonomic profiling data in the independent `phyloseq` data format.

## Key Parameters
- No parameters are explicitly detailed in the provided vignette text.

## Best Practices
- Transition to the `miaverse` project and `TreeSummarizedExperiment` data container for added capabilities in multi-omics data analysis.
- Use the package to facilitate scalable exploration of population cohorts and targeted case-control studies.
- Rely on the independent `phyloseq` package and data structures for R-based microbiome analysis.

## Common Pitfalls
- **Using discontinued software for new multi-omics projects**: The `microbiome` package development is discontinued. Fix: Shift to `miaverse` tools based on `TreeSummarizedExperiment`.
- **Incompatibility with new data containers**: Attempting to use `TreeSummarizedExperiment` objects directly in `microbiome`. Fix: Use `phyloseq` format or migrate to `miaverse`.
- **Missing general-purpose tools**: Relying solely on `microbiome` for all analyses. Fix: Integrate with the independent `phyloseq` package and its data structures.

## Alternatives
- **phyloseq**: The independent package and data structure for R-based microbiome analysis that `microbiome` relies heavily upon.
- **miaverse**: The recommended successor project based on the `TreeSummarizedExperiment` data container.

## Citations
- Leo Lahti et al. (Bioconductor, 2017-2020). Tools for microbiome analysis in R. Microbiome package version.

## References
- Homepage: https://bioconductor.org/packages/microbiome
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/microbiome
