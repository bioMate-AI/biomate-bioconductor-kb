---
name: bioconductor-awst
description: We propose an Asymmetric Within-Sample Transformation (AWST) to regularize RNA-seq read counts and reduce the effect of noise on the classification of samples. AWST comprises two main steps: standardization and smoothing. These steps transform gene expression data to reduce the noise of the lowly expressed features, which suffer from background effects and low signal-to-noise ratio, and the influence of the highly expressed features, which may be the result of amplification bias and other experi
when_to_use: Use when: We propose an Asymmetric Within-Sample Transformation (AWST) to regularize RNA-seq read counts and reduce the effect of; "install" using install, valid; filtering using rowMeans, table; raw awst using awst, plot; genefilter using gene_filter; pca using prcomp, ggplot. Not for: awst requires R/Bioconductor; see installation guide
user-invocable: false
---

# awst

## Workflows

### Standard Workflow

```r
library(awst)
library(SummarizedExperiment)
library(EDASeq)

# Load data (e.g., SummarizedExperiment)
data(airway, package = "airway")

# Filter lowly expressed genes
filter <- rowMeans(assay(airway)) >= 10
se <- airway[filter,]

# Apply Asymmetric Within-Sample Transformation
se <- awst(se)

# Filter uninformative genes using entropy
filtered <- gene_filter(se)

# Optional: Apply AWST after full-quantile normalization
assay(se, "fq") <- betweenLaneNormalization(assay(se), which = "full")
se_normalized <- awst(se, expr_values = "fq")
```
**Input/Output Note:** Inputs a `SummarizedExperiment` containing raw RNA-seq counts; outputs a `SummarizedExperiment` with transformed values in the `"awst"` assay and optionally filtered features.

## When to Use
- To regularize RNA-seq read counts and reduce the effect of noise on sample clustering or classification, especially for highly degraded or low input material samples like tumors or single cells.
- To perform per-sample standardization and asymmetric winsorization using `awst()` to reduce the influence of highly expressed features and noise of lowly expressed features.
- To filter out uninformative genes that contribute only noise to sample distances using the entropy-based `gene_filter()` function.

## When NOT to Use
- For differential expression analysis where raw or specifically modeled counts are required (use `DESeq2` or `edgeR` instead).
- For multi-sample batch effect correction across highly heterogeneous batches without prior normalization (use `sva::ComBat` or `removeBatchEffect` from `limma` instead).

## Data Requirements
- Input must be a `SummarizedExperiment` object (or a matrix of counts).
- Contains raw or normalized RNA-seq read counts (e.g., from `airway` dataset).
- Lowly expressed genes should be pre-filtered (e.g., keeping genes with `rowMeans(assay(se)) >= 10`).

## Key Parameters
- **expr_values** ("counts"): Character string specifying which assay of the input `SummarizedExperiment` to use for the transformation (e.g., `"fq"` after running `betweenLaneNormalization`).

## Best Practices
- Pre-filter non-expressed or lowly expressed genes (e.g., average count < 10) before applying AWST to reduce computational load and noise.
- Apply a prior normalization step, such as full-quantile normalization via `betweenLaneNormalization()`, which allows `awst()` to estimate parameters only once for all samples.
- Use `gene_filter()` after `awst()` to remove uninformative genes and improve sample separation in downstream analyses like PCA (`prcomp()`).

## Common Pitfalls
- *Pitfall*: Running `awst()` on log-transformed data. *Fix*: Ensure the input assay contains non-log-transformed counts, as `awst()` internally exploits the log-normal probability distribution.
- *Pitfall*: Retaining too many uninformative genes which dilutes the biological signal in PCA. *Fix*: Run `gene_filter()` on the transformed object to retain only genes contributing to sample distance.

## Alternatives
- `DESeq2` for variance stabilizing transformation (VST) or rlog.
- `edgeR` for calculating CPM/RPKM or TMM normalization.
- `scater` / `scran` for single-cell specific normalization and pooling.

## Citations
- Risso D, Pagnotta SM (2021). "Per-sample standardization and asymmetric winsorization lead to accurate clustering of RNA-seq expression profiles." *Bioinformatics*. doi:10.1093/bioinformatics/btab091.

## References
- Homepage: https://bioconductor.org/packages/awst
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/awst/inst/doc/awst_intro.html
