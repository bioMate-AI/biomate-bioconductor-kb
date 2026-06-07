---
name: bioconductor-limma
description: Given a matrix of counts (e.g. from featureCounts) and optional information about the genes, this tool performs differential expression (DE) using the limma Bioconductor package and produces plots and tables useful in DE analysis. Interacti
when_to_use: Use when: Microarray differential expression; RNA-seq (via voom transformation); Complex designs: factorial, time-course, blocking; Batch effect correction with duplicateCorrelation; Rotation test for gene set testing (ROAST/MROAST)
user-invocable: false
---

# limma — Comprehensive Skill Guide

> **Domain:** Microarray / RNA-seq
> **Bioconductor:** [limma](https://bioconductor.org/packages/release/bioc/html/limma.html)
> **Paper:** Ritchie ME et al. (2015). Nucleic Acids Research, 43:e47.

Linear models for microarray and RNA-seq data. Enables any experimental design expressible as a linear model; uses empirical Bayes shrinkage of standard errors.

## When to Use

- Microarray differential expression
- RNA-seq (via voom transformation)
- Complex designs: factorial, time-course, blocking
- Batch effect correction with duplicateCorrelation
- Rotation test for gene set testing (ROAST/MROAST)

**Alternatives:** `DESeq2`, `edgeR`

## Do NOT Use When

- Very small sample sizes (n<3 per group) where Bayesian shrinkage cannot be estimated — use edgeR instead.
- RNA-seq without `voom()` transformation — raw counts violate limma's Gaussian assumption.
- Non-linear effects or complex time-series without manual design matrix specification.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Replicates** | ≥3 per group for RNA-seq; works with n=2 but with reduced power |
| **Input Format** | For RNA-seq: raw counts + `voom()`; for microarray: log2 intensities (pre-normalized) |
| **Must Not Use** | Raw counts directly without voom() for RNA-seq |
| **Notes** | For microarray: normalize with `normalizeBetweenArrays()` before fitting |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("limma")
library(limma)
```

## Workflows

### RNA-seq with voom
*Standard limma-voom workflow for RNA-seq*

#### Setup

```r
library(limma); library(edgeR)
d <- DGEList(counts=counts)
keep <- filterByExpr(d, group=group)
d <- d[keep,]
d <- calcNormFactors(d)
design <- model.matrix(~group)
```

#### voom transform + fit

```r
v <- voom(d, design, plot=TRUE)   # visualise mean-variance trend
fit <- lmFit(v, design)
fit <- eBayes(fit, trend=TRUE)     # trend=TRUE for RNA-seq
topTable(fit, coef=2, n=20)        # top DE genes for coefficient 2
```

#### Multiple contrasts

```r
contr.matrix <- makeContrasts(AvsB=A-B, AvsC=A-C, BvsC=B-C, levels=design)
vfit <- contrasts.fit(fit, contr.matrix)
vfit <- eBayes(vfit, trend=TRUE)
results <- decideTests(vfit)       # summary across contrasts
summary(results)
```

### Microarray
*Agilent or Affymetrix expression arrays*

#### Load and normalise

```r
library(limma)
targets <- readTargets("targets.txt")
RG <- read.maimages(targets, source="agilent", green.only=TRUE)
RG <- backgroundCorrect(RG, method="normexp")
MA <- normalizeBetweenArrays(RG, method="quantile")
```

#### DE analysis

```r
design <- model.matrix(~0 + factor(targets$Treat))
colnames(design) <- c("Control","Treated")
fit <- lmFit(MA, design)
contrasts <- makeContrasts(Treated-Control, levels=design)
fit2 <- contrasts.fit(fit, contrasts)
fit2 <- eBayes(fit2)
topTable(fit2, adjust.method="BH")
```

## Key Functions & Parameters

### `voom()`

Transform RNA-seq counts to log-CPM with precision weights for limma

| Parameter | Description |
|-----------|-------------|
| `counts` | DGEList or count matrix |
| `design` | model matrix |
| `normalize.method` | 'none'\|'scale'\|'quantile'\|'cyclicloess' |
| `plot` | logical; plot mean-variance trend |

### `lmFit()`

Fit linear model to each gene

| Parameter | Description |
|-----------|-------------|
| `object` | EList (voom output) or expression matrix |
| `design` | model matrix from model.matrix() |
| `block` | vector of blocking variable (for duplicateCorrelation) |
| `correlation` | intra-block correlation from duplicateCorrelation() |

### `makeContrasts()`

Build contrast matrix for pairwise or complex comparisons

| Parameter | Description |
|-----------|-------------|
| `...` | named contrasts as expressions e.g. TreatvsCtrl=Treat-Control |
| `levels` | colnames of design matrix |

### `contrasts.fit()`

Re-parametrise MArrayLM for specified contrasts

| Parameter | Description |
|-----------|-------------|
| `fit` | MArrayLM from lmFit |
| `contrasts` | contrast matrix from makeContrasts |

### `eBayes()`

Empirical Bayes moderation of t-statistics

| Parameter | Description |
|-----------|-------------|
| `fit` | MArrayLM |
| `trend` | logical; model variance trend with intensity (RNA-seq: TRUE) |
| `robust` | logical; robust empirical Bayes |
| `proportion` | prior proportion of DE genes (default 0.01) |

### `topTable()`

Extract top DE genes

| Parameter | Description |
|-----------|-------------|
| `fit` | MArrayLM after eBayes |
| `coef` | coefficient name or index |
| `n` | genes to return (default 10; Inf for all) |
| `adjust.method` | 'BH' \| 'BY' \| 'holm' |
| `p.value` | p-value filter (default 1) |
| `lfc` | log2FC threshold filter (default 0) |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- After voom transformation, the data approximately follows a normal distribution.
- Precision weights from voom account for the mean-variance relationship in RNA-seq counts.
- Empirical Bayes shrinkage of variance toward a common value across genes (eBayes).
- The linear model correctly specifies the experimental design.

## Result Interpretation

- `logFC`: log2 fold-change (or contrast coefficient); same direction convention as edgeR.
- `adj.P.Val`: BH-FDR adjusted p-value; use < 0.05 as standard cutoff.
- `t`: moderated t-statistic (smaller SE than ordinary t because of eBayes shrinkage).
- `B` (log-odds): log-odds of DE; B > 0 means more likely DE than not (rarely used directly).
- `AveExpr`: average log2-expression across all samples; low value → less reliable estimates.
- Volcano: `plotMA(fit2)` or `volcanoplot(fit2)` for MA and volcano visualization.
- Use `treat()` instead of `eBayes()` to test against a minimum FC threshold.

## Best Practices

- For RNA-seq use `voom()` + `lmFit()` + `eBayes()` workflow.
- Set `trend=TRUE` in `eBayes()` for RNA-seq data (accommodates mean-variance trend).
- Use `duplicateCorrelation()` for paired samples or repeated measures.
- Use `removeBatchEffect()` only for visualisation — not as input for DE; put batch in design.
- For microarray, quantile-normalise with `normalizeBetweenArrays()` before lmFit.
- Use `fry()` or `camera()` for gene set testing — they account for inter-gene correlation.
- voomWithQualityWeights() improves power when sample quality varies.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `DESeq2` | You have microarray data or very large RNA-seq cohorts; you want linear model contrasts flexibility. | You have count data, small n, or want negative binomial modelling. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Ritchie ME et al. (2015). Nucleic Acids Res 43:e47.** [PMID:25605792](https://pubmed.ncbi.nlm.nih.gov/25605792)  
  limma-voom competitive with DESeq2/edgeR for RNA-seq; best for microarray and large n.

- **Law CW et al. (2014). Genome Biol 15:R29.** [PMID:24926665](https://pubmed.ncbi.nlm.nih.gov/24926665)  
  voom outperforms DESeq2/edgeR at large sample sizes (n≥20); performs comparably for small n.

## Common Errors & Troubleshooting

### `Coefficients not estimable from factor 'X'`

**Cause:** Aliased coefficients — model is not full rank

**Fix:** Use `nonEstimable(design)` to identify redundant columns; simplify design

### From Community Q&A (Biostars)

- [Contrasts for comparing condition within tissue](https://www.biostars.org/p/9605190/)
- [Deseq2  Limma - the paired test seems to be incorrect - is it known problem ?](https://www.biostars.org/p/9596357/)
- [limma eBayes error in analysis of Illumina HumanHT-12 V4.0 expression beadchip data](https://www.biostars.org/p/9588697/)

## Additional Notes from Official Documentation

*Extracted from the limma Bioconductor vignette(s)*

### What is it?


Limma is an R package for the analysis of gene expression data, especially the use of linear models for analysing designed experiments and the assessment of differential expression.
Limma provides the ability to analyse comparisons between many RNA targets simultaneously in arbitrary complicated designed experiments.
Empirical Bayesian methods are used to provide stable results even when the number of arrays is small.
The normalization and background correction functions are provided for microarrays and similar technologies.
The linear model and differential expression functions apply to a wide variety of gene expression technologies including microarrays (single-channel or two-color), quantitative PCR, RNA-seq or proteomics.

### How to get help


The edgeR Userâs Guide is available by
or alternatively from the limma landing page .
Documentation for specific functions is available through the usual R help system, e.g., ?lmFit .
Further questions about the package should be directed to the Bioconductor support site .

```r
> library(limma)
> limmaRUsersGuide()
```

### Further reading


Ritchie ME, Phipson B, Wu D, Hu Y, Law CW, Shi W, Smyth GK (2015). limma powers differential expression analyses for RNA-sequencing and microarray studies. Nucleic Acids Research 43, e47. doi:10.1093/nar/gkv007
Phipson B, Lee S, Majewski IJ, Alexander WS, and Smyth GK (2016). Robust hyperparameter estimation protects against hypervariable genes and improves power to detect differential expression. Annals of Applied Statistics 10, 946-963. doi:10.1214/16-AOAS920
Law CW, Chen Y, Shi W, Smyth GK (2014). Voom: precision weights unlock linear model analysis tools for RNA-seq read counts. Genome Biology 15, R29. doi:10.1186/gb-2014-15-2-r29 . See also the Preprint Version at https://gksmyth.github.io/pubs/VoomPreprint.pdf incorporating some notational corrections.
Law CW, Alhamdoosh M, Su S, Do

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/limma.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/vignettes/limma/inst/doc/usersguide.pdf
- **GitHub:** https://github.com/Bioconductor/limma
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Ritchie ME et al. (2015). Nucleic Acids Research, 43:e47.

---
