---
name: bioconductor-hicontacts
description: HiContacts provides a collection of tools to analyse and visualize Hi-C datasets imported in R by HiCExperiment.
when_to_use: Use when: HiContacts provides a collection of tools to analyse and visualize Hi-C datasets imported in R by HiCExperiment.; Introduction to HiContacts. Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# HiContacts

## Workflows

### Standard Workflow

```r
library(HiCExperiment)
library(HiContacts)
library(HiContactsData)

# Import Hi-C matrix
cool_file <- HiContactsData('yeast_wt', format = 'cool')
hic <- import(cool_file, format = 'cool')

# Perform matrix arithmetic
hic_detrended <- detrend(hic)
hic_smooth <- despeckle(hic)

# Plot contact map
plotMatrix(hic_smooth, use.scores = 'balanced.despeckled')
```
Input: A `HiCExperiment` object.
Output: Detrended, smoothed, or merged contact maps and their corresponding plots.

### Contact Map Analysis

```r
library(HiCExperiment)
library(HiContacts)
library(HiContactsData)

mcool_file <- HiContactsData('yeast_wt', format = 'mcool')
hic <- import(mcool_file, format = 'mcool', resolution = 1000)

# Calculate cis-trans ratios
ratios <- cisTransRatio(hic)

# Compute distance decay P(s) curves
ps <- distanceLaw(hic)
```
Input: A `HiCExperiment` object, optionally with an associated pairs file.
Output: A tibble of cis-trans ratios and distance decay P(s) curves.

### Topological Feature Mapping

```r
library(HiCExperiment)
library(HiContacts)
library(HiContactsData)

mcool_file <- HiContactsData('yeast_wt', format = 'mcool')
hic <- import(mcool_file, format = 'mcool', resolution = 16000)

# Map chromosome compartments
hic <- getCompartments(hic, chromosomes = c('XV', 'XVI'))

# Compute insulation scores and borders
hic <- refocus(hic, 'II:1-300000') |> 
    zoom(resolution = 1000) |> 
    getDiamondInsulation(window_size = 8000) |> 
    getBorders()
```
Input: A `HiCExperiment` object.
Output: A `HiCExperiment` object updated with compartments, insulation scores, and domain borders.

## When to Use
- Visualizing Hi-C contact matrices as heatmaps (square or horizontal) using `plotMatrix()`.
- Performing matrix arithmetic such as detrending (`detrend()`), autocorrelating (`autocorrelate()`), merging (`merge()`), dividing (`divide()`), and smoothing (`despeckle()`).
- Mapping chromosome compartments (`getCompartments()`), insulation scores (`getDiamondInsulation()`), and domain borders (`getBorders()`).
- Analyzing distance decay curves using `distanceLaw()` and plotting them with `plotPs()` or `plotPsSlope()`.

## When NOT to Use
- For initial raw sequence alignment or filtering of fastq files, use pipelines like HiC-Pro, distiller, or Juicer instead of `HiContacts`.
- For general genomic interval manipulation without interaction data, use `GenomicRanges` or `IRanges` directly.

## Data Requirements
- A `HiCExperiment` object imported from `.cool`, `.mcool`, `.hic`, or HiC-Pro files.
- For accurate distance decay P(s) curves, an associated pairs file (e.g., `.pairs.gz`) should be linked using `pairsFile(hic) <- ...`.

## Key Parameters
- **use.scores** ('balanced'): Specifies which interaction score type to plot or analyze (e.g., `'balanced'`, `'detrended'`, `'autocorrelated'`).
- **limits** (NULL): A numeric vector of length 2 specifying the color scale limits in `plotMatrix()`.
- **maxDistance** (NULL): Maximum distance from the diagonal to plot in horizontal matrices.
- **focal.size** (5): Size of the focal window used for smoothing in `despeckle()`.
- **window_size** (8000): Window size in base pairs for computing diamond insulation scores in `getDiamondInsulation()`.
- **chromosomes** (NULL): Vector of chromosome names to restrict compartment calling in `getCompartments()`.

## Best Practices
- Always use normalized scores (like `'balanced'`) rather than raw counts for comparative analyses.
- Link a physical pairs file using `pairsFile()` before running `distanceLaw()` to avoid approximations in the P(s) curve.
- Export computed topological features (e.g., compartments or insulation scores) to standard formats like BigWig or BED using `rtracklayer::export()`.

## Common Pitfalls
- Running `distanceLaw()` without a pairs file: This results in an approximation warning. Fix by assigning a pairs file to the `HiCExperiment` object first.
- Plotting matrices with extreme dynamic ranges without log transformation: Use `scale = 'log10'` in `plotMatrix()` to improve visualization.

## Alternatives
- `diffHic`: For differential analysis of Hi-C data using biological replicates.

## Citations
- Serizay J, Matthey-Doret C, Bignaud A, Baudry L, Koszul R (2024). "Orchestrating chromosome conformation capture analysis with Bioconductor." Nature Communications, 15, 1-9. doi:10.1038/s41467-024-44761-x.

## References
- Homepage: bioconductor.org/packages/HiContacts
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/HiContacts/inst/doc/HiContacts.html
