---
name: bioconductor-spatialde
description: SpatialDE is a method to find spatially variable genes (SVG) from spatial transcriptomics data. This package provides wrappers to use the Python SpatialDE library in R, using reticulate and basilisk.
when_to_use: Use when: SpatialDE is a method to find spatially variable genes (SVG) from spatial transcriptomics data; stabilize using stabilize; regres out using regress_out; run using run; model search using model_search; spatial patterns using spatial_patterns. Not for: Requires R ≥ 4.3 and Bioconductor ≥ 3.16
user-invocable: false
---

# spatialDE

## Workflows

### Standard Workflow

Identify, classify, and cluster spatially variable genes from raw count matrices and spatial coordinates.

```r
library(spatialDE)
library(ggplot2)

# Load data
data("Rep11_MOB_0")
data("MOB_sample_info")

# 1. Filter out unobserved genes and calculate total counts per spot
counts <- Rep11_MOB_0[rowSums(Rep11_MOB_0) >= 3, ]
counts <- counts[, row.names(MOB_sample_info)]
MOB_sample_info$total_counts <- colSums(counts)
X <- MOB_sample_info[, c("x", "y")]

# 2. Stabilize variance using Anscombe's approximation
norm_expr <- stabilize(counts)

# 3. Regress out library size effects
resid_expr <- regress_out(norm_expr, sample_info = MOB_sample_info)

# 4. Classify SVGs into interpretable classes
sample_resid_expr <- head(resid_expr, 1000)
results <- spatialDE::run(sample_resid_expr, coordinates = X)
de_results <- results[results$qval < 0.05, ]
ms_results <- model_search(sample_resid_expr, coordinates = X, de_results = de_results)

# 5. Group SVGs into spatial patterns
sp <- spatial_patterns(sample_resid_expr, coordinates = X, de_results = de_results, n_patterns = 4L, length = 1.5)

# 6. Visualize results
FSV_sig(results, ms_results)
```
*Input: Raw count matrices and spatial coordinates; Output: Spatially variable gene tables, model classifications, and spatial pattern clusters.*

### Spatial Experiment Workflow

Identify, classify, and cluster spatially variable genes directly using a SpatialExperiment object.

```r
library(spatialDE)
library(SpatialExperiment)

# Load data
data("Rep11_MOB_0")
data("MOB_sample_info")
partial_counts <- head(Rep11_MOB_0, 1000)

spe <- SpatialExperiment(
  assays = list(counts = partial_counts),
  spatialData = DataFrame(MOB_sample_info[, c("x", "y")]),
  spatialCoordsNames = c("x", "y")
)

# Run spatialDE on SpatialExperiment
out <- spatialDE(spe, assay_type = "counts", verbose = FALSE)

# 1. Visualize spatial patterns of multiple genes
spe_results <- out[out$qval < 0.05, ]
ordered_spe_results <- spe_results[order(spe_results$qval), ]
multiGenePlots(spe, assay_type = "counts", ordered_spe_results[1:6, ]$g, point_size = 4, viridis_option = "D", dark_theme = FALSE)

# 2. Classify SVGs into interpretable classes
msearch <- modelSearch(spe, de_results = out, qval_thresh = 0.05, verbose = FALSE)

# 3. Group SVGs into spatial patterns
spatterns <- spatialPatterns(spe, de_results = spe_results, qval_thresh = 0.05, n_patterns = 4L, length = 1.5, verbose = FALSE)
```
*Input: A SpatialExperiment object; Output: Updated data frames of spatially variable genes, model classifications, and spatial patterns.*

## When to Use
- Finding spatially variable genes (SVGs) from spatial transcriptomics data using `spatialDE::run()` or `spatialDE()`.
- Stabilizing negative binomial count variance using Anscombe's approximation with `stabilize()`.
- Regressing out library size effects with `regress_out()`.
- Classifying SVGs into interpretable spatial models (e.g., linear, general) using `model_search()` or `modelSearch()`.
- Grouping SVGs into spatial patterns using automatic expression histology (AEH) with `spatial_patterns()` or `spatialPatterns()`.

## When NOT to Use
- For non-spatial single-cell RNA-seq differential expression, use `scran` or `DESeq2` because spatialDE requires spatial coordinates.
- For spatial clustering of spots/cells rather than genes, use packages like `BayesSpace` because spatialDE focuses on identifying and clustering spatially variable genes.

## Data Requirements
- Raw spatial transcriptomics count matrix (genes as rows, spots/cells as columns) or a `SpatialExperiment` object.
- Spatial coordinates (X and Y) for each spot/cell.
- Sample information containing total counts per spot for library size regression.

## Key Parameters
- **coordinates**: Data frame containing the spatial coordinates (e.g., `x` and `y`) of the spots.
- **de_results**: Data frame of differential expression results from `spatialDE::run()`.
- **n_patterns** (4L): Number of spatial patterns to group SVGs into.
- **length** (1.5): Characteristic length scale for spatial correlation.
- **qval_thresh** (0.05): Q-value threshold for filtering significant SVGs in `modelSearch()` or `spatialPatterns()`.
- **assay_type** ("counts"): Assay name to extract counts from in `SpatialExperiment` workflows.

## Best Practices
- Filter out practically unobserved genes (e.g., `rowSums(counts) >= 3`) before running the pipeline to reduce computational overhead.
- Always stabilize variance using `stabilize()` and regress out library size effects using `regress_out()` before running the core SpatialDE test.
- Run the SpatialDE test on a subset of genes first to estimate running time, as running on the full genome can be computationally intensive.

## Common Pitfalls
- Non-stabilized counts: Running SpatialDE directly on raw counts violates the normality assumption; fix this by applying `stabilize()` first.
- Transposition errors: `stabilize()` expects samples in columns and genes in rows, whereas `SpatialExperiment` objects store genes in rows and spots in columns; ensure correct orientation or use the `SpatialExperiment` wrapper `spatialDE()`.

## Alternatives
- `SpatialExperiment`: For storing and manipulating spatial transcriptomics data.
- `ggplot2`: For custom spatial gene expression plotting.

## Citations
- Svensson et al. (2018), Nature Methods.

## References
- Homepage: bioconductor.org/packages/spatialDE
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/spatialDE/inst/doc/spatialDE.html
