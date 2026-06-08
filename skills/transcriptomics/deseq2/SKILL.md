---
name: bioconductor-deseq2
description: Uses DESeq2 version 1.40.2 to estimate variance-mean dependence in count data from high-throughput sequencing assays and test for differential expression based on a model using the negative binomial distribution.
when_to_use: Use when: When analyzing un-normalized integer count data from RNA-seq, ChIP-seq, HiC, shRNA screening, or mass spectrometry to identify systematic changes between conditions while controlling for within-condition variability.
user-invocable: false
---

# DESeq2

## When to Use

- Two-group comparison (treatment vs control)
- Multi-factor design with blocking variables
- Likelihood ratio test for complex designs
- Time-series expression analysis
- Allelic imbalance testing

**Alternatives:** `edgeR`, `limma-voom`, `DEXSeq (exon-level)`

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Replicates** | ≥2 biological replicates per group (≥3 strongly recommended for FDR control) |
| **Input Format** | Raw integer count matrix: genes × samples (not normalized values) |
| **Must Not Use** | TPM, FPKM, RPKM, or any library-size-normalized values as input |
| **Coverage** | ≥5–10M uniquely mapped reads per sample recommended; <1M is problematic |
| **Sparsity** | Works best with bulk RNA-seq; for highly sparse data (sc) use sfType='poscounts' |

## Key Parameters

- **`design`**: Formula specifying the experimental design (e.g., ~ batch + condition). The variable of interest should be at the end, and the control level should be the first level of the factor
- **`contrast`**: Character vector of length 3 (e.g., c("factorName", "numeratorLevel", "denominatorLevel")) or a list/numeric vector used in results() to extract specific comparisons
- **`type`**: Shrinkage estimator type in lfcShrink() ("apeglm", "ashr", or "normal"), with "apeglm" being the default
- **`blind`**: Logical indicating whether the transformation in vst() or rlog() should be blind to the sample information in the design formula (default TRUE for QA/QC, FALSE for downstream analysis where design-driven differences are expected)
- **`test`**: Hypothesis test to use, either "Wald" (default) or "LRT" (Likelihood Ratio Test)
- **`reduced`**: Formula for the reduced model when using test="LRT"
- **`alpha`**: Significance cutoff for independent filtering (default 0.1)

## Workflow Variants

### Standard De From Matrix

**Intent**: Perform standard differential expression analysis starting from a raw count matrix and sample metadata.

**Inputs**:
- `cts (matrix of un-normalized integer counts)`
- `coldata (data.frame of sample metadata)`

**Steps**:
1. Construct DESeqDataSet from matrix
2. Pre-filter low count genes
3. Set factor levels and reference group
4. Run DESeq() pipeline
5. Extract results and apply LFC shrinkage
6. Visualize results (MA-plot, plotCounts)
7. Export results to CSV

```r
library("DESeq2")
dds <- DESeqDataSetFromMatrix(countData = cts,
                              colData = coldata,
                              design = ~ condition)
smallestGroupSize <- 3
keep <- rowSums(counts(dds) >= 10) >= smallestGroupSize
dds <- dds[keep,]
dds$condition <- factor(dds$condition, levels = c("untreated","treated"))
dds$condition <- relevel(dds$condition, ref = "untreated")
dds <- DESeq(dds)
res <- results(dds)
resultsNames(dds)
resLFC <- lfcShrink(dds, coef="condition_treated_vs_untreated", type="apeglm")
resOrdered <- res[order(res$pvalue),]
summary(res)
plotMA(res, ylim=c(-2,2))
plotMA(resLFC, ylim=c(-2,2))
plotCounts(dds, gene=which.min(res$padj), intgroup="condition")
write.csv(as.data.frame(resOrdered),
          file="condition_treated_results.csv")
```


---

### De From Transcript Abundance

**Intent**: Import transcript-level quantification files and summarize them to gene-level counts for differential expression analysis.

**Inputs**:
- `quant.sf.gz (Salmon transcript quantification files)`
- `samples.txt (sample metadata table)`
- `tx2gene.gencode.v27.csv (transcript-to-gene mapping file)`

**Steps**:
1. Read sample metadata
2. Locate quantification files
3. Import and summarize to gene-level counts using tximport
4. Construct DESeqDataSet from tximport object

