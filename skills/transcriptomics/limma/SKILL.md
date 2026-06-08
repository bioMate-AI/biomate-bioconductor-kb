---
name: bioconductor-limma
description: Given a matrix of counts (e.g. from featureCounts) and optional information about the genes, this tool performs differential expression (DE) using the limma Bioconductor package and produces plots and tables useful in DE analysis. Interacti
when_to_use: Use when: Use when performing differential expression analysis on quantitative gene expression data (microarrays, RNA-seq, qPCR, proteomics) from designed experiments, especially those with complex multi-factor designs, batch effects, or small sample sizes.
user-invocable: false
---

# limma

## When to Use

- Microarray differential expression
- RNA-seq (via voom transformation)
- Complex designs: factorial, time-course, blocking
- Batch effect correction with duplicateCorrelation
- Rotation test for gene set testing (ROAST/MROAST)

**Alternatives:** `DESeq2`, `edgeR`

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Replicates** | ≥3 per group for RNA-seq; works with n=2 but with reduced power |
| **Input Format** | For RNA-seq: raw counts + `voom()`; for microarray: log2 intensities (pre-normalized) |
| **Must Not Use** | Raw counts directly without voom() for RNA-seq |
| **Notes** | For microarray: normalize with `normalizeBetweenArrays()` before fitting |

## Key Parameters

- **`method`**: In backgroundCorrect(), options include "normexp" (recommended with offset=50 to avoid negative/zero intensities and stabilize variance) or "subtract". In normalizeWithinArrays(), options include "printtiploess" (default for spotted arrays), "loess" (global loess, for Agilent arrays), "robustspline" (empirical Bayes compromise), or "control" (using control spots).
- **`green.only`**: In read.maimages(), set to TRUE to read single-channel data and output an EListRaw/EList object instead of an RGList.
- **`wt.fun`**: In read.maimages(), a function to compute spot quality weights (e.g., wtflags() or wtarea()) to downweight unreliable spots.
- **`trend`**: In eBayes(), set to TRUE to model a prior variance trend, which is highly recommended for RNA-seq or single-channel data.
- **`robust`**: In eBayes(), set to TRUE to protect hyperparameter estimation against hypervariable genes.

## Workflow Variants

### Two Color Microarray Analysis

**Intent**: Analyze two-color spotted microarray data to identify differentially expressed genes.

**Inputs**:
- `targets.txt (tab-delimited metadata file listing array filenames and Cy3/Cy5 targets)`
- `.gpr (or other image analysis output files containing raw intensity data per array)`

**Steps**:
1. Read targets metadata using readTargets().
2. Read raw intensities and apply spot quality weights using read.maimages().
3. Perform background correction using backgroundCorrect() with the normexp method.
4. Perform within-array normalization using normalizeWithinArrays().
5. Fit gene-wise linear models using lmFit().
6. Apply empirical Bayes smoothing using eBayes().
7. Extract top differentially expressed genes using topTable().

```r
library(limma)
targets <- readTargets("targets.txt")
f <- function(x) as.numeric(x$Flags > -99)
RG <- read.maimages(targets, source="genepix", wt.fun=f)
RG <- backgroundCorrect(RG, method="normexp", offset=50)
MA <- normalizeWithinArrays(RG)
fit <- lmFit(MA, design=c(-1,1,-1,1))
fit <- eBayes(fit)
topTable(fit)
```


---

### Single Channel Microarray Analysis

**Intent**: Analyze single-channel microarray data (e.g., Affymetrix) to identify differentially expressed genes.

**Inputs**:
- `targets.txt (tab-delimited metadata file listing filenames and genotypes/treatments)`
- `.CEL (raw Affymetrix intensity files)`

**Steps**:
1. Read targets metadata using readTargets().
2. Read and pre-process raw data using ReadAffy() and gcrma() from the gcrma package.
3. Construct a design matrix representing the experimental groups.
4. Fit gene-wise linear models using lmFit().
5. Apply empirical Bayes smoothing with robust and trend options using eBayes().
6. Extract top differentially expressed genes using topTable().

```r
library(gcrma)
library(limma)
targets <- readTargets("targets.txt")
ab <- ReadAffy(filenames=targets$FileName)
eset <- gcrma(ab)
design <- cbind(WT=1, MUvsWT=targets$Genotype=="mu")
fit <- lmFit(eset, design)
fit <- eBayes(fit)
topTable(fit, coef="MUvsWT")
```


---

### Filtering Unexpressed Probes

**Intent**: Filter out unexpressed probes based on average log-expression values before empirical Bayes analysis.

**Inputs**:
- `y (normalized expression object, e.g., EList or MAList)`
- `design (design matrix)`

**Steps**:
1. Fit initial linear model using lmFit().
2. Inspect average expression distribution and residual variance using hist() and plotSA().
3. Filter out probes below a threshold.
4. Run empirical Bayes with trend on the filtered fit using eBayes().
5. Inspect the final residual variance plot using plotSA().

```r
fit <- lmFit(y, design)
hist(fit$Amean)
plotSA(fit)
keep <- fit$Amean > CutOff
fit2 <- eBayes(fit[keep,], trend=TRUE)
plotSA(fit2)
```


## Best Practices

- For RNA-seq use `voom()` + `lmFit()` + `eBayes()` workflow.
- Set `trend=TRUE` in `eBayes()` for RNA-seq data (accommodates mean-variance trend).
- Use `duplicateCorrelation()` for paired samples or repeated measures.
- Use `removeBatchEffect()` only for visualisation — not as input for DE; put batch in design.
- For microarray, quantile-normalise with `normalizeBetweenArrays()` before lmFit.
- Use `fry()` or `camera()` for gene set testing — they account for inter-gene correlation.
- voomWithQualityWeights() improves power when sample quality varies.

## Common Pitfalls

- print-tip loess on Agilent arrays=Agilent arrays do not have print-tip groups; using print-tip loess is inappropriate and global loess ("loess") should be used instead.
- print-tip loess on small arrays=Unreliable for arrays with fewer than 150 spots per print-tip group or when many spots have missing values.
- simple background subtraction=Can produce negative or zero corrected intensities, leading to missing values in log-ratios; "normexp" with an offset is preferred.
- boutique arrays=Loess normalization assumes most probes are not differentially expressed; this fails on boutique arrays with specifically selected genes (use control/titration spots instead).
- qualitative weights in lmFit=marray read functions populate weights with qualitative flags; these must not be used as quantitative weights in lmFit (set weights=NULL or convert them first).

## Alternatives

- **marray**: Mentioned as an alternative package for reading and normalizing spotted two-color microarray data; objects can be converted to limma classes using the convert package.
- **affy/gcrma/aroma.affymetrix**: Recommended for reading and normalizing Affymetrix GeneChip data before using limma.
- **vst/beadarray**: Can be used in conjunction with limma for pre-processing Illumina data.
- **edgeR**: Provides the filterByExpr function to identify genes or exons for filtering in RNA-seq workflows.
- **limmaGUI/affylmGUI**: Graphical user interfaces for users who prefer menu-driven analysis.

## References

- Homepage: bioconductor.org/packages/limma
- Vignette: bioconductor.org/packages/release/bioc/vignettes/limma
