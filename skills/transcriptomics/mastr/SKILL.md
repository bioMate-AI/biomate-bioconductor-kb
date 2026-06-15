---
name: bioconductor-mastr
description: mastR is an R package designed for automated screening of signatures of interest for specific research questions. The package is developed for generating refined lists of signature genes from multiple group comparisons based on the results from edgeR and limma differential expression (DE) analysis workflow. It also takes into account the background noise of tissue-specificity, which is often ignored by other marker generation tools. This package is particularly useful for the identification of g
when_to_use: Use when: mastR_Demo with mastR; Differential expression analysis (mastR). Not for: Requires R ≥ 4.3.0
user-invocable: false
---

# mastR

## Workflows

### Standard Workflow

Generate and refine a group-specific gene signature from a single transcriptomics dataset, including background tissue expression removal and visualization.

```r
library(mastR)
library(limma)

# 1. Build markers pool
data("lm7", "lm22")
LM <- get_lm_sig(lm7.pattern = "^NK", lm22.pattern = "NK cells")

# 2. Process data with customized contrast matrix
data("im_data_6")
con_mat <- makeContrasts(
  'NK-CD4' = 'NK - CD4',
  'NK-T' = 'NK - (CD4 + CD8)/2',
  levels = levels(factor(make.names(im_data_6$`celltype:ch1`)))
)

proc_data <- process_data(
  im_data_6,
  group_col = 'celltype:ch1',
  target_group = 'NK',
  contrast_mat = con_mat,
  summary = TRUE,
  gene_id = "ENSEMBL"
)

# 3. Visualize mean-variance relationship
plot_mean_var(proc_data)
```
*Input: ExpressionSet object (e.g., im_data_6) and cell type metadata. Output: Processed list containing DGEList, design, and contrast-specific differential expression results.*

### Multi Dataset Signature Aggregation

Identify and aggregate robust gene signatures across multiple independent transcriptomics datasets using union, intersection, or Robust Rank Aggregation (RRA).

```r
library(mastR)
library(limma)
data("im_data_6")

con_mat <- makeContrasts(
  'NK-CD4' = 'NK - CD4',
  levels = levels(factor(make.names(im_data_6$`celltype:ch1`)))
)

# Retrieve DE tables for downstream aggregation
DE_table <- get_de_table(
  im_data_6,
  group_col = 'celltype:ch1',
  target_group = 'NK',
  contrast_mat = con_mat,
  summary = TRUE,
  gene_id = "ENSEMBL"
)
```
*Input: ExpressionSet data and contrast matrix. Output: List of differential expression tables for each contrast.*

### Single Cell Pseudo Bulk Signature

Convert single-cell RNA-sequencing data into pseudo-bulk samples and identify group-specific marker signatures.

```r
library(mastR)
# Assuming pseudo-bulk ExpressionSet 'pb_eset' is prepared
# process_data internally handles DGEList conversion and limma/edgeR fitting
proc_data <- process_data(
  im_data_6, 
  group_col = 'celltype:ch1',
  target_group = 'NK',
  summary = TRUE,
  gene_id = "ENSEMBL"
)
```
*Input: Pseudo-bulk ExpressionSet. Output: Processed differential expression results for identifying cell-type signatures.*

## When to Use
- To perform simplified customized contrast design for differential expression analysis using `process_data()`.
- To build a markers pool from public databases like CIBERSORT (using `get_lm_sig()`) or MSigDB (using `get_gsc_sig()`), and merge them using `merge_markers()`.
- To visualize gene-set overlaps using UpSet plots with `gsc_plot()`.
- To extract all differential expression tables across multiple contrasts in a single call using `get_de_table()`.

## When NOT to Use
- For performing single-cell differential expression directly on individual cells without pseudo-bulking; use `Seurat::FindMarkers()` instead because `mastR` relies on robust pseudo-bulk statistical methods like `limma` and `edgeR`.
- For non-linear or complex random effects modeling; use `lme4` or `variancePartition` because `mastR` is built on standard linear modeling via `limma`.

## Data Requirements
- Expression data as an `ExpressionSet` object (e.g., `im_data_6`) containing normalized counts (e.g., TMM normalized counts) or raw counts.
- Phenotypic metadata with a grouping column (e.g., `celltype:ch1`) containing group/cell-type labels.
- Gene identifiers matching the expression matrix row names (e.g., "ENSEMBL" or "SYMBOL").

## Key Parameters
- **group_col** (required): Column name in metadata containing group labels.
- **target_group** (required): The specific group of interest (e.g., 'NK') for signature identification.
- **contrast_mat** (`NULL`): A customized contrast matrix created using `limma::makeContrasts()`.
- **summary** (`FALSE`): Logical indicating whether to print a summary of up/down-regulated genes.
- **gene_id** ("ENSEMBL"): Type of gene identifier used in the expression matrix.
- **lm7.pattern** (required in `get_lm_sig`): Regular expression to filter LM7 leukocyte signatures.
- **lm22.pattern** (required in `get_lm_sig`): Regular expression to filter LM22 leukocyte signatures.

## Best Practices
- Create the customized contrast matrix using levels derived from the design matrix of a dummy `process_data()` run to avoid level mismatch errors.
- Merge multiple retrieved marker sets into a single `GeneSet` using `merge_markers()` to simplify downstream intersection.
- Visualize the mean-variance relationship of the processed data using `plot_mean_var()` to check data quality.

## Common Pitfalls
- *Contrast matrix level mismatch*: If the levels in the contrast matrix do not match the expression matrix group levels, the analysis will fail. Fix by generating the contrast matrix using levels from `proc_data$vfit$design`.
- *Missing packages for visualization*: Interactive Glimma plots require `Glimma` to be installed. Fix by installing `Glimma` and calling `Glimma::glimmaMDS(proc_data)`.

## Alternatives
- `limma` for direct, low-level differential expression and contrast design.
- `edgeR` for differential expression of RNA-seq counts using negative binomial models.
- `singscore` for single-sample gene signature scoring.

## Citations
- Cursons et al. 2019 (for the Huntington gene list / NK markers)
- Tosolini et al. (for LM7 leukocyte signature)

## References
- Homepage: https://bioconductor.org/packages/mastr
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/mastr/inst/doc/mastR.html
