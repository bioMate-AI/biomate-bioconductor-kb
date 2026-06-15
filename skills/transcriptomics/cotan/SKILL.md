---
name: bioconductor-cotan
description: Statistical and computational method to analyze the co-expression of gene pairs at single cell level. It provides the foundation for single-cell gene interactome analysis. The basic idea is studying the zero UMI counts' distribution instead of focusing on positive counts; this is done with a generalized contingency tables framework. COTAN can effectively assess the correlated or anti-correlated expression of gene pairs. It provides a numerical index related to the correlation and an approximate
when_to_use: Use when: Statistical and computational method to analyze the co-expression of gene pairs at single cell level; Guided tutorial to COTAN V.2; Single-cell RNA-seq analysis (COTAN). Not for: Requires R ≥ 4.3 and Bioconductor ≥ 3.16
user-invocable: false
---

# COTAN

## Workflows

### Standard Workflow

Clean raw single-cell UMI count datasets by identifying and removing doublets, dead cells, and low-efficiency cells.

```r
library(COTAN)
library(zeallot)

# Resolve operator precedence conflicts
conflicted::conflict_prefer("%<-%", "zeallot")

# 1. Create COTAN object and initialize metadata
rawDataset <- data.frame(Gene1 = c(1, 0, 5), Gene2 = c(0, 2, 0)) # Mock raw counts
obj <- COTAN(raw = rawDataset)
obj <- initializeMetaDataset(
  obj, 
  GEO = "GSM2861514", 
  sequencingMethod = "Drop_seq", 
  sampleCondition = "mouse_cortex_E17.5"
)

# 2. Add condition metadata
data(vignette.cells.origin)
obj <- addCondition(obj, condName = "origin", conditions = vignette.cells.origin)

# 3. Drop problematic cells and run cleaning
obj <- dropGenesCells(obj, cells = c())
obj <- clean(obj)

# 4. Generate diagnostic plots
c(pcaCellsPlot, pcaCellsData, genesPlot, UDEPlot, nuPlot, zoomedNuPlot) %<-% cleanPlots(obj)
```
*Note on inputs/outputs:* Input is a raw UMI count matrix; output is a cleaned and filtered `COTAN` object with estimated cell efficiency (`nu`) parameters.

### Cell Clustering And Dea

Cluster cells based on expression uniformity and perform differential expression analysis (DEA) on the resulting clusters.

```r
library(COTAN)

# 1. Load pre-calculated clusterizations
data("vignette.split.clusters", package = "COTAN")
vignette.split.clusters <- asClusterization(
  vignette.split.clusters, 
  allCells = getCells(obj)
)

# 2. Execute Differential Expression Analysis on clusters
vignette.split.coexDF <- DEAOnClusters(obj, clusters = vignette.split.clusters)

# 3. Save outputs to the COTAN object
obj <- addClusterization(
  obj, 
  clName = "split", 
  clusters = vignette.split.clusters, 
  coexDF = vignette.split.coexDF, 
  override = FALSE
)
```
*Note on inputs/outputs:* Input is a `COTAN` object and a clusterization vector; output is a `COTAN` object updated with cluster-specific differential expression analysis (DEA) coefficients.

### Gene Coexpression And Clustering

Calculate gene-pair co-expression (COEX), calculate Global Differentiation Index (GDI), and establish gene clusters.

```r
library(COTAN)

# 1. Calibrate the COTAN model and estimate dispersion
obj <- proceedToCoex(
  obj, 
  calcCoex = FALSE, 
  optimizeForSpeed = TRUE, 
  cores = 3L
)

# 2. Retrieve and manipulate clusters
splitClusters <- getClusters(obj, clName = "split")
splitClustersAsList <- toClustersList(splitClusters)
```
*Note on inputs/outputs:* Input is a cleaned `COTAN` object; output is a `COTAN` object with estimated dispersion parameters and cluster lists.

## When to Use
- **Gene Co-expression Analysis:** Assess correlated or anti-correlated expression of gene pairs at the single-cell level using zero UMI count distributions.
- **Dataset Cleaning:** Identify and drop low-quality cells, doublets, or cells with high mitochondrial percentages using `dropGenesCells` and `clean`.
- **Differential Expression Analysis (DEA):** Assess gene enrichment or depletion across cell clusters using `DEAOnClusters`.
- **Cluster Reordering:** Reorder cluster labels based on transcriptional similarity using `reorderClusterization`.

## When NOT to Use
- **Standard Highly Variable Gene Selection:** For traditional highly variable gene selection and PCA-based clustering without the zero-count contingency framework, use `Seurat` or `scran`.
- **Trajectory-Based Differential Expression:** For modeling continuous gene expression changes along pseudotime, use `tradeSeq` or `condiments`.

## Data Requirements
- **Raw Counts:** A matrix or data frame of raw, unnormalized UMI counts (rows as genes, columns as cells).
- **Example Structure:**
  ```r
  rawDataset <- read.csv(datasetFileName, sep = "\t", row.names = 1L)
  obj <- COTAN(raw = rawDataset)
  ```

## Key Parameters
- **raw**: A data frame or matrix of raw UMI counts passed to `COTAN()`.
- **calcCoex** (TRUE/FALSE): Logical indicating whether to evaluate the gene-pair COEX matrix in `proceedToCoex()`.
- **optimizeForSpeed** (TRUE): Logical to optimize calculations for speed in `proceedToCoex()`.
- **cores** (1L): Number of cores to use for multi-processing.
- **clName**: Name of the clusterization to add or retrieve from the COTAN object.
- **override** (FALSE): Logical indicating whether to overwrite an existing clusterization in `addClusterization()`.

## Best Practices
- **Initialize Metadata:** Always run `initializeMetaDataset` immediately after creating the `COTAN` object to store experimental metadata.
- **Quality Control Plots:** Check `cellSizePlot`, `genesSizePlot`, and `mitochondrialPercentagePlot` to determine appropriate thresholds before dropping cells.
- **Re-run Clean:** Run `clean()` after dropping any genes or cells to re-estimate the cell efficiency (`nu`) parameters.
- **Check UDE Correlation:** Verify that cell efficiency (UDE) does not strongly correlate with principal components using `UDEPlot`.

## Common Pitfalls
- **Operator Precedence Conflicts:** When using multi-assignment (`%<-%`), resolve operator precedence conflicts by calling `conflicted::conflict_prefer("%<-%", "zeallot")`.
- **High Memory/Time Usage:** Calculating the full gene-pair COEX matrix can be resource-intensive; set `calcCoex = FALSE` in `proceedToCoex()` if only cluster-level DEA is needed.
- **Out-of-Date Nu Parameters:** Forgetting to run `clean()` or `estimateNuLinear()` after dropping cells will lead to inaccurate downstream analyses.

## Alternatives
- **Seurat**: For general single-cell RNA-seq analysis, clustering, and visualization.
- **scater** / **scran**: For standard single-cell quality control, normalization, and highly variable gene selection.

## Citations
- Yuzwa et al. 2017, Cell Reports (Mouse cortex dataset source)

## References
- Homepage: https://bioconductor.org/packages/COTAN
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/COTAN/inst/doc/COTAN.html
