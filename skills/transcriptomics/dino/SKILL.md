---
name: bioconductor-dino
description: Dino normalizes single-cell, mRNA sequencing data to correct for technical variation, particularly sequencing depth, prior to downstream analysis. The approach produces a matrix of corrected expression for which the dependency between sequencing depth and the full distribution of normalized expression; many existing methods aim to remove only the dependency between sequencing depth and the mean of the normalized expression. This is particuarly useful in the context of highly sparse datasets such
when_to_use: Use when: Normalization by distributional resampling of high throughput single-cell RNA-sequencing data; Single-cell RNA-seq analysis (Dino); Data normalization and preprocessing (Dino). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# Dino

## Workflows

### Standard Workflow

Filter and normalize a raw UMI count matrix using Dino, then convert it to a Seurat object for downstream clustering and visualization.

```r
library(Dino)
library(Seurat)
library(Matrix)

# Load dataset
data("pbmcSmall")

# 1. Filter out genes with low non-zero expression
pbmcSmall <- pbmcSmall[rowSums(pbmcSmall != 0) >= 20, ]

# Normalize data
pbmcSmall_Norm <- Dino(pbmcSmall)

# 2. Run downstream Seurat clustering and visualization
pbmcSmall_Seurat <- SeuratFromDino(pbmcSmall_Norm, doNorm = FALSE)
pbmcSmall_Seurat <- FindVariableFeatures(pbmcSmall_Seurat, selection.method = "mvp")
pbmcSmall_Seurat <- ScaleData(pbmcSmall_Seurat, features = rownames(pbmcSmall_Norm))
pbmcSmall_Seurat <- RunPCA(pbmcSmall_Seurat, features = VariableFeatures(object = pbmcSmall_Seurat), verbose = FALSE)
pbmcSmall_Seurat <- FindNeighbors(pbmcSmall_Seurat, dims = 1:10)
pbmcSmall_Seurat <- FindClusters(pbmcSmall_Seurat, verbose = FALSE)
pbmcSmall_Seurat <- RunUMAP(pbmcSmall_Seurat, dims = 1:10)
DimPlot(pbmcSmall_Seurat, reduction = "umap")
```
*Note on inputs/outputs*: Input is a raw UMI count matrix (`pbmcSmall`), and output is a fully processed and clustered `Seurat` object.

### Single Cell Experiment Normalization

Normalize scRNA-seq data formatted as a SingleCellExperiment object using Dino.

```r
library(SingleCellExperiment)
library(Dino)

# Load dataset
data("pbmcSmall")

# Create a SingleCellExperiment object from the count matrix
pbmc_SCE <- SingleCellExperiment(assays = list("counts" = pbmcSmall))

# Run Dino
pbmc_SCE <- Dino_SCE(pbmc_SCE)

# Inspect or extract the normalized counts using normcounts
normalized_counts <- normcounts(pbmc_SCE)
str(normalized_counts)
```
*Note on inputs/outputs*: Input is a `SingleCellExperiment` object containing raw counts, and output is the same object with normalized counts accessible via `normcounts()`.

### Custom Depth Normalization

Normalize a UMI count matrix using Dino with custom sequencing depths calculated via Scran size factors.

```r
library(Dino)
library(scran)

# Load dataset
data("pbmcSmall")

# Compute size factors using Scran's calculateSumFactors
scranSizes <- calculateSumFactors(pbmcSmall)

# Re-normalize data with custom depths
pbmcSmall_SNorm <- Dino(pbmcSmall, nCores = 1, depth = log(scranSizes))
```
*Note on inputs/outputs*: Input is a raw UMI count matrix, and output is a normalized sparse matrix using custom log-transformed size factors.

## When to Use
- Normalizing high-throughput single-cell RNA-sequencing (scRNA-seq) UMI count data to correct for technical variation in sequencing depth using `Dino()`.
- Integrating normalized expression matrices directly into Seurat workflows using `SeuratFromDino()`.
- Normalizing data structured as a `SingleCellExperiment` object using `Dino_SCE()`.

## When NOT to Use
- For non-UMI sequencing protocols (e.g., traditional bulk RNA-seq), use packages like `DESeq2` or `edgeR` because Dino is specifically designed and optimized for UMI count data.
- For correcting batch effects or other sample-specific effects, use packages like `Combat` or `harmony` because Dino only corrects for technical variation correlated with sequencing depth.

## Data Requirements
- **Input format**: Sparse or dense matrix of expression (e.g., `dgCMatrix` or standard matrix) with genes (features) on the rows and cells (samples) on the columns.
- **Structure**: Non-negative integer UMI counts (e.g., `pbmcSmall`).
- **Normalization state**: Raw, un-normalized count data.

## Key Parameters
- **nCores** (2): Number of parallel instances/threads to run. Setting to 0 utilizes all available cores.
- **depth** (NULL): Alternate cell-specific sequencing depths (e.g., log of `scran` size factors).
- **doNorm** (TRUE): Logical indicating whether to perform normalization inside `SeuratFromDino()`.
- **doLog** (TRUE): Logical indicating whether to log-transform expression as log(x + 1) in `SeuratFromDino()`.

## Best Practices
- Filter out genes lacking a minimum of non-zero expression (e.g., keeping genes with at least 20 non-zero samples using `rowSums(pbmcSmall != 0) >= 20`) prior to normalization to improve downstream analysis.
- Set a random seed using `set.seed()` before running Dino to ensure reproducibility of the distributional resampling.
- Ensure that when providing custom sequencing depths via `depth`, the median depth is close to 1.

## Common Pitfalls
- Running Dino on non-UMI datasets: This can lead to poor normalization because Dino's Negative Binomial mixture model is specifically tailored for sparse UMI data. Fix by using Dino only on UMI counts.
- Failing to filter low-expression genes: Dino will default to simple scaling with sequencing depth for genes with fewer than 10 non-zero samples. Fix by filtering genes with low non-zero expression (e.g., `rowSums(counts != 0) >= 20`) beforehand.

## Alternatives
- `Seurat`: For comprehensive single-cell workflows including alternative normalization methods like SCTransform.
- `scran`: For pooling-based normalization of single-cell data using `calculateSumFactors`.
- `scater`: For quality control and visualization of single-cell RNA-seq data.

## Citations
- Brown, J., Ni, Z., Mohanty, C., Bacher, R., and Kendziorski, C. (2021). "Normalization by distributional resampling of high throughput single-cell RNA-sequencing data." Bioinformatics, 37, 4123-4128.
- Lun, A. T. L., Bach, K. and Marioni, J. C. (2016). "Pooling across cells to normalize single-cell RNA sequencing data with many zero counts." Genome Biol., 17, 1–14.

## References
- Homepage: https://bioconductor.org/packages/Dino
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Dino/inst/doc/Dino.html
