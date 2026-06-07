---
name: bioconductor-scater
description: A collection of tools for doing various analyses of single-cell RNA-seq gene expression data, with a focus on quality control and visualization.
when_to_use: Use when: Compute per-cell QC metrics (nGenes, total UMI, % mitochondrial); Identify and remove low-quality cells using adaptive thresholds; Visualize dimensionality reductions (PCA, UMAP, t-SNE); Diagnostic plots for expression distributions before/after normalization
user-invocable: false
---

# scater — Comprehensive Skill Guide

> **Domain:** Single-cell / QC
> **Bioconductor:** [scater](https://bioconductor.org/packages/release/bioc/html/scater.html)
> **Paper:** McCarthy DJ et al. (2017). Bioinformatics, 33(8):1179-1186.

Single-cell RNA-seq QC, normalization, and visualization toolkit. Provides perCellQCMetrics, plotReducedDim, and a rich set of diagnostic plots for SCE objects.

## When to Use

- Compute per-cell QC metrics (nGenes, total UMI, % mitochondrial)
- Identify and remove low-quality cells using adaptive thresholds
- Visualize dimensionality reductions (PCA, UMAP, t-SNE)
- Diagnostic plots for expression distributions before/after normalization

**Alternatives:** `Seurat (QC + visualization)`, `scanpy (Python)`

## Do NOT Use When

- Bulk RNA-seq — use DESeq2/edgeR for DE and plotMDS for visualization.
- Spatial transcriptomics without SPE-aware tools.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | SingleCellExperiment with count assay |
| **Notes** | Run quality filtering BEFORE normalization and dimensionality reduction |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("scater")
library(scater)
```

## Workflows

### scRNA-seq QC, Normalization, and Visualization
*Standard scRNA-seq QC pipeline using scater*

#### Compute QC metrics

```r
library(scater)
library(scuttle)
# Find mitochondrial genes
is_mito <- grepl("^MT-", rownames(sce))

# Compute per-cell QC metrics
df <- perCellQCMetrics(sce, subsets=list(Mito=is_mito))
colnames(df)
# sum, detected, subsets_Mito_sum, subsets_Mito_percent, etc.
```

#### Adaptive outlier filtering

```r
# One-step adaptive QC
qc_out <- quickPerCellQC(df,
                          percent_subsets="subsets_Mito_percent",
                          nmads=3)
# qc_out has logical discard column + reason columns
table(qc_out$discard)
table(qc_out$reasons)
```

#### Inspect QC metrics before filtering

```r
colData(sce) <- cbind(colData(sce), df)
sce$discard <- qc_out$discard

# Scatter plot: total UMI vs % mito
plotColData(sce, x="sum", y="subsets_Mito_percent",
            colour_by="discard") +
    geom_hline(yintercept=20, lty=2)

# Violin plots
plotColData(sce, y="detected", colour_by="Sample")
```

#### Filter and normalize

```r
sce_qc <- sce[, !qc_out$discard]
sce_qc <- logNormCounts(sce_qc)  # adds 'logcounts' assay
```

#### Dimensionality reduction and visualization

```r
# Feature selection
library(scran)
dec <- modelGeneVar(sce_qc)
hvgs <- getTopHVGs(dec, n=3000)

sce_qc <- runPCA(sce_qc, subset_row=hvgs, ncomponents=50)
sce_qc <- runUMAP(sce_qc, dimred="PCA")

# Plot UMAP colored by cluster or gene expression
plotReducedDim(sce_qc, "UMAP", colour_by="cluster")
plotReducedDim(sce_qc, "UMAP", colour_by="CD3E")  # any gene
```

## Key Functions & Parameters

### `perCellQCMetrics()()`

Compute per-cell QC statistics

| Parameter | Description |
|-----------|-------------|
| `x` | SingleCellExperiment or matrix |
| `subsets` | named list of gene sets for subset metrics (e.g. list(Mito=mito_genes)) |
| `use_altexps` | include altExp (spike-ins) in metrics |

### `quickPerCellQC()()`

One-step QC: compute metrics + adaptive outlier detection

| Parameter | Description |
|-----------|-------------|
| `x` | per-cell QC metrics DataFrame |
| `percent_subsets` | name of % subset column to filter on (e.g. 'subsets_Mito_percent') |
| `nmads` | number of MADs for outlier threshold (default 3) |

### `plotReducedDim()()`

Plot any reducedDim (UMAP, PCA, t-SNE)

| Parameter | Description |
|-----------|-------------|
| `object` | SingleCellExperiment |
| `dimred` | name of reducedDim to plot ('UMAP', 'PCA') |
| `colour_by` | column in colData to color cells |
| `point_size` | size of plotted points |

### `plotHighestExprs()()`

Bar chart of genes with highest average expression — QC diagnostic


### `plotExpression()()`

Violin/box plots of expression for selected genes

| Parameter | Description |
|-----------|-------------|
| `object` | SingleCellExperiment |
| `features` | gene names or indices |
| `x` | colData variable for x-axis grouping |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Outlier cells (by MAD-based thresholds) represent low-quality captures or doublets.
- % mitochondrial reads is a proxy for cell damage (high mito% → damaged cells).

## Result Interpretation

- `perCellQCMetrics()`: `sum` = total UMI, `detected` = genes with ≥1 count, `subsets_Mito_percent` = % mito reads.
- Adaptive outlier thresholds: cells >3 MADs from median in sum/detected/mito% are flagged.
- PCA plot: expect smooth continuum for heterogeneous tissue; distinct clusters suggest cell types.
- Outlier cells on PCA (isolated far from bulk) may be doublets or damaged cells.

## Best Practices

- Use `perCellQCMetrics(sce, subsets=list(Mito=grep('^MT-', rownames(sce))))` for human data.
- Use adaptive outlier thresholds (`quickPerCellQC`) rather than fixed cutoffs to account for dataset heterogeneity.
- Inspect `plotColData(sce, x='sum', y='subsets_Mito_percent')` to choose QC thresholds.
- Use `runPCA(sce)`, `runUMAP(sce)` before `plotReducedDim()` — these add to `reducedDims(sce)`.
- Never filter on a single metric; use multi-metric outlier detection to avoid losing true biology.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `Seurat (QC module)` | You are already in the Seurat ecosystem. | You want Bioconductor-native adaptive outlier detection with MAD thresholds. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **McCarthy DJ et al. (2017). Bioinformatics 33:1179.** [PMID:28088785](https://pubmed.ncbi.nlm.nih.gov/28088785)  
  scater provides robust QC metrics and visualization that outperform simple library-size filtering.

## Common Errors & Troubleshooting

### `Error: 'UMAP' not in reducedDimNames()`

**Cause:** runUMAP() not called before plotReducedDim()

**Fix:** Call `sce <- runUMAP(sce)` first

## Additional Notes from Official Documentation

*Extracted from the scater Bioconductor vignette(s)*

### 1 Introduction


scater provides tools for visualization of single-cell transcriptomic data.
It is based on the SingleCellExperiment class (from the SingleCellExperiment package),
and thus is interoperable with many other Bioconductor packages such as scran , scuttle and iSEE .
To demonstrate the use of the various scater functions,
we will load in the classic Zeisel dataset:
Note: A more comprehensive description of the use of scater (along with other packages) in a scRNA-seq analysis workflow is available at https://osca.bioconductor.org .

```r
library(scRNAseq)
example_sce <- ZeiselBrainData()
example_sce
```

```r
## class: SingleCellExperiment 
## dim: 20006 3005 
## metadata(0):
## assays(1): counts
## rownames(20006): Tspan12 Tshz1 ... mt-Rnr1 mt-Nd4l
## rowData names(1): featureType
## colnames(3005): 1772071015_C02 1772071017_G12 ... 1772066098_A12
##   1772058148_F03
## colData names(9): tissue group # ... level1class level2class
## reducedDimNames(0):
## mainExpName: gene
## altExpNames(2): repeat ERCC
```

### 2 Diagnostic plots for quality control


Quality control to remove damaged cells and poorly sequenced libraries is a common step in single-cell analysis pipelines.
We will use some utilities from the scuttle package
(conveniently loaded for us when we load scater )
to compute the usual quality control metrics for this dataset.
Metadata variables can be plotted against each other using the plotColData() function, as shown below.
We expect to see an increasing number of detected genes with increasing total count.
Each point represents a cell that is coloured according to its tissue of origin.
Here, we have plotted the total count for each cell against the mitochondrial content.
Well-behaved cells should have a large number of expressed features and and a low percentage of expression from feature controls.
High percentage expressio

```r
library(scater)
example_sce <- addPerCellQC(example_sce, 
    subsets=list(Mito=grep("mt-", rownames(example_sce))))
```

```r
plotColData(example_sce, x = "sum", y="detected", colour_by="tissue")
```

### 3 Visualizing expression values


The plotExpression() function makes it easy to plot expression values for a subset of genes or features.
This can be particularly useful for further examination of features identified from differential expression testing, pseudotime analysis or other analyses.
By default, it uses expression values in the "logcounts" assay, but this can be changed through the exprs_values argument.
Setting x will determine the covariate to be shown on the x-axis.
This can be a field in the column metadata or the name of a feature (to obtain the expression profile across cells).
Categorical covariates will yield grouped violins as shown above, with one panel per feature.
By comparison, continuous covariates will generate a scatter plot in each panel, as shown below.
The points can also be coloured, shaped o

```r
plotExpression(example_sce, rownames(example_sce)[1:6], x = "level1class")
```

```r
plotExpression(example_sce, rownames(example_sce)[1:6],
    x = rownames(example_sce)[10])
```

### 4.1 Principal components analysis


Principal components analysis (PCA) is often performed to denoise and compact the data prior to downstream analyses.
The runPCA() function provides a simple wrapper around the base machinery in BiocSingular for computing PCs from log-transformed expression values.
This stores the output in the reducedDims slot of the SingleCellExperiment , which can be easily retrieved (along with the percentage of variance explained by each PC) as shown below:
By default, runPCA() uses the top 500 genes with the highest variances to compute the first PCs.
This can be tuned by specifying subset_row to pass in an explicit set of genes of interest,
and by using ncomponents to determine the number of components to compute.
The name argument can also be used to change the name of the result in the reducedDims

```r
example_sce <- runPCA(example_sce)
str(reducedDim(example_sce, "PCA"))
```

```r
##  num [1:3005, 1:50] -15.4 -15 -17.2 -16.9 -18.4 ...
##  - attr(*, "dimnames")=List of 2
##   ..$ : chr [1:3005] "1772071015_C02" "1772071017_G12" "1772071017_A05" "1772071014_B06" ...
##   ..$ : chr [1:50] "PC1" "PC2" "PC3" "PC4" ...
##  - attr(*, "varExplained")= num [1:50] 478 112.8 51.1 47 33.2 ...
##  - attr(*, "percentVar")= num [1:50] 39.72 9.38 4.25 3.9 2.76 ...
##  - attr(*, "rotation")= num [1:500, 1:50] 0.1471 0.1146 0.1084 0.0958 0.0953 ...
##   ..- attr(*, "dimnames")=List of 2
##   .. ..$ : chr [1:500] "Plp1" "Trf" "Mal" "Apod" ...
##   .. ..$ : chr [1:50] "PC1" "PC2" "PC3" "PC4" ...
```

### 4.2 Other dimensionality reduction methods


\(t\) -distributed stochastic neighbour embedding ( \(t\) -SNE) is widely used for visualizing complex single-cell data sets.
The same procedure described for PCA plots can be applied to generate \(t\) -SNE plots using plotTSNE , with coordinates obtained using runTSNE via the Rtsne package.
We strongly recommend generating plots with different random seeds and perplexity values, to ensure that any conclusions are robus
t to different visualizations.
A more common pattern involves using the pre-existing PCA results as input into the \(t\) -SNE algorithm.
This is useful as it improves speed by using a low-rank approximation of the expression matrix; and reduces random noise, by focusing on the major factors of variation.
The code below uses the first 10 dimensions of the previously compute

```r
# Perplexity of 10 just chosen here arbitrarily.
set.seed(1000)
example_sce <- runTSNE(example_sce, perplexity=10)
head(reducedDim(example_sce, "TSNE"))
```

```r
##                    TSNE1      TSNE2
## 1772071015_C02 -52.20650 -11.388339
## 1772071017_G12 -55.13973 -10.384870
## 1772071017_A05 -51.84183 -11.289268
## 1772071014_B06 -54.70043 -10.173423
## 1772067065_H06 -54.25904  -9.833723
## 1772071017_E02 -55.25140  -9.888935
```

### 4.3 Visualizing reduced dimensions


Any dimensionality reduction result can be plotted using the plotReducedDim function.
Here, each point represents a cell and is coloured according to its cell type label.
Some result types have dedicated wrappers for convenience, e.g., plotTSNE() for \(t\) -SNE results:
The dedicated plotPCA() function also adds the percentage of variance explained to the axes:
Multiple components can be plotted in a series of pairwise plots.
When more than two components are plotted, the diagonal boxes in the scatter plot matrix show the density for each component.
We separate the execution of these functions from the plotting to enable the same coordinates to be re-used across multiple plots.
This avoids repeatedly recomputing those coordinates just to change an aesthetic across plots.

```r
plotReducedDim(example_sce, dimred = "PCA", colour_by = "level1class")
```

```r
plotTSNE(example_sce, colour_by = "Snap25")
```

### 5 Utilities for custom visualization


We provide some helper functions to easily convert from a SingleCellExperiment object to a data.frame for use in, say, ggplot2 functions.
This allows users to create highly customized plots that are not covered by the existing scater functions.
The ggcells() function will intelligently retrieve fields from the colData() , assays() , altExps() or reducedDims() to create a single data.frame for immediate use.
In the example below, we create boxplots of Snap25 expression stratified by cell type and tissue of origin:
Reduced dimension results are easily pulled in to create customized equivalents of the plotReducedDim() output.
In this example, we create a \(t\) -SNE plot faceted by tissue and coloured by Snap25 expression:
It is also straightforward to examine the relationship between the siz

```r
ggcells(example_sce, mapping=aes(x=level1class, y=Snap25)) + 
    geom_boxplot() +
    facet_wrap(~tissue)
```

```r
ggcells(example_sce, mapping=aes(x=TSNE.1, y=TSNE.2, colour=Snap25)) +
    geom_point() +
    stat_density_2d() +
    facet_wrap(~tissue) +
    scale_colour_distiller(direction=1)
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/scater.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/scater.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** McCarthy DJ et al. (2017). Bioinformatics, 33(8):1179-1186.

---
