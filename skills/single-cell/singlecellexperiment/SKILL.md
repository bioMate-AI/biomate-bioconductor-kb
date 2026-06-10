---
name: bioconductor-singlecellexperiment
description: Defines a S4 class for storing data from single-cell experiments. This includes specialized methods to store and retrieve spike-in information, dimensionality reduction coordinates and size factors for each cell, along with the usual metada
when_to_use: Use when: Store and manipulate scRNA-seq count matrices + metadata; Add dimensionality reductions (PCA, UMAP, t-SNE) to the object; Track multiple assay representations (counts, logcounts, normalized); Pass data between Bioconductor scRNA-seq tools (scran, scater, batchelor)
user-invocable: false
---

# SingleCellExperiment — Comprehensive Skill Guide

> **Domain:** Single-cell
> **Bioconductor:** [SingleCellExperiment](https://bioconductor.org/packages/release/bioc/html/SingleCellExperiment.html)
> **Paper:** Amezquita RA et al. (2020). Nature Methods, 17:137-145.

S4 class for storing single-cell experiment data including counts, reduced dimensions, and column/row metadata. The foundational container for the Bioconductor single-cell ecosystem.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.34.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** SummarizedExperiment
- **Imports:** S4Vectors, BiocGenerics, GenomicRanges, DelayedArray
- **System requirements:** URL
- **Install:** `BiocManager::install("SingleCellExperiment")`

## When to Use

- Store and manipulate scRNA-seq count matrices + metadata
- Add dimensionality reductions (PCA, UMAP, t-SNE) to the object
- Track multiple assay representations (counts, logcounts, normalized)
- Pass data between Bioconductor scRNA-seq tools (scran, scater, batchelor)

**Alternatives:** `SeuratObject (Seurat)`, `AnnData (Python/scanpy)`

## Do NOT Use When

- Bulk RNA-seq data — use SummarizedExperiment directly.
- Spatial transcriptomics without extending to SpatialExperiment.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | Count matrix (genes × cells) in any sparse or dense format |
| **Notes** | Column names = cell barcodes; row names = gene IDs |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("SingleCellExperiment")
library(SingleCellExperiment)
```

## Workflows

### Create and Manipulate SCE Object
*Build a SingleCellExperiment from count matrices and metadata*

#### Create SCE from count matrix

```r
library(SingleCellExperiment)
# counts: genes x cells matrix
sce <- SingleCellExperiment(
    assays  = list(counts = counts_matrix),
    colData = cell_metadata,   # DataFrame with cell-level info
    rowData = gene_metadata    # DataFrame with gene-level info
)
sce
```

#### Add normalized assay

```r
library(scuttle)
sce <- logNormCounts(sce)
# Now sce has both 'counts' and 'logcounts' assays
assayNames(sce)
```

#### Add dimensionality reductions

```r
library(scater)
sce <- runPCA(sce, ncomponents=50)
sce <- runUMAP(sce, dimred="PCA")
reducedDimNames(sce)   # c("PCA", "UMAP")
```

#### Access data

```r
# Access counts
mat <- counts(sce)
log_mat <- logcounts(sce)

# Access metadata
colData(sce)$cluster <- cluster_labels
rowData(sce)$is_mito <- grepl("^MT-", rownames(sce))

# Subset
sce_subset <- sce[rowData(sce)$is_hvg, colData(sce)$cluster == 1]
```

## Key Functions & Parameters

### `SingleCellExperiment()()`

Create a SingleCellExperiment from assay matrices

| Parameter | Description |
|-----------|-------------|
| `assays` | named list of matrices (e.g. list(counts=mat, logcounts=log1p(mat))) |
| `colData` | DataFrame of per-cell metadata (treatment, batch, cluster) |
| `rowData` | DataFrame of per-gene metadata (symbol, chromosome) |
| `reducedDims` | named list of low-dim embeddings (PCA, UMAP matrices) |

### `assay() / assays()()`

Get or set assay matrices

| Parameter | Description |
|-----------|-------------|
| `x` | SingleCellExperiment object |
| `i` | assay name (e.g. 'counts', 'logcounts') |

### `reducedDim() / reducedDims()()`

Access or set low-dim embeddings

| Parameter | Description |
|-----------|-------------|
| `x` | SingleCellExperiment |
| `type` | name string ('PCA', 'UMAP', 'TSNE') |

### `colData() / rowData()()`

Access cell or gene metadata DataFrames


### `logNormCounts()()`

Log-normalize counts in-place (via scuttle)

| Parameter | Description |
|-----------|-------------|
| `x` | SingleCellExperiment |
| `size.factors` | per-cell scaling factors; NULL = library-size normalization |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Each column represents a unique cell (after doublet removal).
- Assay named 'counts' contains raw UMI/read counts.

## Result Interpretation

- Object structure: colData = cell metadata (cluster, cell type, QC metrics); rowData = gene metadata.
- Accessing assays: `counts(sce)` = raw counts, `logcounts(sce)` = log-normalized.
- Multiple assays can coexist: `assayNames(sce)` lists all stored matrices.

## Best Practices

- Store raw counts in `assay(sce, 'counts')`; add `logcounts` for log-normalized values.
- Put all per-cell metadata (cluster, treatment, batch) in `colData(sce)`, NOT in a separate data frame.
- Use `reducedDims(sce) <- list(PCA=pca_mat)` to store embeddings in-object.
- Use `altExp(sce, 'ERCC')` to store spike-in or protein (CITE-seq) data alongside.
- Check `isSpike` / `sizeFactors` slots before running normalization.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `Seurat (SeuratObject)` | You use the Seurat ecosystem exclusively. | You want Bioconductor-native tools (scran, scater, batchelor) that all work with SCE. |
| `AnnData (Python/scanpy)` | You work in Python; you need large-scale backed arrays. | You want R and Bioconductor ecosystem integration. |

## Benchmark Evidence

*SingleCellExperiment (SCE) is a data container; citations measure its adoption and the
correctness of its design.*

- **Amezquita RA et al. (2020). Nature Methods 17:137.** [PMID:31792435](https://pubmed.ncbi.nlm.nih.gov/31792435)
  OSCA book paper — demonstrates that the SCE-based workflow (scran + scater + SCE)
  reproduces published single-cell results across 10 diverse datasets with full
  computational reproducibility.

- **Lun ATL, McCarthy DJ, Marioni JC (2016). F1000Research 5:2122.** [PMID:27909575](https://pubmed.ncbi.nlm.nih.gov/27909575)
  Original scran paper; SCE was introduced as the core data structure and validated
  on multiple 10x Genomics and Smart-seq2 datasets.


## Common Errors & Troubleshooting

### `Error in .check_sce: number of columns in assay != nrow(colData)`

**Cause:** Assay matrix and colData have different sample orders

**Fix:** Ensure colnames(counts_mat) matches rownames(colData)

## Additional Notes from Official Documentation

*Extracted from the SingleCellExperiment Bioconductor vignette(s)*

### 1 Motivation


The SingleCellExperiment class is a lightweight Bioconductor container for storing and manipulating single-cell genomics data.
It extends the RangedSummarizedExperiment class and follows similar conventions,
i.e., rows should represent features (genes, transcripts, genomic regions) and columns should represent cells.
It provides methods for storing dimensionality reduction results and data for alternative feature sets (e.g., synthetic spike-in transcripts, antibody-derived tags).
It is the central data structure for Bioconductor single-cell packages like scater and scran .

### 2 Creating SingleCellExperiment instances


SingleCellExperiment objects can be created via the constructor of the same name.
For example, if we have a count matrix in counts , we can simply call:
In practice, it is often more useful to name the assay by passing in a named list:
It is similarly easy to set the column and row metadata by passing values to the appropriate arguments.
We will not go into much detail here as most of this is covered by the SummarizedExperiment documentation,
but to give an example:
Alternatively, we can construct a SingleCellExperiment by coercing an existing (Ranged)SummarizedExperiment object:
Any operation that can be applied to a RangedSummarizedExperiment is also applicable to any instance of a SingleCellExperiment .
This includes access to assay data via assay() , column metadata with colData() , a

```r
library(SingleCellExperiment)
counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
sce <- SingleCellExperiment(counts)
sce
```

```r
## class: SingleCellExperiment 
## dim: 10 10 
## metadata(0):
## assays(1): ''
## rownames: NULL
## rowData names(0):
## colnames: NULL
## colData names(0):
## reducedDimNames(0):
## mainExpName: NULL
## altExpNames(0):
```

### 3 Adding low-dimensional representations


We compute log-transformed normalized expression values from the count matrix.
(We note that many of these steps can be performed as one-liners from the scater package,
but we will show them here in full to demonstrate the capabilities of the SingleCellExperiment class.)
We obtain the PCA and t-SNE representations of the data and add them to the object with the reducedDims()<- method.
Alternatively, we can representations one at a time with the reducedDim()<- method (note the missing s ).
The coordinates for all representations can be retrieved from a SingleCellExperiment en masse with reducedDims() or one at a time by name/index with reducedDim() .
Each row of the coordinate matrix is assumed to correspond to a cell while each column represents a dimension.
Any subsetting by column of sc

```r
counts <- assay(sce, "tophat_counts")
libsizes <- colSums(counts)
size.factors <- libsizes/mean(libsizes)
logcounts(sce) <- log2(t(t(counts)/size.factors) + 1)
assayNames(sce)
```

```r
## [1] "tophat_counts" "logcounts"
```

### 4 Convenient access to named assays


In the SingleCellExperiment , users can assign arbitrary names to entries of assays .
To assist interoperability between packages, we provide some suggestions for what the names should be for particular types of data:
counts : Raw count data, e.g., number of reads or transcripts for a particular gene.
normcounts : Normalized values on the same scale as the original counts.
For example, counts divided by cell-specific size factors that are centred at unity.
logcounts : Log-transformed counts or count-like values.
In most cases, this will be defined as log-transformed normcounts , e.g., using log base 2 and a pseudo-count of 1.
cpm : Counts-per-million.
This is the read count for each gene in each cell, divided by the library size of each cell in millions.
tpm : Transcripts-per-million.
Thi

```r
counts(sce) <- assay(sce, "tophat_counts")
sce
```

```r
## class: SingleCellExperiment 
## dim: 20816 379 
## metadata(2): SuppInfo which_qc
## assays(3): tophat_counts logcounts counts
## rownames(20816): 0610007P14Rik 0610009B22Rik ... Zzef1 Zzz3
## rowData names(0):
## colnames(379): SRR2140028 SRR2140022 ... SRR2139341 SRR2139336
## colData names(22): NREADS NALIGNED ... Animal.ID passes_qc_checks_s
## reducedDimNames(2): PCA TSNE
## mainExpName: endogenous
## altExpNames(1): ERCC
```

### 5 Adding alternative feature sets


Many scRNA-seq experiments contain sequencing data for multiple feature types beyond the endogenous genes:
Externally added spike-in transcripts for plate-based experiments.
Antibody tags for CITE-seq experiments.
CRISPR tags for CRISPR-seq experiments.
Allele information for experiments involving multiple genotypes.
Such features can be stored inside the SingleCellExperiment via the concept of âalternative Experimentsâ.
These are nested SummarizedExperiment instances that are guaranteed to have the same number and ordering of columns as the main SingleCellExperiment itself.
Data for endogenous genes and other features can thus be kept separate - which is often desirable as they need to be processed differently - while still retaining the synchronization of operations on a single obje

```r
altExp(sce)
```

```r
## class: SingleCellExperiment 
## dim: 92 379 
## metadata(0):
## assays(4): tophat_counts cufflinks_fpkm rsem_counts rsem_tpm
## rownames(92): ERCC-00002 ERCC-00003 ... ERCC-00170 ERCC-00171
## rowData names(0):
## colnames(379): SRR2140028 SRR2140022 ... SRR2139341 SRR2139336
## colData names(0):
## reducedDimNames(0):
## mainExpName: NULL
## altExpNames(0):
```

### 6 Storing row or column pairings


A common procedure in single-cell analyses is to identify relationships between pairs of cells,
e.g., to construct a nearest-neighbor graph or to mark putative physical interactions between cells.
We can capture this information in the SingleCellExperiment class with the colPairs() functionality.
To demonstrate, say we have 100 relationships between the cells in sce , characterized by some distance measure:
We store this in the SingleCellExperiment as a SelfHits object using the value metadata field to hold our data.
This is easily extracted as a SelfHits or, for logical or numeric data, as a sparse matrix from Matrix .
A particularly useful feature is that the indices of the interacting cells are automatically remapped when sce is subsetted.
This ensures that the pairings are always sync

```r
cell1 <- sample(ncol(sce), 100, replace=TRUE)
cell2 <- sample(ncol(sce), 100, replace=TRUE)
distance <- runif(100)
```

```r
colPair(sce, "relationships") <- SelfHits(
    cell1, cell2, nnode=ncol(sce), value=distance)
colPair(sce, "relationships")
```

### 7 Additional metadata fields


The SingleCellExperiment class provides the sizeFactors() getter and setter methods,
to set and retrieve size factors from the colData of the object.
Each size factor represents the scaling factor applied to a cell to normalize expression values prior to downstream comparisons,
e.g., to remove the effects of differences in library size and other cell-specific biases.
These methods are primarily intended for programmatic use in functions implementing normalization methods,
but users can also directly call this to inspect or define the size factors for their analysis.
The colLabels() getter and setters methods allow applications to set and retrieve cell labels from the colData .
These labels can be derived from cluster annotations, assigned by classification algorithms, etc.
and are often u

```r
# Making up some size factors and storing them:
sizeFactors(sce) <- 2^rnorm(ncol(sce))
summary(sizeFactors(sce))
```

```r
##    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
##  0.1336  0.6761  1.0082  1.2365  1.5034  9.8244
```

### 1 Introduction


By design, the scope of this package is limited to defining the SingleCellExperiment class and some minimal getter and setter methods.
For this reason, we leave it to developers of specialized packages to provide more advanced methods for the SingleCellExperiment class.
If packages define their own data structure, it is their responsibility to provide coercion methods to/from their classes to SingleCellExperiment .
For developers, the use of SingleCellExperiment objects within package functions is mostly the same as the use of instances of the base SummarizedExperiment class.
The only exceptions involve direct access to the internal fields of the SingleCellExperiment definition.
Manipulation of these internal fields in other packages is possible but requires some caution, as we shall disc

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/SingleCellExperiment.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/SingleCellExperiment.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Amezquita RA et al. (2020). Nature Methods, 17:137-145.

---