```r
library("tximport")
library("readr")
library("tximportData")
dir <- system.file("extdata", package="tximportData")
samples <- read.table(file.path(dir,"samples.txt"), header=TRUE)
samples$condition <- factor(rep(c("A","B"),each=3))
rownames(samples) <- samples$run
files <- file.path(dir,"salmon", samples$run, "quant.sf.gz")
names(files) <- samples$run
tx2gene <- read_csv(file.path(dir, "tx2gene.gencode.v27.csv"))
txi <- tximport(files, type="salmon", tx2gene=tx2gene)
library("DESeq2")
ddsTxi <- DESeqDataSetFromTximport(txi,
                                   colData = samples,
                                   design = ~ condition)
```


---

### Multi Factor Analysis

**Intent**: Perform differential expression analysis controlling for additional batch or technical covariates.

**Inputs**:
- `dds (DESeqDataSet object)`

**Steps**:
1. Update design formula to include covariates
2. Run DESeq() pipeline
3. Extract results for the primary condition
4. Extract results for the covariate using contrasts

```r
design(ddsMF) <- formula(~ type + condition)
ddsMF <- DESeq(ddsMF)
resMF <- results(ddsMF)
resMFType <- results(ddsMF,
                     contrast=c("type", "single", "paired"))
```


---

### Likelihood Ratio Test

**Intent**: Perform a Likelihood Ratio Test (LRT) to identify genes with significant changes across multi-level factors or time-series.

**Inputs**:
- `dds (DESeqDataSet object)`

**Steps**:
1. Run DESeq() with LRT test and specify a reduced design formula
2. Extract results

```r
dds <- DESeq(dds, test="LRT", reduced=~1)
res <- results(dds)
```


---

### Transformation And Qc

**Intent**: Transform count data to stabilize variance across the mean and perform sample-level quality control visualization.

**Inputs**:
- `dds (DESeqDataSet object)`

**Steps**:
1. Apply VST and rlog transformations
2. Plot standard deviation vs mean to assess variance stabilization
3. Generate sample distance heatmap
4. Generate Principal Component Analysis (PCA) plot

```r
vsd <- vst(dds, blind=FALSE)
rld <- rlog(dds, blind=FALSE)
ntd <- normTransform(dds)
library("vsn")
meanSdPlot(assay(ntd))
meanSdPlot(assay(vsd))
meanSdPlot(assay(rld))
library("pheatmap")
select <- order(rowMeans(counts(dds,normalized=TRUE)),
                decreasing=TRUE)[1:20]
df <- as.data.frame(colData(dds)[,c("condition","type")])
pheatmap(assay(vsd)[select,], cluster_rows=FALSE, show_rownames=FALSE,
         cluster_cols=FALSE, annotation_col=df)
sampleDists <- dist(t(assay(vsd)))
library("RColorBrewer")
sampleDistMatrix <- as.matrix(sampleDists)
rownames(sampleDistMatrix) <- paste(vsd$condition, vsd$type, sep="-")
colnames(sampleDistMatrix) <- NULL
colors <- colorRampPalette( rev(brewer.pal(9, "Blues")) )(255)
pheatmap(sampleDistMatrix,
         clustering_distance_rows=sampleDists,
         clustering_distance_cols=sampleDists,
         col=colors)
plotPCA(vsd, intgroup=c("condition", "type"))
```


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

## Common Pitfalls

- Providing normalized counts (e.g., FPKM, TPM, or library-size scaled counts) instead of raw, un-normalized integer counts
- Mismatched sample order between the columns of the count matrix and the rows of the sample metadata (column data)
- Relying on default alphabetical factor levels for reference groups without explicitly setting them (e.g., using relevel or factor(..., levels=...))
- Collapsing biological replicates using collapseReplicates (which is only for technical replicates)
- Using blind dispersion estimation (blind=TRUE) for downstream analysis when major design-driven differences are expected, leading to over-shrinkage
- Using the original normal shrinkage estimator for designs with interaction terms (not recommended; use apeglm or ashr instead, or rearrange the design)
- Model matrix not full rank errors due to linear combinations, nested groups, or levels without samples

## Alternatives

- **edgeR, limma, DSS, EBSeq, baySeq**: Alternative packages for differential expression analysis
- **IHW**: Independent Hypothesis Weighting package, used as an alternative to default BH p-value adjustment via results(dds, filterFun=ihw)
- **vst**: A faster alternative to rlog for large sample sizes (100s of samples)
- **glmGamPoi**: An alternative faster NB GLM engine specified via fitType="glmGamPoi" in DESeq() for complex designs

## References

- Homepage: bioconductor.org/packages/DESeq2
- Vignette: bioconductor.org/packages/release/bioc/vignettes/DESeq2
