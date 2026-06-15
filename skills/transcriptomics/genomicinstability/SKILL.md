---
name: bioconductor-genomicinstability
description: This package contain functions to run genomic instability analysis (GIA) from scRNA-Seq data. GIA estimates the association between gene expression and genomic location of the coding genes. It uses the aREA algorithm to quantify the enrichment of sets of contiguous genes (loci-blocks) on the gene expression profiles and estimates the Genomic Instability Score (GIS) for each analyzed cell.
when_to_use: Use when: Using genomicInstability; Single-cell RNA-seq analysis (genomicInstability). Not for: Requires R ≥ 4.1.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# genomicInstability

## Workflows

### Standard Workflow

Estimate genomic instability scores and neoplastic likelihood for single cells without a prior normal reference.

```r
library(genomicInstability)

# 1. Estimate association between gene expression and loci-blocks
cnv <- inferCNV(tpm_matrix)

# 2. Estimate the relative likelihood of cells being neoplastic
cnv <- genomicInstabilityScore(cnv)
cnv <- giLikelihood(cnv)

# 3. Plot the GIS density and fitted Gaussian models
giDensityPlot(cnv)

# 4. Refine likelihood estimation by manually specifying normal and tumor components
cnv <- giLikelihood(cnv, recompute=FALSE, normal=1, tumor=2:3)
```
*Input: A normalized single-cell gene expression matrix (TPM); Output: An updated `inferCNV` object containing genomic instability scores (GIS) and relative likelihoods.*

### Reference Based Gia

Refine genomic instability analysis by using a subset of cells identified as normal (or an external normal dataset) as a reference null model.

```r
library(genomicInstability)

# 1. Read User Inputs and define normal reference matrix
null_cells <- tpm_matrix[, cnv$gi_likelihood < 0.25, drop=FALSE]

# 2. Run inferCNV using the normal reference matrix
cnv_norm <- inferCNV(tpm_matrix, nullmat=null_cells)

# 3. Calculate GIS and estimate likelihood simultaneously
cnv_norm <- genomicInstabilityScore(cnv_norm, likelihood=TRUE)

# 4. Visualize the GIS density, fitted models, and null model
giDensityPlot(cnv_norm)

# 5. Plot the loci-block enrichment heatmap
plot(cnv_norm, output="heatmap.png", resolution=120, gamma=2)
```
*Input: A normalized single-cell gene expression matrix and a designated reference matrix of normal cells; Output: A refined `inferCNV` object and a saved enrichment heatmap image.*

## When to Use
- To estimate genomic instability scores (GIS) for individual cells from single-cell RNA-seq data using `genomicInstabilityScore()`.
- To identify putative neoplastic cells in a heterogeneous sample without requiring a prior normal reference using `giLikelihood()`.
- To perform reference-based genomic instability analysis by specifying a normal cell matrix via the `nullmat` parameter in `inferCNV()`.

## When NOT to Use
- For DNA-based copy number variation detection, use packages like `copynumber` because `genomicInstability` infers genomic instability from transcriptional profiles.
- For bulk RNA-seq sample classification where single-cell resolution is not required, use standard gene set enrichment packages like `GSVA` because GIA is optimized for single-cell resolution.

## Data Requirements
- **Input Format**: A standard R `matrix` of gene expression values (e.g., Transcripts-per-million, TPM) or a `SingleCellExperiment` object.
- **Structure**: Genes (using EntrezIDs or symbols) as rows and individual cells as columns.
- **Normalization State**: Fully normalized expression values (e.g., TPM) are required as input to `inferCNV()`.

## Key Parameters
- **nullmat** (NULL): A matrix of gene expression for normal (non-neoplastic) reference samples passed to `inferCNV()`.
- **species** ("human"): Species to be analyzed (currently "human" and "mouse" are implemented) in `inferCNV()`.
- **k** (100): Number of genes for each loci-block in `inferCNV()`.
- **skip** (25): Displacement, in number of genes, between loci-blocks in `inferCNV()`.
- **likelihood** (FALSE): Logical indicating whether to compute genomic instability likelihood simultaneously in `genomicInstabilityScore()`.
- **recompute** (TRUE): Logical indicating whether to recompute the mixture model parameters in `giLikelihood()`.
- **normal** (1): Integer specifying which fitted Gaussian component(s) represent normal cells in `giLikelihood()`.
- **tumor** (2:3): Integer vector specifying which fitted Gaussian component(s) represent tumor cells in `giLikelihood()`.

## Best Practices
- Set a random seed using `set.seed()` before running downstream analyses to ensure reproducibility of the mixture model fitting.
- Inspect the raw GIS density distribution using `plot(density(cnv$gis))` to verify if it exhibits a multi-modal distribution before fitting Gaussian models.
- Visualize the fitted Gaussian models using `giDensityPlot()` to confirm that the assigned normal and tumor components align with the observed peaks.
- Use cells with low genomic instability likelihood (e.g., `gi_likelihood < 0.25`) as a reference null model (`nullmat`) in a second iteration of `inferCNV()` to refine the analysis.

## Common Pitfalls
- **Incorrect Gaussian component assignment**: Fix by manually specifying the `normal` and `tumor` component indices in `giLikelihood()`.
- **Using raw unnormalized count data**: Fix by converting raw counts to TPM or another normalized format before running `inferCNV()`.
- **Mismatched gene identifiers**: Fix by ensuring the input matrix uses EntrezIDs or compatible symbols that match the genomic location database for the specified `species`.

## Alternatives
- `infercnv` (Bioconductor) for detailed copy number variation profiling from single-cell RNA-seq using physical genomic position maps.
- `Seurat` for general single-cell clustering and marker-based cell type annotation.
- `scran` for single-cell variance modeling and normalization.

## Citations
- Puram et al. 2017, Cell (for the HNSC dataset reference).
- Alvarez et al. 2016, Nature Genetics (for the aREA algorithm reference).

## References
- Homepage: bioconductor.org/packages/genomicInstability
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/genomicInstability/inst/doc/genomicInstability.html
