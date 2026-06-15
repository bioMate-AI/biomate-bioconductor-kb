---
name: bioconductor-omicsviewer
description: omicsViewer visualizes ExpressionSet (or SummarizedExperiment) in an interactive way. The omicsViewer has a separate back- and front-end. In the back-end, users need to prepare an ExpressionSet that contains all the necessary information for the downstream data interpretation. Some extra requirements on the headers of phenotype data or feature data are imposed so that the provided information can be clearly recognized by the front-end, at the same time, keep a minimum modification on the existin
when_to_use: Use when: quickStart.html; Differential expression analysis (omicsViewer). Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# omicsViewer

## Workflows

### Standard Workflow

```r
library(omicsViewer)
library(Biobase)

packdir <- system.file("extdata", package = "omicsViewer")
expr <- read.delim(file.path(packdir, "expressionMatrix.tsv"), stringsAsFactors = FALSE)
colnames(expr) <- make.names(colnames(expr))
rownames(expr) <- make.names(rownames(expr))

fd <- read.delim(file.path(packdir, "featureGeneral.tsv"), stringsAsFactors = FALSE)
pd <- read.delim(file.path(packdir, "sampleGeneral.tsv"), stringsAsFactors = FALSE)

# Prepare the ExpressionSet object
d <- prepOmicsViewer(
  expr = expr, pData = pd, fData = fd, 
  PCA = TRUE, pca.fillNA = TRUE,
  SummarizedExperiment = FALSE
)

# Run correlation analysis and extend metadata
expr_mat <- exprs(d)
drugData <- read.delim(file.path(packdir, "sampleDrug.tsv"))
drugcor <- correlationAnalysis(expr_mat, pheno = drugData[, 1:2])
d <- extendMetaData(d, drugcor, where = "fData")
```
*Input:* Expression matrix, feature data, and phenotype data.  
*Output:* An `ExpressionSet` object prepared and extended for interactive visualization in `omicsViewer`.

## When to Use
- Interactive exploration of high-throughput omics data stored in `ExpressionSet` or `SummarizedExperiment` objects.
- Performing on-the-fly enrichment analysis (using `fgsea` or Fisher's exact test) or STRING network analysis on selected features.
- Testing associations between selected samples and phenotype variables using `correlationAnalysis` or hypothesis tests (t-test, Mann-Whitney U test, chi-square, or log-rank test).

## When NOT to Use
- For high-throughput sequence alignment or raw read counting; use packages like `Rsubread` instead.
- For complex multi-factor differential expression modeling without interactive visualization; use `limma`, `edgeR`, or `DESeq2` directly.

## Data Requirements
- An expression matrix with unique row names (features) and column names (samples).
- Feature data (`fData`) and phenotype data (`pData`) where row names match the expression matrix's row and column names, respectively.
- Column headers in feature and phenotype data formatted as `Analysis|Subset|Variable` (e.g., `ttest|RE_vs_ME|mean.diff`).

## Key Parameters
- **expr**: Expression matrix with unique row and column names.
- **pData**: Phenotype data frame matching columns of the expression matrix.
- **fData**: Feature data frame matching rows of the expression matrix.
- **PCA** (`TRUE`): Logical indicating whether to perform principal component analysis.
- **pca.fillNA** (`TRUE`): Logical indicating whether to impute missing values for PCA.
- **t.test**: Matrix defining t-tests to perform.
- **ttest.fillNA** (`FALSE`): Logical indicating whether to impute missing values for t-tests.
- **SummarizedExperiment** (`FALSE`): Logical indicating whether to return a SummarizedExperiment instead of an ExpressionSet.

## Best Practices
- Pre-calculate dendrograms for rows and columns using `hclust` and `as.dendrogram` and store them as attributes (`rowDendrogram`/`colDendrogram`) of the expression matrix to speed up heatmap rendering.
- Use reserved keywords like `Surv`, `StringDB`, and `GS` in headers to enable specific downstream tabs (Survival, STRING, ORA/fGSEA) in the analyst panel.
- Extend metadata post-creation using `extendMetaData` to integrate additional statistical results like correlation analyses.

## Common Pitfalls
- **Slow heatmap rendering**: Calculating dendrograms on the fly for large matrices is slow. Fix: Pre-calculate dendrograms and assign them to the `rowDendrogram` attribute of the expression matrix.
- **Incompatible headers**: Front-end fails to recognize analysis columns. Fix: Ensure column names follow the strict `Analysis|Subset|Variable` format.
- **Non-matching identifiers**: Feature or sample names do not align between matrices. Fix: Ensure row names of `fData` match row names of `expr`, and row names of `pData` match column names of `expr`.

## Alternatives
- **limma**: For non-interactive, complex linear modeling of microarray and RNA-seq data.
- **DESeq2**: For differential expression analysis of RNA-seq count data.
- **edgeR**: For differential expression analysis of digital gene expression data.

## Citations
- Meng Chen (2026). Interactive and explorative visualization of ExpressionSet using omicsViewer.

## References
- Homepage: https://bioconductor.org/packages/omicsViewer
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/omicsViewer/inst/doc/quickStart.html
