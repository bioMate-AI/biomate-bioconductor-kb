---
name: bioconductor-deseq2
description: Uses DESeq2 version 1.40.2 to estimate variance-mean dependence in count data from high-throughput sequencing assays and test for differential expression based on a model using the negative binomial distribution.
when_to_use: Use when: Two-group comparison (treatment vs control); Multi-factor design with blocking variables; Likelihood ratio test for complex designs; Time-series expression analysis; Allelic imbalance testing
user-invocable: false
---

# DESeq2 — Comprehensive Skill Guide

> **Domain:** RNA-seq
> **Bioconductor:** [DESeq2](https://bioconductor.org/packages/release/bioc/html/DESeq2.html)
> **Paper:** Love MI, Huber W, Anders S (2014). Genome Biology, 15:550.

Differential gene expression analysis based on the negative binomial distribution. The gold standard for bulk RNA-seq DE analysis.

## When to Use

- Two-group comparison (treatment vs control)
- Multi-factor design with blocking variables
- Likelihood ratio test for complex designs
- Time-series expression analysis
- Allelic imbalance testing

**Alternatives:** `edgeR`, `limma-voom`, `DEXSeq (exon-level)`

## Do NOT Use When

- Pre-normalised data (TPM, FPKM, RPKM) — use raw integer counts only.
- Single-cell RNA-seq without modifications (use DESeq2 with `sfType='poscounts'` or use scran/muscat instead).
- N=1 per condition (no replicates) — replicates are mathematically required.
- Continuous response variables — use limma/mixed models instead.
- Proteomics or metabolomics count matrices — distributional assumptions differ.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Replicates** | ≥2 biological replicates per group (≥3 strongly recommended for FDR control) |
| **Input Format** | Raw integer count matrix: genes × samples (not normalized values) |
| **Must Not Use** | TPM, FPKM, RPKM, or any library-size-normalized values as input |
| **Coverage** | ≥5–10M uniquely mapped reads per sample recommended; <1M is problematic |
| **Sparsity** | Works best with bulk RNA-seq; for highly sparse data (sc) use sfType='poscounts' |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("DESeq2")
library(DESeq2)
```

## Workflows

### Standard Two-Group Comparison
*Comparing treatment vs control with simple design*

#### Import counts

```r
# From count matrix
library(DESeq2)
counts <- read.csv("counts.csv", row.names=1)
coldata <- data.frame(condition=factor(c("ctrl","ctrl","trt","trt")),
                      row.names=colnames(counts))
dds <- DESeqDataSetFromMatrix(countData=counts, colData=coldata,
                               design=~condition)
```

#### From tximeta (salmon/alevin counts)

```r
library(tximeta)
se <- tximeta(coldata)          # coldata must have 'names' and 'files' columns
dds <- DESeqDataSet(se, design=~condition)
```

#### Pre-filter low-count genes

```r
keep <- rowSums(counts(dds) >= 10) >= 2   # ≥10 counts in ≥2 samples
dds <- dds[keep,]
```

#### Run DESeq2

```r
dds <- DESeq(dds)          # estimates: sizeFactors, dispersions, GLM, Wald test
resultsNames(dds)          # show available coefficients
```

#### Extract and shrink results

```r
res <- results(dds, contrast=c("condition","trt","ctrl"), alpha=0.05)
res_shrunk <- lfcShrink(dds, coef="condition_trt_vs_ctrl", type="apeglm")
summary(res_shrunk)
sig <- subset(res_shrunk, padj < 0.05 & abs(log2FoldChange) > 1)
```

#### Visualise

```r
plotMA(res_shrunk, ylim=c(-5,5))          # MA plot
plotDispEsts(dds)                          # dispersion estimates
vsd <- vst(dds, blind=FALSE)
plotPCA(vsd, intgroup="condition")         # PCA of samples
library(pheatmap)
pheatmap(assay(vsd)[head(order(res$padj),50),])  # top 50 gene heatmap
```

### Multi-factor Design (Batch Correction)
*Account for batch/sex/patient while testing condition*

#### Design with nuisance variable

```r
dds <- DESeqDataSetFromMatrix(countData=counts, colData=coldata,
                               design=~batch + condition)
dds <- DESeq(dds)
res <- results(dds, name="condition_treated_vs_untreated")
```

#### Visualise after removing batch for plots only

```r
vsd <- vst(dds, blind=FALSE)
# Remove batch effect for visualisation ONLY (never use this as input to DE)
assay(vsd) <- limma::removeBatchEffect(assay(vsd), vsd$batch)
plotPCA(vsd, intgroup="condition")
```

### Likelihood Ratio Test (LRT) for Complex Designs
*Time-series, interaction terms, or any multi-level comparison*

#### LRT comparing full vs reduced model

```r
dds <- DESeqDataSetFromMatrix(counts, coldata, design=~condition+time+condition:time)
dds <- DESeq(dds, test="LRT", reduced=~condition+time)
# Genes significant by LRT show any condition:time interaction
res_lrt <- results(dds)
sig_interaction <- subset(res_lrt, padj < 0.05)
```

## Key Functions & Parameters

### `DESeqDataSetFromMatrix()`

Create DESeqDataSet from count matrix + colData

| Parameter | Description |
|-----------|-------------|
| `countData` | integer matrix of raw counts (genes × samples) |
| `colData` | DataFrame of sample metadata |
| `design` | R formula specifying model (e.g. ~ condition, ~ batch + condition) |

### `DESeq()`

Main wrapper: estimate size factors, dispersions, fit GLM, run Wald/LRT tests

| Parameter | Description |
|-----------|-------------|
| `object` | DESeqDataSet |
| `test` | 'Wald' (default) or 'LRT'; use LRT for multi-factor / time-series |
| `fitType` | 'parametric' (default) \| 'local' \| 'mean' \| 'glmGamPoi' |
| `sfType` | 'ratio' (default) \| 'poscounts' \| 'iterate' |
| `parallel` | logical; use BiocParallel for large datasets |

### `results()`

Extract results table with log2FC, p-value, padj

| Parameter | Description |
|-----------|-------------|
| `object` | DESeqDataSet |
| `contrast` | vector c('factor','numerator','denominator') or numeric for LRT |
| `alpha` | significance threshold for independent filtering (default 0.1) |
| `lfcThreshold` | test against this minimum \|log2FC\| (default 0); use with altHypothesis |
| `altHypothesis` | 'greaterAbs'\|'lessAbs'\|'greater'\|'less' |
| `independentFiltering` | logical; filter low-mean genes (default TRUE) |
| `cooksCutoff` | flag outliers above Cook's distance threshold |

### `lfcShrink()`

Shrink log2 fold-change estimates (STRONGLY RECOMMENDED for ranking/visualisation)

| Parameter | Description |
|-----------|-------------|
| `dds` | DESeqDataSet after DESeq() |
| `coef` | coefficient name or index (use resultsNames(dds) to see options) |
| `type` | 'apeglm' (default, best) \| 'ashr' \| 'normal' |
| `res` | optional: supply existing results() object |

### `vst()`

Variance Stabilising Transformation for visualisation/clustering (fast)

| Parameter | Description |
|-----------|-------------|
| `object` | DESeqDataSet |
| `blind` | TRUE (unsupervised, default) or FALSE (use design) |
| `nsub` | number of genes used to estimate dispersion (default 1000) |

### `rlog()`

Regularised log2 transformation; better for small n, slower than vst

| Parameter | Description |
|-----------|-------------|
| `object` | DESeqDataSet |
| `blind` | TRUE (default) or FALSE |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Counts follow a negative binomial (NB) distribution.
- The dispersion parameter (φ) is estimated from data and shrunk toward a common trend.
- Genes are not differentially expressed between most samples (used to estimate size factors).
- Library sizes (or size factors) capture the main technical variation.
- Within-group expression is approximately exchangeable (biological replication).

## Result Interpretation

- `log2FoldChange` (raw): can be noisy for low-count genes — always report the SHRUNKEN LFC from `lfcShrink()`.
- `padj` (BH-adjusted p-value): 0.05 → 5% expected false discoveries among all genes you call significant.
- `pvalue` (raw): report `padj` in papers, not raw p-value.
- `baseMean`: average normalized count across ALL samples; low baseMean (< 5) → high uncertainty, treat cautiously.
- `NA` in `padj`: gene was filtered by independent filtering (too low count) or Cook's outlier — not a bug.
- Volcano plot: plot `log2FoldChange` (shrunken) vs `-log10(padj)`. Use `padj<0.05 & |LFC|>1` as typical cutoff.
- MA plot (`plotMA`): expected to show points symmetrically around 0; systematic bias indicates normalization issue.

## Best Practices

- Always use raw counts, never pre-normalised values (RPKM/TPM).
- Pre-filter genes with very low counts: `keep <- rowSums(counts(dds) >= 10) >= 3`
- Use `lfcShrink(type='apeglm')` for final LFC estimates and volcano/MA plots.
- For designs with a nuisance variable (batch), put it in `design` as `~ batch + condition`.
- Use `test='LRT'` when comparing a complex model vs reduced model (time-series, interaction).
- Check size factors: very large or small values (>5 or <0.2) indicate composition bias.
- Check Cook's distance outlier genes; set `cooksCutoff=FALSE` to disable flagging.
- For single-cell / very sparse data consider `sfType='poscounts'`.
- Use `plotDispEsts(dds)` to verify dispersion estimates before trusting results.
- Use `DESeqDataSetFromTximeta()` instead of matrix import when using salmon/alevin counts.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `edgeR` | You have ≥3 replicates per group; you want apeglm LFC shrinkage; you prefer Bayesian-style shrinkage approach. | You have very small n (2 per group); you need quasi-likelihood F-tests; you prefer exact negative binomial tests. |
| `limma-voom` | You are working with count data from a well-powered experiment (≥5 replicates). | You have microarray data, large n (≥10/group), or want to use linear model contrasts flexibly. |
| `fishpond (Swish)` | Your data comes from Salmon and you have bootstrap replicates; you want robust transcript-level DE. | You want gene-level DE from any aligner (STAR+featureCounts etc.) without bootstraps. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Love MI, Huber W, Anders S (2014). Genome Biol 15:550.** [PMID:25516281](https://pubmed.ncbi.nlm.nih.gov/25516281)  
  Original DESeq2 paper demonstrating superior FDR control and power vs simple fold-change ranking.

- **Rapaport F et al. (2013). Genome Biol 14:R95.** [PMID:24651052](https://pubmed.ncbi.nlm.nih.gov/24651052)  
  Benchmark: DESeq2 and edgeR outperform other methods in sensitivity/specificity; DESeq2 better FDR control at low counts.

- **Love MI et al. (2015). F1000Research 4:1070.** [PMID:29481549](https://pubmed.ncbi.nlm.nih.gov/29481549)  
  End-to-end RNA-seq workflow paper demonstrating DESeq2 from Salmon → tximeta → DE analysis.

## Common Errors & Troubleshooting

### `Error in checkForExperimentalReplicates: ...`

**Cause:** Only one sample per condition — DESeq2 needs replicates

**Fix:** You must have ≥2 biological replicates per group

### `Error: every gene contains at least one zero`

**Cause:** Using VST/rlog on a dataset with all-zero genes

**Fix:** Pre-filter: `dds <- dds[rowSums(counts(dds)) > 0,]`

### `NA p-values for some genes`

**Cause:** Genes with all-zero counts OR extreme Cook's distance outliers

**Fix:** Expected — these are filtered by independent filtering / Cook's cutoff

### `model matrix not full rank`

**Cause:** Perfect collinearity in the design matrix (e.g. batch confounds condition)

**Fix:** Drop one level or use a different design; run `colnames(model.matrix(~cond,df))`

### From Community Q&A (Biostars)

- [DiffBind normalization error: invalid argument type (list) - cannot make it work everything seems co](https://www.biostars.org/p/9610880/)
- [DESeq2: error in checkFullRank(modelMatrix)](https://www.biostars.org/p/9605748/)
- [Are unequal sample sizes in differential gene expression (DGE) analysis a problem for edgeR DESeq2 a](https://www.biostars.org/p/9605688/)
- [Contrasts for comparing condition within tissue](https://www.biostars.org/p/9605190/)
- [PyDeseq2 - InvalidIndexError](https://www.biostars.org/p/9604809/)

## Additional Notes from Official Documentation

*Extracted from the DESeq2 Bioconductor vignette(s)*

### 11/13/2025


A basic task in the analysis of count data from RNA-seq is the detection of differentially expressed genes. The count data are presented as a table which reports, for each sample, the number of sequence fragments that have been assigned to each gene. Analogous data also arise for other assay types, including comparative ChIP-Seq, HiC, shRNA screening, and mass spectrometry. An important analysis question is the quantification and statistical inference of systematic changes between conditions, as compared to within-condition variability. The package DESeq2 provides methods to test for differential expression by use of negative binomial generalized linear models; the estimates of dispersion and logarithmic fold changes incorporate data-driven prior distributions. This vignette explains the 

### Standard workflow


Note: if you use DESeq2 in published research, please cite:
Love, M.I., Huber, W., Anders, S. (2014) Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biology , 15 :550. 10.1186/s13059-014-0550-8
Other Bioconductor packages with similar aims are edgeR , limma , DSS , EBSeq , and baySeq .

### Quick start


Here we show the most basic steps for a differential expression analysis. There are a variety of steps upstream of DESeq2 that result in the generation of counts or estimated counts for each sample, which we will discuss in the sections below. This code chunk assumes that you have a count matrix called cts and a table of sample information called coldata . The design indicates how to model the samples, here, that we want to measure the effect of the condition, controlling for batch differences. The two factor variables batch and condition should be columns of coldata .
The following starting functions will be explained below:
If you have performed transcript quantification (with Salmon , kallisto , RSEM , etc.) you could import the data with tximport , which produces a list, and then you 

```r
dds <- DESeqDataSetFromMatrix(countData = cts,
                              colData = coldata,
                              design= ~ batch + condition)
dds <- DESeq(dds)
resultsNames(dds) # lists the coefficients
res <- results(dds, name="condition_trt_vs_untrt")
# or to shrink log fold changes association with condition:
res <- lfcShrink(dds, coef="condition_trt_vs_untrt", type="apeglm")
```

### How to get help for DESeq2


Any and all DESeq2 questions should be posted to the Bioconductor support site , which serves as a searchable knowledge base of questions and answers:
https://support.bioconductor.org
Posting a question and tagging with âDESeq2â will automatically send an alert to the package authors to respond on the support site. See the first question in the list of Frequently Asked Questions (FAQ) for information about how to construct an informative post.
You should not email your question to the package authors, as we will just reply that the question should be posted to the Bioconductor support site .

### Acknowledgments


We have benefited in the development of DESeq2 from the help and feedback of many individuals, including but not limited to:
The Bionconductor Core Team, Alejandro Reyes, Andrzej Oles, Aleksandra Pekowska, Felix Klein (early testers), Constantin Ahlmann-Eltze (glmGamPoi), Nikolaos Ignatiadis (IHW, greaterAbs), Raphael Rossellini (greaterAbs), Anqi Zhu (apeglm), Joseph Ibrahim (apeglm), Vince Carey, Owen Solberg, Ruping Sun, Devon Ryan, Steve Lianoglou, Jessica Larson, Christina Chaivorapol, Pan Du, Richard Bourgon, Willem Talloen, Elin Videvall, Hanneke van Deutekom, Todd Burwell, Jesse Rowley, Igor Dolgalev, Stephen Turner, Ryan C Thompson, Tyr Wiesner-Hanks, Konrad Rudolph, David Robinson, Mingxiang Teng, Mathias Lesche, Sonali Arora, Jordan Ramilowski, Ian Dworkin, Bjorn Gruning, Ryan 

### Funding


DESeq2 and its developers have been partially supported by funding from the European Unionâs 7th Framework Programme via Project RADIANT, NIH NHGRI R01-HG009937, and by a CZI EOSS award.
ELIXIR feedback: Your feedback matters! Please take our quick user satisfaction survey: link

### Why un-normalized counts?


As input, the DESeq2 package expects count data as obtained, e.g., from RNA-seq or another high-throughput sequencing experiment, in the form of a matrix of integer values. The value in the i -th row and the j -th column of the matrix tells how many reads can be assigned to gene i in sample j . Analogously, for other types of assays, the rows of the matrix might correspond e.g.Â to binding regions (with ChIP-Seq) or peptide sequences (with quantitative mass spectrometry). We will list method for obtaining count matrices in sections below.
The values in the matrix should be un-normalized counts or estimated counts of sequencing reads (for single-end RNA-seq) or fragments (for paired-end RNA-seq). The RNA-seq workflow describes multiple techniques for preparing such count matrices. It is im

### The DESeqDataSet


The object class used by the DESeq2 package to store the read counts and the intermediate estimated quantities during statistical analysis is the DESeqDataSet , which will usually be represented in the code here as an object dds .
A technical detail is that the DESeqDataSet class extends the RangedSummarizedExperiment class of the SummarizedExperiment package. The âRangedâ part refers to the fact that the rows of the assay data (here, the counts) can be associated with genomic ranges (the exons of genes). This association facilitates downstream exploration of results, making use of other Bioconductor packagesâ range-based functionality (e.g.Â find the closest ChIP-seq peaks to the differentially expressed genes).
A DESeqDataSet object must have an associated design formula . The des

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/DESeq2.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/vignettes/DESeq2/inst/doc/DESeq2.html
- **GitHub:** https://github.com/mikelove/DESeq2
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Love MI, Huber W, Anders S (2014). Genome Biology, 15:550.

---
