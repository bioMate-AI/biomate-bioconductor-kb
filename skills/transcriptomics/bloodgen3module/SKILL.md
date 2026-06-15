---
name: bioconductor-bloodgen3module
description: The BloodGen3Module package provides functions for R user performing module repertoire analyses and generating fingerprint representations. Functions can perform group comparison or individual sample analysis and visualization by fingerprint grid plot or fingerprint heatmap. Module repertoire analyses typically involve determining the percentage of the constitutive genes for each module that are significantly increased or decreased. As we describe in details;https://www.biorxiv.org/content/10.11
when_to_use: Use when: BloodGen3Module: Modular Repertoire Analysis and Visualization. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# BloodGen3Module

## Workflows

### Standard Workflow

```r
library(BloodGen3Module)
library(ExperimentHub)
library(SummarizedExperiment)

# 1. Load expression data from ExperimentHub
dat <- ExperimentHub()
res <- query(dat, "GSE13015")
GSE13015 <- res[["EH5429"]]

# 2. Perform group comparison analysis using t-test
Group_df <- Groupcomparison(
  GSE13015,
  sample_info = NULL,
  FC = 1.5,
  pval = 0.1,
  FDR = TRUE,
  Group_column = "Group_test",
  Test_group = "Sepsis",
  Ref_group = "Control",
  SummarizedExperiment = TRUE
)

# 3. Perform group comparison analysis using limma
Group_limma <- Groupcomparisonlimma(
  GSE13015,
  sample_info = NULL,
  FC = 1.5,
  pval = 0.1,
  FDR = TRUE,
  Group_column = "Group_test",
  Test_group = "Sepsis",
  Ref_group = "Control",
  SummarizedExperiment = TRUE
)

# 4. Generate fingerprint grid plot
gridplot(
  Group_df,
  cutoff = 15,
  Ref_group = "Control",
  filename = tempfile()
)

# 5. Perform individual single sample analysis
Individual_df <- Individualcomparison(
  GSE13015,
  sample_info = NULL,
  FC = 1.5,
  DIFF = 10,
  Group_column = "Group_test",
  Ref_group = "Control",
  SummarizedExperiment = TRUE
)

# 6. Generate individual fingerprint heatmap
fingerprintplot(
  Individual_df,
  sample_info = NULL,
  cutoff = 15,
  rowSplit = TRUE,
  Group_column = "Group_test",
  show_ref_group = FALSE,
  Ref_group = "Control",
  Aggregate = "A28",
  filename = tempfile(),
  height = NULL,
  width = NULL
)
```
**Input/Output Note:** Inputs a `SummarizedExperiment` or expression matrix with sample annotations; outputs data frames of module-level percentages and generates PDF visualizations of fingerprint grids and heatmaps.

## When to Use
- To perform blood transcriptional module repertoire analysis on gene expression data.
- To determine the percentage of constitutive genes for each module that are significantly increased or decreased between groups using `Groupcomparison()` or `Groupcomparisonlimma()`.
- To perform individual sample-level modular analysis in reference to a control group using `Individualcomparison()`.
- To visualize group comparison results as a fingerprint grid using `gridplot()` or individual comparisons as a fingerprint heatmap using `fingerprintplot()`.

## When NOT to Use
- For general-purpose differential gene expression analysis without modular grouping (use `limma` or `DESeq2` directly).
- For single-cell RNA-seq data requiring cell-type specific clustering and marker identification (use `Seurat` or `scran` instead).

## Data Requirements
- A normalized, non-log2-transformed expression data matrix or a `SummarizedExperiment` object (log2 transformation is performed automatically).
- A sample annotation table (if not using a `SummarizedExperiment` with built-in colData) where the row names match the column names of the expression matrix.

## Key Parameters
- **FC** (1.5): Fold change threshold for determining significant changes in gene expression.
- **pval** (0.1): P-value threshold for statistical significance.
- **FDR** (TRUE): Logical indicating whether to apply False Discovery Rate correction.
- **Group_column** ("Group_test"): Column name in sample metadata containing the group classifications.
- **Test_group** ("Sepsis"): Name of the group to be tested.
- **Ref_group** ("Control"): Name of the reference group.
- **SummarizedExperiment** (TRUE): Logical indicating if the input is a `SummarizedExperiment` object.
- **cutoff** (15): Percentage threshold for module visualization in grid and fingerprint plots.

## Best Practices
- Ensure the input expression matrix is **not** log2-transformed, as the package functions perform log2 transformation internally.
- Verify that the row names of the sample information table (`sample_info`) match the column names of the expression matrix exactly.
- Use `Groupcomparisonlimma()` instead of `Groupcomparison()` when dealing with complex experimental designs or when limma's empirical Bayes moderation is preferred.

## Common Pitfalls
- *Pitfall*: Inputting pre-log-transformed data, leading to incorrect fold change calculations. *Fix*: Provide raw or normalized linear-scale counts/intensities.
- *Pitfall*: Mismatched sample names between expression matrix columns and annotation row names. *Fix*: Align the names using `colnames(data) <- rownames(sample_info)` before running the analysis.

## Alternatives
- `tmod` for general gene set enrichment and module visualization.
- `GSVA` for gene set variation analysis.
- `clusterProfiler` for standard GO/KEGG functional enrichment.

## Citations
- Rinchai D, et al. (2021). "BloodGen3Module: blood transcriptional module repertoire analysis and visualization using R." *Bioinformatics*. doi:10.1093/bioinformatics/btab121.

## References
- Homepage: https://bioconductor.org/packages/bloodgen3module
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/bloodgen3module/inst/doc/BloodGen3Module.html
