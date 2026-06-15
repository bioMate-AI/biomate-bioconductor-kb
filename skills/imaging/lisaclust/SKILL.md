---
name: bioconductor-lisaclust
description: lisaClust provides a series of functions to identify and visualise regions of tissue where spatial associations between cell-types is similar. This package can be used to provide a high-level summary of cell-type colocalization in multiplexed imaging data that has been segmented at a single-cell resolution.
when_to_use: Use when: "Inroduction to lisaClust"; Single-cell RNA-seq analysis (lisaClust). Not for: Requires R ≥ 4.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# lisaClust

## Workflows

### Standard Workflow

Simultaneously calculate LISA curves, perform k-means clustering, and visualize the identified tissue regions and cell-type enrichments.

```r
library(lisaClust)
library(SingleCellExperiment)
library(SpatialDatasets)

# Load breast cancer dataset
kerenSPE <- SpatialDatasets::spe_Keren_2018()
kerenSPE <- kerenSPE[, kerenSPE$imageID %in% c("5", "6")]

# Run lisaClust to calculate LISA curves and cluster cells
kerenSPE <- lisaClust(kerenSPE, k = 5)

# Examine cell-type enrichment across regions
regionMap(kerenSPE, type = "bubble")

# Visualize spatial regions using hatchingPlot
hatchingPlot(kerenSPE, nbp = 300)
```
*Input: A SingleCellExperiment or SpatialExperiment object with spatial coordinates and cell-type annotations. Output: Region cluster assignments stored in colData, an enrichment bubble plot, and a spatial hatching plot.*

### Custom Lisa Clustering

Calculate LISA curves separately to allow custom clustering algorithms (e.g., manual k-means) before storing and plotting.

```r
library(lisaClust)
library(SingleCellExperiment)

# Generate toy data
set.seed(51773)
x <- round(runif(100), 4) * 100
y <- round(runif(100), 4) * 100
cellType <- factor(rep(c("c1", "c2"), 50))
imageID <- rep("s1", 100)
cells <- data.frame(x, y, cellType, imageID)

# Create SingleCellExperiment object
SCE <- SingleCellExperiment(colData = cells)

# Calculate LISA curves
lisaCurves <- lisa(SCE, Rs = c(20, 50, 100))

# Perform custom k-means clustering
kM <- kmeans(lisaCurves, 2)

# Store custom cluster assignments back into colData
colData(SCE)$custom_region <- paste("region", kM$cluster, sep = "_")
```
*Input: A SingleCellExperiment object. Output: A matrix of calculated LISA curves and custom region cluster assignments stored in colData.*

## When to Use
- **Identifying Tissue Regions**: Use to identify and visualize regions of cell-type colocalization in multiplexed imaging data segmented at single-cell resolution.
- **LISA Curve Generation**: Use `lisa()` to calculate Local Indicators of Spatial Association curves as a localized summary of spatial organization.
- **Cell-Type Enrichment Analysis**: Use `regionMap()` to examine which cell types appear more or less frequently in each identified region than expected by chance.
- **Multi-Region Visualization**: Use `hatchingPlot()` to plot both spatial regions (using hatching patterns) and cell types simultaneously on a single visualization.

## When NOT to Use
- **Pairwise Spatial Association Testing**: For testing pairwise spatial associations between cell types without clustering them into regions, use `spicyR` directly.
- **Non-Spatial Clustering**: For clustering cells based purely on single-cell expression data without spatial coordinates, use standard clustering workflows in `scran` or `Seurat`.

## Data Requirements
- **Input Format**: A `SingleCellExperiment` or `SpatialExperiment` object.
- **Required Metadata (`colData`)**:
  - Spatial coordinates (e.g., `x` and `y` columns).
  - Cell-type annotations (e.g., `cellType` column).
  - Image or sample identifiers (e.g., `imageID` column).

## Key Parameters
- **k** (2): The number of clusters to identify when running `lisaClust()`.
- **Rs** (c(20, 50, 100) in `lisa`): The radii over which the LISA curves will be calculated.
- **type** ("bubble" in `regionMap`): The plot type used to visualize cell-type enrichment across regions.
- **nbp** (300 in `hatchingPlot`): Parameter controlling the grid resolution for the hatching plot.
- **useImages** (NULL): A character vector specifying which images to plot in `hatchingPlot()`.

## Best Practices
- Store cell coordinates, cell types, and image IDs in the `colData` of a `SingleCellExperiment` object before running spatial analyses.
- Use `lisaClust()` as a convenient wrapper to simultaneously calculate LISA curves and perform k-means clustering.
- For custom clustering methods (e.g., SOM or manual k-means), calculate the curves first using `lisa()`, cluster them, and store the assignments back in `colData(SCE)`.
- Use `regionMap(type = "bubble")` to identify which cell types are significantly enriched or depleted in each spatial region.

## Common Pitfalls
- **Missing Spatial Coordinates**: Ensure that spatial coordinates, cell-type annotations, and image IDs are correctly specified and match the column names in `colData` exactly.
- **Inappropriate Radii (`Rs`)**: Choosing radii that are too small or too large relative to cell density can lead to uninformative LISA curves.

## Alternatives
- **spicyR**: For pairwise spatial association analysis.
- **scran**: For non-spatial single-cell clustering.
- **Seurat**: For general single-cell analysis and clustering.

## Citations
- Keren et al. (2018). A Structured Tumor-Immune Microenvironment in Triple Negative Breast Cancer Revealed by Multiplexed Ion Beam Imaging. *Cell*.

## References
- Homepage: bioconductor.org/packages/lisaclust
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/lisaclust/inst/doc/lisaClust.html
