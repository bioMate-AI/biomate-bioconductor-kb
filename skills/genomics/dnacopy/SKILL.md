---
name: bioconductor-dnacopy
description: Implements the circular binary segmentation (CBS) algorithm to segment DNA copy number data and identify genomic regions with abnormal copy number.
when_to_use: Use when: Copy Number Segmentation: Finding change-points in array DNA copy number data (e.g., array CGH) using the segment() function.; Identifying Gains and Losses: Determining regions of gained and lost copy number by plotting segment means with plot().; Outlier Smoothing: Smoothing single point outliers in log-ratio data prior to segmentation using smooth.CNA().. Not for: For allele-specific copy number estimation or tumor purity/ploidy correction, use PureCN because DNAcopy only segments total copy number.; For single-cell DNA copy number profiling where specialized noise models are required, use AneuFinder because D
user-invocable: false
---

# DNAcopy

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.86.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** Imports
- **System requirements:** URL
- **Install:** `BiocManager::install("DNAcopy")`

## When to Use
- **Copy Number Segmentation**: Finding change-points in array DNA copy number data (e.g., array CGH) using the `segment()` function.
- **Identifying Gains and Losses**: Determining regions of gained and lost copy number by plotting segment means with `plot()`.
- **Outlier Smoothing**: Smoothing single point outliers in log-ratio data prior to segmentation using `smooth.CNA()`.

## When NOT to Use
- For allele-specific copy number estimation or tumor purity/ploidy correction, use `PureCN` because `DNAcopy` only segments total copy number.
- For single-cell DNA copy number profiling where specialized noise models are required, use `AneuFinder` because `DNAcopy` assumes bulk-level signal distributions.
- For multi-sample joint segmentation, use `copynumber` because `DNAcopy` processes samples independently.

## Data Requirements
- **Input Object**: Data must be converted into a `CNA` object using the `CNA()` function.
- **Required Columns**: A matrix or vector of log-ratio data, a vector of `Chromosome` identifiers, and a vector of `Position` (map locations).
- **Data Type**: Typically specified as `data.type="logratio"`.

## Key Parameters
- **undo.splits** (`"sdundo"`): Method to get rid of unnecessary change-points due to local trends.
- **undo.SD** (`3`): The number of standard deviations used when `undo.splits="sdundo"` to remove splits.
- **plot.type** (`"w"`, `"s"`, `"c"`, `"p"`): Determines the layout of the `plot()` function (e.g., whole genome, by chromosome, across studies, or ordered by plateau).
- **p.method** (`"perm"`): Method for p-value computation. The default is a faster hybrid approach, but full permutations can be forced.
- **nperm** (`10000`): Number of permutations used in the hybrid method.
- **alpha**: Significance level for the test to accept change-points.
- **verbose** (`1`): Controls the printing of progress during the `segment()` run.

## Best Practices
- **Smooth Data First**: Always run `smooth.CNA()` on your `CNA` object to mitigate the effect of single point outliers before running `segment()`.
- **Undo Local Trends**: Use `undo.splits="sdundo"` with `undo.SD=3` in `segment()` to remove false-positive change-points caused by local data trends.
- **Subset Large Data**: Use `subset.CNA()` to subset by chromosome and sample so that segmentation does not have to be run on a whole data set at once.
- **Determine Thresholds**: Use `plot()` with `plot.type="p"` to order segments by their chromosome means, helping to visually determine the plateaus for calling gains (e.g., 0.4) and losses (e.g., -0.6).

## Common Pitfalls
- **Over-segmentation from Local Trends**: The algorithm may find change-points due to local trends rather than true copy number shifts. *Fix*: Apply the `undo.splits="sdundo"` parameter in `segment()`.
- **Slow Computation on Large Datasets**: Running the full permutation algorithm takes O(N^2) computations. *Fix*: Rely on the default hybrid approach (Gaussian approximation + permutation) rather than setting `p.method='perm'`, or reduce `nperm`.
- **Plotting Clutter**: Plotting multiple chromosomes at once can be hard to read. *Fix*: Use `plot.type="s"` to plot by chromosome within a study.

## Alternatives
- **copynumber**: For multi-sample segmentation and joint segmentation of copy number data.
- **PureCN**: For joint estimation of tumor purity, ploidy, and absolute copy number.
- **AneuFinder**: For copy number analysis of single-cell sequencing data.

## Citations
- Olshen, A. B., Venkatraman, E. S., Lucito, R., and Wigler, M. (2004). Circular binary segmentation for the analysis of array-based dna copy number data. *Biostatistics*, 5:557–72.
- Venkatraman, E. S. and Olshen, A. B. (2007). A faster circular binary segmentation algorithm for the analysis of array cgh data. *Bioinformatics*, 23:657–63.

## References
- Homepage: https://bioconductor.org/packages/DNAcopy
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/DNAcopy/inst/doc/DNAcopy.pdf
