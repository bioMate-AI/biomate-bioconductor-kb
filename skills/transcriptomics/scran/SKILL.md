---
name: bioconductor-scran
description: Implements miscellaneous functions for interpretation of single-cell RNA-seq data. Methods are provided for assignment of cell cycle phase, detection of highly variable and significantly correlated genes, identification of marker genes, and
when_to_use: Use when: Pooling-based normalisation (handles zero inflation); Detecting highly variable genes for HVG selection; Graph-based clustering of single cells; Marker gene detection with pairwise tests; Pseudobulk DE analysis with aggregateAcrossCells
user-invocable: false
---

# scran — Comprehensive Skill Guide

> **Domain:** Single-cell RNA-seq
> **Bioconductor:** [scran](https://bioconductor.org/packages/release/bioc/html/scran.html)
> **Paper:** Lun ATL, McCarthy DJ, Marioni JC (2016). Genome Biology, 17:75.

Methods for single-cell RNA-seq: pooling-based normalisation, high-variable gene detection, doublet detection, and graph-based clustering.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.40.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** SingleCellExperiment, scuttle
- **Imports:** SummarizedExperiment, S4Vectors, BiocGenerics, BiocParallel, Rcpp, Matrix, edgeR, limma, igraph, statmod, MatrixGenerics, S4Arrays, DelayedArray, BiocSingular, bluster, metapod, dqrng, beachmat
- **System requirements:** C++11
- **Install:** `BiocManager::install("scran")`

## When to Use

- Pooling-based normalisation (handles zero inflation)
- Detecting highly variable genes for HVG selection
- Graph-based clustering of single cells
- Marker gene detection with pairwise tests
- Pseudobulk DE analysis with aggregateAcrossCells

**Alternatives:** `Seurat normalisation`, `scuttle`, `sctransform`

## Do NOT Use When

- Bulk RNA-seq — use DESeq2 or edgeR.
- Very small datasets (<100 cells) where pooling-based size factor estimation fails.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Cells** | ≥100 cells (pooling for size factors requires sufficient cells) |
| **Input Format** | SingleCellExperiment with raw count matrix |
| **Notes** | Works best after quality filtering with scater/perCellQCMetrics |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("scran")
library(scran)
```

## Workflows

### scRNA-seq Normalization and HVG Selection
*Core OSCA workflow: normalize pooled size factors → model gene variance → select HVGs*

#### Normalize with pooling-based size factors

```r
library(scran)
library(scater)

# sce is a SingleCellExperiment (post-QC)
set.seed(42)
clusters <- quickCluster(sce)           # pre-cluster to improve size factor estimation
sce      <- computeSumFactors(sce, clusters=clusters)
summary(sizeFactors(sce))              # should be positive; flag negatives

sce <- logNormCounts(sce)              # log-normalize using computed size factors
```

#### Model gene variance and select highly variable genes

```r
dec     <- modelGeneVar(sce)           # models mean-variance trend
hvgs    <- getTopHVGs(dec, n=3000)     # top 3000 HVGs for downstream use

# For multi-batch: model per batch then combine
dec1    <- modelGeneVar(sce, block=sce$batch)
hvgs_blocked <- getTopHVGs(dec1, n=3000)
```

#### Dimensionality reduction and clustering

```r
sce <- runPCA(sce, subset_row=hvgs, ncomponents=30)
sce <- runUMAP(sce, dimred="PCA")

# Graph-based clustering
library(bluster)
clusters <- clusterRows(reducedDim(sce,"PCA"), NNGraphParam(k=20))
sce$cluster <- factor(clusters)
plotReducedDim(sce, "UMAP", colour_by="cluster")
```

#### Per-cluster marker gene detection

```r
markers <- findMarkers(sce, groups=sce$cluster,
                       test.type="wilcox", direction="up")
# Top markers for cluster 1:
markers[[1]][1:10, c("Top","p.value","FDR")]
```


## Key Functions & Parameters

### `quickCluster()`

Fast pre-clustering for normalisation (required before computeSumFactors)

| Parameter | Description |
|-----------|-------------|
| `x` | SingleCellExperiment or matrix |
| `min.size` | minimum cluster size (default 100) |
| `method` | 'igraph' (default) \| 'hclust' |

### `computeSumFactors()`

Pooling-based normalisation (deconvolution); handles near-zero counts

| Parameter | Description |
|-----------|-------------|
| `x` | SingleCellExperiment |
| `clusters` | cluster assignments from quickCluster() |
| `min.mean` | lower bound on average count for HEG selection (default 0.1) |
| `BPPARAM` | parallel backend |

### `modelGeneVar()`

Model per-gene variance to identify HVGs

| Parameter | Description |
|-----------|-------------|
| `x` | log-normalised SCE |
| `block` | factor for blocking by sample/batch |
| `density.weights` | use density weights for mean-variance fit |

### `getTopHVGs()`

Select top HVGs from modelGeneVar output

| Parameter | Description |
|-----------|-------------|
| `stats` | output of modelGeneVar() |
| `n` | number of HVGs (default 2000) |
| `var.threshold` | minimum biological variance threshold |
| `fdr.threshold` | FDR threshold for significant HVGs |

### `buildSNNGraph()`

Build shared nearest-neighbour graph for clustering

| Parameter | Description |
|-----------|-------------|
| `x` | SCE or matrix |
| `k` | number of nearest neighbours (default 10; higher=coarser clusters) |
| `type` | 'rank' (default) \| 'number' \| 'jaccard' |
| `d` | number of PCs to use |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Pooling reads across cells enables robust size factor estimation even for very sparse single-cell data.
- Most genes are NOT differentially expressed between cells of the same type (for size factor estimation).
- Highly variable genes (HVGs) reflect biological variation, not purely technical noise.

## Result Interpretation

- `sizeFactors(sce)`: per-cell scaling factors; very high or very low values indicate problematic cells.
- `logcounts`: log1p-transformed normalized counts; use for visualization and clustering input.
- `modelGeneVar()` result: `total` variance = `bio` + `tech`; only `bio > 0` genes are HVGs.
- `pairwiseTTests()` / `scoreMarkers()`: use `Cohen's d` and `AUC` for marker specificity, not just p-value.

## Best Practices

- Run `quickCluster()` before `computeSumFactors()` — pooling within clusters is critical for accuracy.
- Use `scuttle::logNormCounts()` after `computeSumFactors()` to apply size factors.
- For multi-sample experiments, pass `block=sce$Sample` to `modelGeneVar()` to account for batch.
- Prefer `aggregateAcrossCells()` + DESeq2/edgeR for differential abundance (pseudobulk).
- Use `scDblFinder::scDblFinder()` (uses scran infrastructure) for doublet detection.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `Seurat SCTransform` | You are in the Seurat ecosystem and want regularized NB regression normalization. | You want Bioconductor-native normalization with theoretical underpinning for sparse data. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Lun ATL, McCarthy DJ, Marioni JC (2016). Genome Biol 17:75.** [PMID:27122128](https://pubmed.ncbi.nlm.nih.gov/27122128)  
  Pooling-based size factor estimation outperforms library-size normalization for sparse scRNA-seq data.

## Common Errors & Troubleshooting

### `Error in computeSumFactors: not enough cells in cluster`

**Cause:** Cluster too small for pooling

**Fix:** Reduce `min.size` in quickCluster or merge small clusters

## Additional Notes from Official Documentation

*Extracted from the scran Bioconductor vignette(s)*

### 1 Introduction


Single-cell RNA sequencing (scRNA-seq) is a widely used technique for profiling gene expression in individual cells.
This allows molecular biology to be studied at a resolution that cannot be matched by bulk sequencing of cell populations.
The scran package implements methods to perform low-level processing of scRNA-seq data,
including cell cycle phase assignment, variance modelling and testing for marker genes and gene-gene correlations.
This vignette provides brief descriptions of these methods and some toy examples to demonstrate their use.
Note: A more comprehensive description of the use of scran (along with other packages) in a scRNA-seq analysis workflow is available at https://osca.bioconductor.org .

### 2 Setting up the data


We start off with a count matrix where each row is a gene and each column is a cell.
These can be obtained by mapping read sequences to a reference genome, and then counting the number of reads mapped to the exons of each gene.
(See, for example, the Rsubread package to do both of these tasks.)
Alternatively, pseudo-alignment methods can be used to quantify the abundance of each transcript in each cell.
For simplicity, we will pull out an existing dataset from the scRNAseq package.
This particular dataset is taken from a study of the human pancreas with the CEL-seq protocol (Grun et al. 2016 ) .
It is provided as a SingleCellExperiment object (from the SingleCellExperiment package), which contains the raw data and various annotations.
We perform some cursory quality control to remove cell

```r
library(scRNAseq)
sce <- GrunPancreasData()
sce
```

```r
## class: SingleCellExperiment 
## dim: 20064 1728 
## metadata(0):
## assays(1): counts
## rownames(20064): A1BG-AS1__chr19 A1BG__chr19 ... ZZEF1__chr17
##   ZZZ3__chr1
## rowData names(2): symbol chr
## colnames(1728): D2ex_1 D2ex_2 ... D17TGFB_95 D17TGFB_96
## colData names(2): donor sample
## reducedDimNames(0):
## mainExpName: endogenous
## altExpNames(1): ERCC
```

### 3 Variance modelling


We identify genes that drive biological heterogeneity in the data set by modelling the per-gene variance.
By only using a subset of highly variable genes in downstream analyses like clustering, we improve resolution of biological structure by removing uninteresting genes driven by technical noise.
We decompose the total variance of each gene into its biological and technical components by fitting a trend to the endogenous variances (Lun, McCarthy, and Marioni 2016 ) .
The fitted value of the trend is used as an estimate of the technical component, and we subtract the fitted value from the total variance to obtain the biological component for each gene.
If we have spike-ins, we can use them to fit the trend instead.
This provides a more direct estimate of the technical variance and avoids 

```r
dec <- modelGeneVar(sce)
plot(dec$mean, dec$total, xlab="Mean log-expression", ylab="Variance")
curve(metadata(dec)$trend(x), col="blue", add=TRUE)
```

```r
dec2 <- modelGeneVarWithSpikes(sce, 'ERCC')
plot(dec2$mean, dec2$total, xlab="Mean log-expression", ylab="Variance")
points(metadata(dec2)$mean, metadata(dec2)$var, col="red")
curve(metadata(dec2)$trend(x), col="blue", add=TRUE)
```

### 4 Automated PC choice


Principal components analysis is commonly performed to denoise and compact the data prior to downstream analysis.
A common question is how many PCs to retain; more PCs will capture more biological signal at the cost of retaining more noise and requiring more computational work.
One approach to choosing the number of PCs is to use the technical component estimates to determine the proportion of variance that should be retained.
This is implemented in denoisePCA() , which takes the estimates returned by modelGeneVar() or friends.
(For greater accuracy, we use the fit with the spikes; we also subset to only the top HVGs to remove noise.)
Another approach is based on the assumption that each subpopulation should be separated from each other on a different axis of variation.
Thus, we choose th

```r
sced <- denoisePCA(sce, dec2, subset.row=getTopHVGs(dec2, prop=0.1))
ncol(reducedDim(sced, "PCA"))
```

```r
## [1] 50
```

### 5 Graph-based clustering


Clustering of scRNA-seq data is commonly performed with graph-based methods due to their relative scalability and robustness. scran provides several graph construction methods based on shared nearest neighbors (Xu and Su 2015 ) through the buildSNNGraph() function.
This is most commonly generated from the selected PCs, after which community detection methods from the igraph package can be used to explicitly identify clusters.
By default, buildSNNGraph() uses the mode of shared neighbor weighting described by Xu and Su ( 2015 ) , but other weighting methods (e.g., the Jaccard index) are also available by setting type= .
An unweighted \(k\) -nearest neighbor graph can also be constructed with buildKNNGraph() .
We can then use methods from scater to visualize this clustering on a \(t\) -SNE 

```r
# In this case, using the PCs that we chose from getClusteredPCs().
g <- buildSNNGraph(sce, use.dimred="PCAsub")
cluster <- igraph::cluster_walktrap(g)$membership

# Assigning to the 'colLabels' of the 'sce'.
colLabels(sce) <- factor(cluster)
table(colLabels(sce))
```

```r
## 
##   1   2   3   4   5   6   7   8   9  10  11  12 
##  79 285  64 170 166 164 124  32  57  63  63  24
```

### 6 Identifying marker genes


The scoreMarkers() wrapper function will perform differential expression comparisons between pairs of clusters to identify potential marker genes.
For each pairwise comparison, we compute a variety of effect sizes to quantify the differences between those clusters.
Cohenâs \(d\) is a standardized log-fold change, representing the number of standard deviations that separate the means of two groups.
This is analogous to the \(t\) -statistic in Studentâs \(t\) -test.
The area under the curve (AUC) is the probability that a randomly chosen observation from one group is greater than a random observation from another group.
This is proportional to the U-statistic from the Wilcoxon ranked sum test.
We also compute the log-fold change in the proportion of cells with detectable (i.e., non-zero

```r
# Uses clustering information from 'colLabels(sce)' by default:
markers <- scoreMarkers(sce)
markers
```

```r
## List of length 12
## names(12): 1 2 3 4 5 6 7 8 9 10 11 12
```

### 7 Detecting correlated genes


Another useful procedure is to identify significant pairwise correlations between pairs of HVGs.
The idea is to distinguish between HVGs caused by random stochasticity, and those that are driving systematic heterogeneity, e.g., between subpopulations.
Correlations are computed by the correlatePairs method using a slightly modified version of Spearmanâs rho,
tested against the null hypothesis of zero correlation using the same method in cor.test() .
As with variance estimation, if uninteresting substructure is present, this should be blocked on using the block= argument.
This avoids strong correlations due to the blocking factor.
The pairs can be used for choosing marker genes in experimental validation, and to construct gene-gene association networks.
In other situations, the pairs may 

```r
# Using the first 200 HVs, which are the most interesting anyway.
of.interest <- top.hvgs[1:200]
cor.pairs <- correlatePairs(sce, subset.row=of.interest)
cor.pairs
```

```r
## DataFrame with 19900 rows and 5 columns
##                 gene1          gene2          rho      p.value          FDR
##           <character>    <character>    <numeric>    <numeric>    <numeric>
## 1     KCNQ1OT1__chr11 UGDH-AS1__chr4     0.830625  0.00000e+00  0.00000e+00
## 2           CPE__chr4    SCG5__chr15     0.813664 6.05366e-306 6.02339e-302
## 3         CHGA__chr14    SCG5__chr15     0.808313 7.64265e-299 5.06963e-295
## 4           GCG__chr2     TTR__chr18     0.803692 6.86304e-293 3.41436e-289
## 5         CHGB__chr20      CPE__chr4     0.802498 2.23623e-291 8.90020e-288
## ...               ...            ...          ...          ...          ...
## 19896      ELF3__chr1 METTL21A__chr2  3.83996e-05     0.998900     0.999101
## 19897      EGR1__chr5    NPTX2__chr7 -2.94559e-05     0.999156     0.999307
## 19898     ODF2L__chr1      VGF__chr7 -2.25268e-05     0.999355     0.999455
## 19899 LOC90834__chr22  SLC30A8__chr8  1.99362e-05     0.999429     0.999479
## 19900       IL8__chr4    UGGT1__chr2  1.20185e-05     0.999656     0.999656
```

### 8 Converting to other formats


The SingleCellExperiment object can be easily converted into other formats using the convertTo method.
This allows analyses to be performed using other pipelines and packages.
For example, if DE analyses were to be performed using edgeR , the count data in sce could be used to construct a DGEList .
By default, rows corresponding to spike-in transcripts are dropped when get.spikes=FALSE .
As such, the rows of y may not correspond directly to the rows of sce â users should match by row name to ensure correct cross-referencing between objects.
Normalization factors are also automatically computed from the size factors.
The same conversion strategy roughly applies to the other supported formats.
DE analyses can be performed using DESeq2 by converting the object to a DESeqDataSet .
Cells can

```r
y <- convertTo(sce, type="edgeR")
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/scran.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/vignettes/scran/inst/doc/scran.html
- **GitHub:** https://github.com/Bioconductor/scran
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Lun ATL, McCarthy DJ, Marioni JC (2016). Genome Biology, 17:75.

---
