---
name: bioconductor-scarray
description: Provides large-scale single-cell omics data manipulation using Genomic Data Structure (GDS) files. It combines dense and sparse matrices stored in GDS files and the Bioconductor infrastructure framework (SingleCellExperiment and DelayedArray) to provide out-of-memory data storage and large-scale manipulation using the R programming language.
when_to_use: Use when: Overview; Single-cell RNA-seq data manipulation using GDS files; Single-cell RNA-seq analysis (SCArray). Not for: Requires R ≥ 3.5.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# scarray

## Workflows

### Standard Workflow

Convert single-cell data to GDS format, load it as a GDS-backed SingleCellExperiment, and perform memory-efficient downstream analysis.

```r
library(SCArray)
library(SingleCellExperiment)
library(scuttle)
library(scater)

# Load example SingleCellExperiment
fn <- system.file("extdata", "example.rds", package="SCArray")
sce <- readRDS(fn)

# Convert to GDS file
scConvGDS(sce, "test.gds")

# Load SingleCellExperiment from GDS
sce_gds <- scExperiment("test.gds")

# Normalize counts
sce_gds <- logNormCounts(sce_gds)

# Row and column summarization
col_mean <- colMeans(assays(sce_gds)$counts)
mvar <- scRowMeanVar(assays(sce_gds)$counts)

# Memory-efficient PCA and UMAP
sce_gds <- scRunPCA(sce_gds)
sce_gds <- runUMAP(sce_gds)

# Plot PCA
plotReducedDim(sce_gds, dimred="PCA")
```
Input: A SingleCellExperiment object or matrix; Output: A GDS-backed SingleCellExperiment object with normalized counts and reduced dimensions.

## When to Use
- To convert large-scale single-cell datasets (matrices or `SingleCellExperiment` objects) to GDS format using `scConvGDS`.
- To load and manipulate single-cell data out-of-memory as a GDS-backed `SingleCellExperiment` using `scExperiment`.
- To perform memory-efficient row/column summarization (e.g., `colMeans`, `rowMeans`, `scRowMeanVar`) on GDS-backed `DelayedMatrix` objects.
- To run memory-efficient PCA on large-scale single-cell datasets using `scRunPCA`.

## When NOT to Use
- When the dataset is small enough to fit comfortably in memory and standard in-memory matrices are preferred.
- For non-array-oriented genomic data (e.g., raw FASTQ or BAM files).

## Data Requirements
- Input single-cell datasets as a `SingleCellExperiment` object or a dense/sparse matrix (e.g., `dgCMatrix`).
- Output GDS files (`.gds`) containing compressed assay data.

## Key Parameters
- **SCArray.verbose** (`TRUE`/`FALSE`): Global option to enable displaying debug information during SCArray operations.
- **dimred**: The name of the reduced dimension slot to plot in `plotReducedDim` (e.g., `"PCA"`, `"UMAP"`).

## Best Practices
- Use `scRunPCA` instead of `scater::runPCA` for large-scale datasets to avoid high memory usage from realizing the full matrix in memory.
- Enable verbose debugging with `options(SCArray.verbose=TRUE)` to track GDS-backed matrix operations.
- Keep the GDS file connection closed when not in use by calling `scClose` if manually opened with `scOpen`.

## Common Pitfalls
- Attempting to run standard memory-intensive functions (like `scater::runPCA`) on very large GDS-backed objects, which triggers in-memory realization and defeats the out-of-memory benefit. Use `scRunPCA` instead.
- Forgetting that GDS-backed matrices are `DelayedMatrix` objects, meaning operations are delayed until explicitly realized.

## Alternatives
- `HDF5Array`: For HDF5-backed out-of-memory data storage and manipulation.
- `TileDBArray`: For TileDB-backed multi-dimensional array storage.
- `LoomExperiment`: For Loom-backed single-cell data storage.

## Citations
- Zheng et al. (GDS format and gdsfmt package).

## References
- Homepage: bioconductor.org/packages/SCArray
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/SCArray/inst/doc/SCArray.html
