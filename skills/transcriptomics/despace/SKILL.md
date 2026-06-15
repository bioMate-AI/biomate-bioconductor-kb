---
name: bioconductor-despace
description: Intuitive framework for identifying spatially variable genes (SVGs) via edgeR, a popular method for performing differential expression analyses. Based on pre-annotated spatial clusters as summarized spatial information, DESpace models gene expression using a negative binomial (NB), via edgeR, with spatial clusters as covariates. SVGs are then identified by testing the significance of spatial clusters. The method is flexible and robust, and is faster than the most SV methods. Furthermore, to the
when_to_use: Use when: A framework to discover spatially variable genes; Differential expression analysis (DESpace); Single-cell RNA-seq analysis (DESpace). Not for: Requires biological replicates for statistical analysis; Requires R ≥ 4.3.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# DESpace

## Workflows

### Standard Workflow

Identify spatially variable genes (SVGs) across tissue regions globally or within individual spatial clusters for single or multiple biological replicates.

```r
library(DESpace)
library(SpatialExperiment)

# Assuming spe3 is a SpatialExperiment object with spatial clusters in 'layer_guess_reordered'
results <- svg_test(spe = spe3, cluster_col = "layer_guess_reordered", verbose = TRUE)

# Test individual clusters using pre-computed dispersions
cluster_results <- individual_svg(spe3, edgeR_y = results$estimated_y, cluster_col = "layer_guess_reordered")

# Combine results
merge_res <- top_results(results$gene_results, cluster_results)
```
*Inputs are a SpatialExperiment object with annotated spatial clusters; outputs are gene-level and cluster-level spatial variability statistics.*

### Differential Spatial Patterns

Identify genes with differential spatial expression patterns (DSPs) across multiple experimental conditions or time points.

```r
library(DESpace)
library(SpatialExperiment)

# Assuming spe.combined is a combined SpatialExperiment object with multiple samples
multi_results <- svg_test(spe = spe.combined, 
                          cluster_col = "layer_guess_reordered", 
                          sample_col = "sample_id", 
                          replicates = TRUE)

# Test individual clusters across replicates
cluster_results <- individual_svg(spe.combined, 
                                  edgeR_y = multi_results$estimated_y, 
                                  replicates = TRUE, 
                                  cluster_col = "layer_guess_reordered")

# Combine results
merge_res <- top_results(multi_results$gene_results, cluster_results, select = "FDR")
```
*Inputs are a combined multi-sample SpatialExperiment object; outputs are joint gene-level and cluster-level spatially variable gene statistics across replicates.*

## When to Use
- Identifying spatially variable genes (SVGs) from spatial transcriptomics data using `svg_test`.
- Testing spatial variability within individual spatial clusters using `individual_svg`.
- Jointly modeling multiple biological replicates to find consistent spatial patterns using `replicates = TRUE` in `svg_test`.
- Combining gene-level and cluster-level results to filter for highly or lowly abundant SVGs using `top_results`.

## When NOT to Use
- For spatial clustering itself, use `BayesSpace` or `stLearn` because `DESpace` requires pre-annotated spatial clusters as input.
- For single-cell RNA-seq differential expression without spatial coordinates, use standard `edgeR` or `DESeq2` because `DESpace` is designed for spatially resolved transcriptomics.

## Data Requirements
- **Input Format**: A `SpatialExperiment` or `SingleCellExperiment` object.
- **Structure**: Must contain spatial coordinates (e.g., `array_row`, `array_col`) and pre-annotated spatial clusters (e.g., `layer_guess_reordered`) in `colData`.
- **Normalization**: Raw count matrix in the `counts` assay (modeled via negative binomial in `edgeR`).

## Key Parameters
- **spe**: The input `SpatialExperiment` or `SingleCellExperiment` object.
- **cluster_col**: Column name in `colData(spe)` containing spatial clusters.
- **sample_col**: Column name in `colData(spe)` containing sample IDs (for multi-sample).
- **replicates** (`FALSE`): Logical indicating whether to fit the multi-sample model.
- **edgeR_y**: Pre-computed `DGEList` object containing dispersion estimates to speed up `individual_svg`.
- **verbose** (`TRUE`): Logical to print progress and statistics.
- **high_low** (`"both"`): Filter in `top_results` to select `"high"`, `"low"`, or `"both"` abundant genes.

## Best Practices
- Perform quality control filtering to remove low-quality spots (e.g., low library size, high mitochondrial ratio) and lowly abundant genes (e.g., detected in < 20 spots) before testing.
- Use pre-computed gene-level dispersion estimates (`estimated_y`) in `individual_svg` to significantly speed up computation.
- Ensure cluster labels are consistent across multiple samples when performing multi-sample joint testing.
- Visualize the spatial expression of top SVGs using `FeaturePlot` with cluster outlines.

## Common Pitfalls
- **Inconsistent cluster labels across samples**: Ensure that cluster names refer to the same spatial region across all samples before running multi-sample joint testing.
- **Slow computation in individual cluster tests**: Pass the `estimated_y` from `svg_test` to the `edgeR_y` parameter in `individual_svg` to avoid re-estimating dispersions.
- **Including low-quality spots**: Apply spot-level QC (e.g., using `scuttle::addPerCellQC`) and filter out genes with low counts before running `svg_test`.

## Alternatives
- `edgeR` for non-spatial differential expression analysis.
- `BayesSpace` for subspot-resolution spatial clustering.
- `SpatialLIBD` for interactive visualization and exploration of DLPFC spatial data.

## Citations
- Robinson, M. D., McCarthy, D. J., & Smyth, G. K. (2010). edgeR: a Bioconductor package for differential expression analysis of digital gene expression data. Bioinformatics, 26(1), 139-140.
- Maynard, K. R. et al. (2021). Transcriptome-scale spatial gene expression in the human dorsolateral prefrontal cortex. Nature Neuroscience, 24(3), 425-436.

## References
- Homepage: bioconductor.org/packages/DESpace
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/DESpace/inst/doc/DESpace.html
