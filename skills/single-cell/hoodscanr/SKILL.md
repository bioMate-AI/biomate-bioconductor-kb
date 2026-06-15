---
name: bioconductor-hoodscanr
description: hoodscanR is an user-friendly R package providing functions to assist cellular neighborhood analysis of any spatial transcriptomics data with single-cell resolution. All functions in the package are built based on the SpatialExperiment object, allowing integration into various spatial transcriptomics-related packages from Bioconductor. The package can result in cell-level neighborhood annotation output, along with funtions to perform neighborhood colocalization analysis and neighborhood-based ce
when_to_use: Use when: hoodscanR_introduction; Single-cell RNA-seq analysis (hoodscanR). Not for: Requires R ≥ 4.3 and Bioconductor ≥ 3.16
user-invocable: false
---

# hoodscanR

## Workflows

### Standard Workflow

Perform cellular neighborhood scanning, colocalization analysis, and neighborhood-based clustering on single-cell spatial transcriptomics data.

```r
library(hoodscanR)
library(SpatialExperiment)
library(scico)

# 1. Read the input SpatialExperiment object
data("spe_test")
spe <- readHoodData(spe, anno_col = "celltypes")

# 2. Visualize cell positions and annotations
plotTissue(spe, color = cell_annotation, size = 1.5, alpha = 0.8)

# 3. Identify nearest neighbor cells
fnc <- findNearCells(spe, k = 100)

# 4. Calculate neighborhood association probabilities
pm <- scanHoods(fnc$distance)

# 5. Merge probabilities by cell type groups
hoods <- mergeByGroup(pm, fnc$cells)

# 6. Visualize neighborhood probabilities
plotHoodMat(hoods, n = 10, hm_height = 5)

# 7. Merge neighborhood results back into the SpatialExperiment object
spe <- mergeHoodSpe(spe, hoods)

# 8. Calculate neighborhood entropy and perplexity and visualize
spe <- calcMetrics(spe, pm_cols = colnames(hoods))
plotTissue(spe, size = 1.5, color = perplexity) + scale_color_scico(palette = "tokyo")

# 9. Perform neighborhood colocalization analysis
plotColocal(spe, pm_cols = colnames(hoods))

# 10. Cluster cells by neighborhood probability distribution
spe <- clustByHood(spe, pm_cols = colnames(hoods), k = 10)

# 11. Visualize cluster probability distributions and spatial clusters
plotProbDist(spe, pm_cols = colnames(hoods), by_cluster = TRUE, plot_all = TRUE, show_clusters = as.character(seq(10)))
plotTissue(spe, color = clusters)
```
*Input/Output Note*: Inputs a `SpatialExperiment` object with cell-type annotations; outputs an updated `SpatialExperiment` containing neighborhood probabilities, entropy, perplexity, and neighborhood-based cluster assignments.

## When to Use
- To perform cellular neighborhood analysis on single-cell resolution spatial transcriptomics data using `SpatialExperiment` objects.
- To calculate the probability of each cell associating with its spatial neighbors using `scanHoods()`.
- To analyze and visualize cell-type colocalization patterns across a tissue slide using `plotColocal()`.
- To cluster cells based on their local neighborhood composition using `clustByHood()`.

## When NOT to Use
- For spot-based spatial transcriptomics data (e.g., 10x Visium) without single-cell resolution; use standard `SpatialExperiment` workflows because `hoodscanR` is designed for single-cell resolution data.
- For standard non-spatial single-cell RNA-seq analysis; use `scran` or `Seurat` because `hoodscanR` requires spatial coordinates (`x` and `y`).
- For cell-type deconvolution of spatial spots; use `RCTD` because `hoodscanR` assumes cells are already annotated with cell types.

## Data Requirements
- **Input format**: A `SpatialExperiment` object.
- **Structure**: Must contain spatial coordinates (accessible via `spatialCoords`) and cell-type annotations in `colData` (specified via `anno_col` in `readHoodData()`).

## Key Parameters
- **anno_col** (NULL): Character string specifying the column name in `colData` containing cell-type annotations.
- **k** (`100`): The number of nearest neighbor cells to identify in `findNearCells()`.
- **n** (`10`): Number of random cells to plot in `plotHoodMat()`.
- **targetCells** (NULL): Vector of specific cell IDs to plot in `plotHoodMat()`.
- **pm_cols** (NULL): Column names of the probability matrix to use for metric calculation or clustering.

## Best Practices
- Format the input `SpatialExperiment` object using `readHoodData()` to ensure compatibility with all package functions.
- Use `perplexity` rather than `entropy` for a more intuitive measure of neighborhood mixture (e.g., perplexity of 2 indicates a 50/50 mix of two neighborhoods).
- Set `k = 100` in `findNearCells()` as a robust starting point for capturing local cellular neighborhoods.
- Visualize neighborhood probability distributions within each cluster using `plotProbDist()` to interpret the biological meaning of the clusters.

## Common Pitfalls
- **Mismatched cell-type annotation column**: Occurs if `anno_col` is not correctly specified in `readHoodData()`. Fix: Verify the column name in `colData(spe)` and pass it exactly to `readHoodData(spe, anno_col = "your_column")`.
- **Slow neighbor search on large datasets**: Occurs when searching for very large values of `k`. Fix: Keep `k` at a reasonable size (e.g., 50 to 100) since the underlying search uses the fast Approximate Near Neighbor (ANN) algorithm.

## Alternatives
- `Seurat`: For spatial data visualization and clustering, though lacking the specific softmax-based neighborhood probability modeling.
- `Giotto`: For comprehensive spatial analysis, including neighborhood enrichment and cell-to-cell interaction.
- `squidpy`: For spatial neighbor graph analysis (Python-based).

## Citations
- Liu, N. and Davis, M. (2026), hoodscanR.

## References
- Homepage: bioconductor.org/packages/hoodscanR
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/hoodscanR/inst/doc/hoodscanR_introduction.html
