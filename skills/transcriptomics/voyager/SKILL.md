---
name: bioconductor-voyager
description: SpatialFeatureExperiment (SFE) is a new S4 class for working with spatial single-cell genomics data. The voyager package implements basic exploratory spatial data analysis (ESDA) methods for SFE. Univariate methods include univariate global spatial ESDA methods such as Moran's I, permutation testing for Moran's I, and correlograms. Bivariate methods include Lee's L and cross variogram. Multivariate methods include MULTISPATI PCA and multivariate local Geary's C recently developed by Anselin. The
when_to_use: Use when: SpatialFeatureExperiment (SFE) is a new S4 class for working with spatial single-cell genomics data; Functionality overview. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# Voyager

## Workflows

### Standard Workflow

Perform exploratory spatial data analysis (ESDA) on spatial transcriptomics data, including univariate, bivariate, and multivariate spatial statistics, and visualize the results over tissue geometries.

```r
library(SFEData)
library(SpatialFeatureExperiment)
library(SpatialExperiment)
library(ggplot2)
library(Voyager)
library(scater)
library(scran)
library(pheatmap)

# 1. Load required libraries & 2. Read dataset
sfe <- McKellarMuscleData()

# 3. Add and mirror the tissue image
sfe <- addImg(sfe, imageSource = "tissue_lowres_5a.jpeg", sample_id = "Vis5A", image_id = "lowres", scale_fct = 1024/22208)
sfe <- mirrorImg(sfe, sample_id = "Vis5A", image_id = "lowres")

# 4. Filter spots and normalize counts
sfe <- sfe[, colData(sfe)$in_tissue]
sfe <- logNormCounts(sfe)

# 5. Construct a spatial neighborhood graph
colGraph(sfe, "visium") <- findVisiumGraph(sfe)

# 6. Run univariate spatial statistics (Moran's I and Getis-Ord Gi*)
features_use <- c("Myh1", "Myh2")
sfe <- runUnivariate(sfe, type = "moran", features = features_use, colGraphName = "visium", swap_rownames = "symbol")
sfe <- runUnivariate(sfe, type = "localG", features = features_use, colGraphName = "visium", include_self = TRUE, swap_rownames = "symbol")

# 7. Identify highly variable genes and calculate bivariate spatial correlation (Lee's L)
gs <- modelGeneVar(sfe)
hvgs <- getTopHVGs(gs, fdr.threshold = 0.01)
res <- calculateBivariate(sfe, "lee", hvgs)

# 8. Perform spatially-informed dimension reduction (MULTISPATI PCA)
hvgs2 <- getTopHVGs(gs, n = 1000)
sfe <- runMultivariate(sfe, "multispati", colGraphName = "visium", subset_row = hvgs2, nfposi = 10, nfnega = 10)

# 9. Visualize results
plotSpatialFeature(sfe, c("nCounts", "Myh1"), colGeometryName = "spotPoly", annotGeometryName = "myofiber_simplified", aes_use = "color", swap_rownames = "symbol")
plotLocalResult(sfe, "localG", features = features_use, colGeometryName = "spotPoly", divergent = TRUE, swap_rownames = "symbol")
ElbowPlot(sfe, ndims = 10, nfnega = 10, reduction = "multispati")
spatialReducedDim(sfe, "multispati", ncomponents = 2, divergent = TRUE)
```
*Input: A SpatialFeatureExperiment object and a tissue image. Output: Spatial plots of gene expression, local spatial statistics, eigenvalues, and reduced dimensions.*

## When to Use
- To perform exploratory spatial data analysis (ESDA) on spatial transcriptomics data structured as a `SpatialFeatureExperiment` (SFE) object.
- To compute univariate global and local spatial statistics such as Moran's I (using `runUnivariate` with `type = "moran"`) and Getis-Ord Gi* (using `type = "localG"`).
- To calculate bivariate spatial correlation (e.g., Lee's L via `calculateBivariate`) to identify spatially co-expressed gene modules.
- To run spatially-informed dimension reduction like MULTISPATI PCA (using `runMultivariate` with `type = "multispati"`).

## When NOT to Use
- For non-spatial single-cell RNA-seq data; use standard `SingleCellExperiment` and `scater` instead.
- If you need to perform cell type deconvolution or spatial domain segmentation directly; use specialized packages like `Seurat` or `Giotto`.

## Data Requirements
- A `SpatialFeatureExperiment` (SFE) object containing spatial coordinates, count matrices, and spot/annotation geometries (e.g., `spotPoly`).
- A spatial neighborhood graph constructed and stored in the SFE object (e.g., using `findVisiumGraph`).

## Key Parameters
- **type** ("moran" / "localG" / "lee" / "multispati"): The spatial statistic method to run.
- **colGraphName** ("visium"): The name of the spatial neighborhood graph stored in the SFE object.
- **include_self** (TRUE): For Getis-Ord Gi*, determines whether to include self-directing edges in the spatial graph.
- **swap_rownames** ("symbol"): Column in `rowData` to swap rownames with (e.g., to use human-readable gene symbols instead of Ensembl IDs).
- **nfposi** (10): Number of positive spatial autocorrelation components to retain in MULTISPATI PCA.
- **nfnega** (10): Number of negative spatial autocorrelation components to retain in MULTISPATI PCA.
- **divergent** (TRUE): Logical indicating whether to use a divergent color palette for local spatial statistics or reduced dimensions.

## Best Practices
- Always construct a spatial neighborhood graph using `findVisiumGraph` before running any spatial statistics.
- Mirror the tissue image using `mirrorImg` if the origin of the image (top-left) does not align with the origin of the spots (bottom-left).
- Filter spots to keep only those in tissue (`colData(sfe)$in_tissue`) and normalize counts using `logNormCounts` before analysis.

## Common Pitfalls
- Mismatch between image and spot coordinates: Ensure you call `mirrorImg` to flip the image if coordinates are inverted.
- Missing spatial graph: Forgetting to assign the output of `findVisiumGraph` to `colGraph(sfe, "visium")` will cause downstream spatial functions to fail.

## Alternatives
- `spdep` for classic geospatial analysis.
- `adespatial` for multivariate spatial analysis (MULTISPATI PCA).
- `scater` for non-spatial single-cell exploratory data analysis.

## Citations
- Moses L, Pachter L (2026). Voyager: Exploratory Spatial Data Analysis for Spatial Bioconductor. R package.

## References
- Homepage: bioconductor.org/packages/Voyager
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Voyager/inst/doc/voyager.html
