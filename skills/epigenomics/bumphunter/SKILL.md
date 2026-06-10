---
name: bioconductor-bumphunter
description: Tools for finding bumps in genomic data
when_to_use: Use when: Finding continuous, spatially clustered genomic regions ("bumps") that differ significantly between conditions using bumphunter().; Grouping genomic locations into distinct clusters based on maximum distance using clusterMaker().; Extracting positive, near-zero, and negative segments from a vector of test statistics using getSegments().; Packaging segmented regions into a table of bump characteris. Not for: For basic linear modeling of independent, unclustered genomic features, use limma because bumphunter is specifically designed to share information between nearby clustered locations.; For end-to-end analysis of Illumina 450k arrays without manual mat
user-invocable: false
---

# bumphunter

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.54.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** S4Vectors, IRanges, Seqinfo, GenomicRanges, foreach, iterators, locfit
- **Imports:** matrixStats, limma, doRNG, BiocGenerics, GenomicFeatures, AnnotationDbi
- **Install:** `BiocManager::install("bumphunter")`

## When to Use
- Finding continuous, spatially clustered genomic regions ("bumps") that differ significantly between conditions using `bumphunter()`.
- Grouping genomic locations into distinct clusters based on maximum distance using `clusterMaker()`.
- Extracting positive, near-zero, and negative segments from a vector of test statistics using `getSegments()`.
- Packaging segmented regions into a table of bump characteristics using `regionFinder()`.

## When NOT to Use
- For basic linear modeling of independent, unclustered genomic features, use `limma` because `bumphunter` is specifically designed to share information between nearby clustered locations.
- For end-to-end analysis of Illumina 450k arrays without manual matrix setup, use `minfi` because it provides a tailored wrapper around the bumphunter engine.
- For whole-genome bisulfite sequencing (WGBS) data requiring specialized smoothing, use `bsseq` because it adapts the bump hunting methodology specifically for bisulfite data.

## Data Requirements
- **Signal Matrix**: A numeric matrix (`y`) of genomic signals where rows represent genomic locations and columns represent biological replicates.
- **Design Matrix**: A design matrix (`X`) representing the experimental covariates, created with standard R modeling functions.
- **Genomic Coordinates**: Vectors for chromosome (`chr`) and genomic positions (`pos`) corresponding to the rows of the signal matrix.

## Key Parameters
- **maxGap** (300): Maximum distance (in base pairs) between genomic positions to be grouped into the same cluster in `clusterMaker()`.
- **cutoff** (0.05 or 0.5): Numeric threshold determining the boundary for "positive" or "negative" segments in `getSegments()` and `bumphunter()`.
- **B** (250): Number of permutations used to assess uncertainty and create a null distribution in `bumphunter()`.
- **verbose** (TRUE): Logical to print progress information during parallel bumphunting.
- **cores** (2): Number of parallel backend cores registered via `registerDoParallel()`.

## Best Practices
- Group genomic locations into distinct units using `clusterMaker()` before running segment-finding functions.
- Use the `doParallel` package and `registerDoParallel()` to distribute permutation computations across multiple cores.
- Ensure the design matrix (`X`) contains an intercept term and the covariate of interest; avoid using permutation testing if adjusting for multiple confounders.
- Run `foreachCleanup()` after parallel execution to properly close connections.

## Common Pitfalls
- Slow execution during permutation testing; fix this by setting up a parallel backend with `registerDoParallel()` before calling `bumphunter()`.
- Permutation test warnings when adjusting for confounders; fix this by noting that permutation testing is not recommended when the design matrix has columns other than the intercept and primary covariate.
- Locations on different chromosomes being clustered together; fix this by ensuring the `chr` vector is correctly passed to `clusterMaker()`, which strictly separates chromosomes.

## Alternatives
- `limma`: Provides `lmFit` for linear modeling of biological replicates without the spatial smoothing and clustering steps.
- `minfi`: Offers a specialized implementation of the bumphunter methodology tailored specifically for Illumina 450k methylation arrays.
- `bsseq`: Adapts the bump hunting conceptual approach specifically for whole-genome bisulfite sequencing data.
- `charm`: Provides modifications of the bump hunting methodology for CHARM-like methylation microarrays.

## Citations
- Jaffe, A. E., et al. (2012). Bump hunting to identify differentially methylated regions in epigenetic epidemiology studies. *International Journal of Epidemiology*, 41(1), 200-209.
- Efron, B., & Tibshirani, R. J. (1993). An Introduction to the Bootstrap.

## References
- Homepage: https://bioconductor.org/packages/bumphunter
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/bumphunter/inst/doc/bumphunter.pdf
