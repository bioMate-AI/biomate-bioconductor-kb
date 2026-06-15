---
name: bioconductor-nnsvg
description: Method for scalable identification of spatially variable genes (SVGs) in spatially-resolved transcriptomics data. The method is based on nearest-neighbor Gaussian processes and uses the BRISC algorithm for model fitting and parameter estimation. Allows identification and ranking of SVGs with flexible length scales across a tissue slide or within spatial domains defined by covariates. Scales linearly with the number of spatial locations and can be applied to datasets containing thousands or more
when_to_use: Use when: Method for scalable identification of spatially variable genes (SVGs) in spatially-resolved transcriptomics data; Single-cell RNA-seq analysis (nnSVG). Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# nnSVG

## Workflows

### Standard Workflow

```r
library(SpatialExperiment)
library(nnSVG)

# Filter low-expressed and mitochondrial genes
spe <- filter_genes(spe)

# Calculate logcounts using library size factors
spe <- computeLibraryFactors(spe)
spe <- logNormCounts(spe)

# Run nnSVG to identify spatially variable genes
spe <- nnSVG(spe)
```
Input: A `SpatialExperiment` object containing raw counts and spatial coordinates.
Output: A `SpatialExperiment` object with SVG ranking and statistics stored in `rowData`.

## When to Use
- Identifying spatially variable genes (SVGs) in spatially-resolved transcriptomics datasets (e.g., Visium, Slide-seq).
- Identifying SVGs within spatial domains or cell types by incorporating covariates using the `X` parameter in `nnSVG`.
- Scaling SVG identification to large datasets with thousands of spatial locations.

## When NOT to Use
- For non-spatial single-cell RNA-seq data, use standard highly variable gene (HVG) selection in `scran` or `Seurat`.
- For simple differential expression between pre-defined clusters without spatial modeling, use `findMarkers` from `scran`.

## Data Requirements
- A `SpatialExperiment` object containing a `counts` assay and spatial coordinates (accessible via `spatialCoords`).
- Alternatively, a numeric matrix of log-transformed normalized counts and a matrix of spatial coordinates.

## Key Parameters
- **X** (NULL): A model matrix of covariates (e.g., cell types or spatial domains) to include in the model.
- **filter_genes_ncounts** (3): Minimum number of counts for gene filtering in `filter_genes`.
- **filter_genes_pcspots** (0.5): Minimum percentage of spots with counts for gene filtering in `filter_genes`.
- **filter_mito** (TRUE): Whether to filter out mitochondrial genes in `filter_genes`.

## Best Practices
- Filter out low-expressed genes using `filter_genes` before running `nnSVG` to avoid errors and reduce runtime.
- Re-calculate library size factors and log-normalized counts after filtering genes.
- For multi-sample datasets, run `nnSVG` individually per sample and combine results by averaging ranks.

## Common Pitfalls
- Running `nnSVG` on rows (genes) or columns (spots) containing all zero counts; ensure proper filtering using `filter_genes` or manual subsetting.
- Empty levels in factor covariates when creating the design matrix; use `droplevels()` to remove them.

## Alternatives
- `SpatialDE` for spatial variable gene identification.
- `Spark` / `SPARK-G` for statistical modeling of SVGs.
- `scran` for non-spatial highly variable gene selection.

## Citations
- Weber and Hicks 2026 (or Weber et al., Nature Communications)
- Datta et al., 2016 (Nearest-neighbor Gaussian processes)
- Saha and Datta, 2018 (BRISC algorithm)

## References
- Homepage: bioconductor.org/packages/nnSVG
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/nnSVG/inst/doc/nnSVG.html
