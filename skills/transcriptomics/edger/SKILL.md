---
name: bioconductor-edger
description: Estimates differential gene expression for short read sequence count using methods appropriate for count data. If you have paired data you may also want to consider Tophat/Cufflinks. Input must be raw count data for each sequence arranged i
when_to_use: Use when: Bulk RNA-seq differential expression; ChIP-seq read count differential binding; ATAC-seq differential accessibility; Multi-group comparisons with contrasts; Complex experimental designs (factorial, nested, batch)
user-invocable: false
---

# edgeR — Comprehensive Skill Guide

> **Domain:** RNA-seq / ChIP-seq / ATAC-seq
> **Bioconductor:** [edgeR](https://bioconductor.org/packages/release/bioc/html/edgeR.html)
> **Paper:** Robinson MD, McCarthy DJ, Smyth GK (2010). Bioinformatics, 26:139-140.

Empirical analysis of digital gene expression data. Handles small sample sizes well; supports a wide range of experimental designs via generalized linear models.

## When to Use

- Bulk RNA-seq differential expression
- ChIP-seq read count differential binding
- ATAC-seq differential accessibility
- Multi-group comparisons with contrasts
- Complex experimental designs (factorial, nested, batch)

**Alternatives:** `DESeq2`, `limma-voom`, `NOISeq`

## Do NOT Use When

- Pre-normalized data (TPM, FPKM, RPKM) — requires raw counts.
- Continuous phenotype association — use linear regression or limma.
- Single-cell RNA-seq — use Seurat, scran, or muscat for pseudobulk.
- Proteomics/metabolomics unless data genuinely follows negative binomial.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Replicates** | ≥2 per group; n=2 is supported but power is very low |
| **Input Format** | Raw integer count matrix (genes × samples) |
| **Must Not Use** | Normalized values; edgeR normalizes internally via TMM |
| **Coverage** | ≥5M aligned reads per sample typical for bulk RNA-seq |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("edgeR")
library(edgeR)
```

## Workflows

### Standard GLM Workflow (Quasi-Likelihood)
*Recommended for most RNA-seq experiments*

#### Setup DGEList

```r
library(edgeR)
d <- DGEList(counts=counts, group=group)
```

#### Filter and normalise

```r
keep <- filterByExpr(d)
d <- d[keep,]
d <- calcNormFactors(d)             # TMM normalisation
```

#### Design matrix and dispersion

```r
design <- model.matrix(~group)
d <- estimateDisp(d, design, robust=TRUE)
plotBCV(d)                          # check BCV estimates
```

#### Fit and test

```r
fit <- glmQLFit(d, design, robust=TRUE)
qlf <- glmQLFTest(fit, coef=2)     # test second coefficient (vs intercept)
plotQLDisp(fit)                     # check quasi-likelihood dispersion
top <- topTags(qlf, n=Inf)$table
sig <- top[top$FDR < 0.05,]
```

### Multi-group Contrasts
*Pairwise comparisons between multiple groups*

#### Build contrasts

```r
group <- factor(c("A","A","B","B","C","C"))
design <- model.matrix(~0+group)     # no intercept for cleaner contrasts
colnames(design) <- levels(group)
d <- estimateDisp(d, design)
fit <- glmQLFit(d, design)
contr <- makeContrasts(BvsA=B-A, CvsA=C-A, BvsC=B-C, levels=design)
res_BvsA <- glmQLFTest(fit, contrast=contr[,"BvsA"])
topTags(res_BvsA)
```

## Key Functions & Parameters

### `DGEList()`

Container for count data

| Parameter | Description |
|-----------|-------------|
| `counts` | matrix of raw counts (genes × samples) |
| `group` | factor of sample groups |
| `lib.size` | optional: library sizes (computed automatically if absent) |
| `norm.factors` | optional: normalisation factors |

### `filterByExpr()`

Automatic count filter — removes lowly expressed genes

| Parameter | Description |
|-----------|-------------|
| `y` | DGEList |
| `group` | factor (uses y$samples$group if absent) |
| `min.count` | minimum count per sample (default 10) |
| `min.total.count` | minimum total count (default 15) |

### `calcNormFactors()`

Compute TMM normalisation factors

| Parameter | Description |
|-----------|-------------|
| `object` | DGEList |
| `method` | 'TMM' (default) \| 'TMMwspll' \| 'RLE' \| 'upperquartile' \| 'none' |

### `estimateDisp()`

Estimate common and tagwise dispersions (BCV)

| Parameter | Description |
|-----------|-------------|
| `y` | DGEList |
| `design` | model matrix from model.matrix() |
| `robust` | logical; robust estimation (default FALSE) |
| `trend.method` | 'locfit' \| 'none' \| 'movingave' |

### `glmQLFit()`

Fit quasi-likelihood negative binomial GLM (preferred for small n)

| Parameter | Description |
|-----------|-------------|
| `y` | DGEList |
| `design` | model matrix |
| `robust` | logical; robustify prior df estimation |

### `glmQLFTest()`

Quasi-likelihood F-test for coefficient(s)

| Parameter | Description |
|-----------|-------------|
| `glmfit` | DGEGLM from glmQLFit |
| `coef` | column index/name of design matrix to test |
| `contrast` | contrast vector/matrix instead of coef |

### `topTags()`

Extract top DE genes from test result

| Parameter | Description |
|-----------|-------------|
| `object` | DGELRT or DGEExact |
| `n` | number of genes (default 10; use Inf for all) |
| `adjust.method` | 'BH' (default) \| 'BY' \| 'holm' \| 'none' |
| `sort.by` | 'PValue' \| 'logFC' \| 'none' |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Counts are negative binomial distributed.
- Dispersion is shared across genes with similar expression (empirical Bayes shrinkage).
- Most genes are NOT differentially expressed (used in TMM normalization).
- The quasi-likelihood F-test (QLF) accounts for additional gene-level variation not captured by NB.

## Result Interpretation

- `logFC`: log2 fold-change; positive = higher in first group of contrast.
- `PValue` / `FDR`: BH-adjusted FDR; standard cutoff FDR < 0.05.
- `logCPM`: average log2-CPM (counts per million) — low logCPM → low-count gene, LFC less reliable.
- `F` statistic (QLF): larger F = more evidence for DE; compare across genes, not absolute value.
- Use `plotBCV()` to inspect biological coefficient of variation — unusually high BCV indicates outlier samples.
- Use `plotSmear()` as an MA plot equivalent to check for systematic bias.

## Best Practices

- Use `filterByExpr()` for automatic gene filtering — it accounts for library size.
- TMM normalisation (`calcNormFactors`) is the default and works well for most datasets.
- Use `glmQLFit` + `glmQLFTest` for small sample sizes (n<10 per group).
- Use `glmFit` + `glmLRT` for large datasets — slightly more powerful but less robust.
- Always provide a design matrix (`model.matrix()`) for multi-factor experiments.
- For pairwise contrasts use `makeContrasts()` — do not subset samples post-hoc.
- Plot `plotBCV(d)` and `plotQLDisp(fit)` to check dispersion estimates.
- For ChIP-seq: use csaw windows instead of gene-level counts.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `DESeq2` | You need GLM quasi-likelihood tests; complex multifactor designs; very small n (n=2). | You prefer apeglm LFC shrinkage or want IHW for multiple testing. |
| `limma-voom` | You have large datasets or complex contrasts that benefit from linear model flexibility. | You prefer moderated t-statistics and eBayes; microarray or large n (≥5/group). |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Robinson MD, McCarthy DJ, Smyth GK (2010). Bioinformatics 26:139.** [PMID:19910308](https://pubmed.ncbi.nlm.nih.gov/19910308)  
  Original edgeR paper; empirical Bayes dispersion estimation outperforms Poisson models.

- **Law CW et al. (2014). Genome Biol 15:R29.** [PMID:24926665](https://pubmed.ncbi.nlm.nih.gov/24926665)  
  edgeR-QLF and limma-voom show best performance for RNA-seq DE across sample sizes.

## Common Errors & Troubleshooting

### `Error in estimateDisp: no residual df`

**Cause:** Saturated model — number of coefficients equals number of samples

**Fix:** Reduce model complexity or add replicates

### `dispersion values all negative`

**Cause:** Very few samples; BCV estimate is unstable

**Fix:** Use `estimateGLMCommonDisp` with `method='deviance'`

### From Community Q&A (Biostars)

- [Are unequal sample sizes in differential gene expression (DGE) analysis a problem for edgeR DESeq2 a](https://www.biostars.org/p/9605688/)
- [Contrasts for comparing condition within tissue](https://www.biostars.org/p/9605190/)
- [Seeking Advice on Using `edgeR` and `variancePartition` for RNA-seq Data with Multiple Tissues and P](https://www.biostars.org/p/9601556/)
- [DEG analysis of RNA-seq data across multiple tissues and two conditions](https://www.biostars.org/p/9592889/)
- [Error in edgeR/Deseq2   Analysis](https://www.biostars.org/p/9592725/)

## Additional Notes from Official Documentation

*Extracted from the edgeR Bioconductor vignette(s)*

### What is it?


edgeR is a package for differential analyses of read count data from sequencing technologies
such as RNA-seq, ChIP-seq, ATAC-seq, BS-seq and CUT&RUN.
It has particularly strong capabilities for expression analyses of RNA-seq data, including gene expression, transcript expression and tests for differential splicing.
edgeR implements novel statistical methods based on the negative binomial distribution
as a model for count variability, including empirical Bayes methods, exact tests, and generalized linear models.
The package is especially suitable for analysing designed experiments with multiple
experimental factors but possibly small numbers of replicates.
It has unique abilities to model transcript specific variation even in small samples,
a capability essential for prioritizing genes or 

### How to get help


The edgeR Userâs Guide is available by
or alternatively from the edgeR landing page .
Documentation for specific functions is available through the usual R help system, e.g., ?glmFit .
Further questions about the package should be directed to the Bioconductor support site .

```r
> library(edgeR)
> edgeRUsersGuide()
```

### Further reading


Chen Y, Chen L, Lun ATL, Baldoni PL, Smyth GK (2024). edgeR 4.0: powerful differential analysis of sequencing data with expanded functionality and improved support for small counts and larger datasets. bioRxiv doi: 10.1101/2024.01.21.576131 .
Chen, Y, Pal, B, Visvader, JE, Smyth, GK (2017). Differential methylation analysis of reduced representation bisulfite sequencing experiments using edgeR. F1000Research 6, 2055. doi:10.12688/f1000research.13196.2
Chen Y, Lun ATL, Smyth GK (2016). From reads to genes to pathways: differential expression analysis of RNA-Seq experiments using Rsubread and the edgeR quasi-likelihood pipeline. F1000Research 5, 1438. doi:10.12688/f1000research.8987.2
McCarthy, DJ, Chen, Y, Smyth, GK (2012). Differential expression analysis of multifactor RNA-Seq experiment

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/edgeR.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/vignettes/edgeR/inst/doc/edgeRUsersGuide.pdf
- **GitHub:** https://github.com/Bioconductor/edgeR
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Robinson MD, McCarthy DJ, Smyth GK (2010). Bioinformatics, 26:139-140.

---
