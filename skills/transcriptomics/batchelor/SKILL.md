---
name: bioconductor-batchelor
description: Implements a variety of methods for batch correction of single-cell (RNA sequencing) data. This includes methods based on detecting mutually nearest neighbors, as well as several efficient variants of linear regression of the log-expression
when_to_use: Use when: Integrate scRNA-seq data from multiple batches/studies; Correct for technical batch effects while preserving biology; Merge datasets for joint clustering and visualization
user-invocable: false
---

# batchelor — Comprehensive Skill Guide

> **Domain:** Single-cell / batch correction
> **Bioconductor:** [batchelor](https://bioconductor.org/packages/release/bioc/html/batchelor.html)
> **Paper:** Haghverdi L et al. (2018). Nature Biotechnology, 36:421-427.

Batch correction for single-cell RNA-seq using fastMNN, regressBatches, and other methods. Part of the OSCA workflow for multi-batch integration.

## When to Use

- Integrate scRNA-seq data from multiple batches/studies
- Correct for technical batch effects while preserving biology
- Merge datasets for joint clustering and visualization

**Alternatives:** `Harmony (harmonypy/harmony)`, `Seurat CCA/RPCA integration`, `scVI (Python)`

## Do NOT Use When

- Bulk RNA-seq batch correction — use limma::removeBatchEffect or ComBat.
- Data with no common cell types across batches — MNN requires shared biology.
- Differential expression with corrected values — always use uncorrected counts + batch covariate for DE.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | SingleCellExperiment objects per batch (normalized, HVG-selected) |
| **Min Cells** | ≥100 cells per batch for reliable MNN detection |
| **Prerequisite** | Normalize each batch separately before integration |
| **Shared Biology** | Batches must share common cell populations (MNN assumption) |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("batchelor")
library(batchelor)
```

## Workflows

### Multi-Batch Integration with fastMNN
*Integrate scRNA-seq data from multiple batches using mutual nearest neighbours*

#### Prepare per-batch SCEs

```r
library(batchelor)
library(scran)
# sce1, sce2 are already normalized SCE objects
# Find HVGs per batch
dec1 <- modelGeneVar(sce1)
dec2 <- modelGeneVar(sce2)
combined_dec <- combineVar(dec1, dec2)
hvgs <- getTopHVGs(combined_dec, n=3000)
```

#### Run fastMNN

```r
mnn_out <- fastMNN(sce1, sce2,
                   subset.row = hvgs,
                   d = 50,          # dimensions to use
                   k = 20,          # nearest neighbours
                   BPPARAM = BiocParallel::SerialParam())

# Inspect merge diagnostics
metadata(mnn_out)$merge.info
```

#### Add corrected embedding to original SCE

```r
# Corrected PCA embedding
reducedDim(sce_combined, "corrected") <- reducedDim(mnn_out, "corrected")

# Cluster in corrected space
library(bluster)
clusters <- clusterRows(reducedDim(mnn_out, "corrected"),
                        NNGraphParam(k=20))
mnn_out$cluster <- clusters
```

#### UMAP on corrected space

```r
library(scater)
mnn_out <- runUMAP(mnn_out, dimred="corrected")
plotReducedDim(mnn_out, "UMAP", colour_by="batch")
plotReducedDim(mnn_out, "UMAP", colour_by="cluster")
```

## Key Functions & Parameters

### `fastMNN()()`

Fast mutual nearest neighbours batch correction

| Parameter | Description |
|-----------|-------------|
| `...` | list of SCE objects or a single SCE with `batch` argument |
| `batch` | factor of batch labels (if single SCE provided) |
| `k` | number of nearest neighbours (default 20) |
| `d` | number of PCs to use (default 50) |
| `auto.merge` | automatically choose merge order (default TRUE) |
| `BPPARAM` | BiocParallel for parallelization |

### `regressBatches()()`

Linear regression batch correction (rescaling approach)

| Parameter | Description |
|-----------|-------------|
| `...` | list of SCE objects |
| `batch` | batch labels |

### `correctExperiments()()`

Wrapper to correct and combine multiple experiments


## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Mutual nearest neighbours (MNNs) between batches represent the same cell type.
- The batch effect is orthogonal to biological variation (rotation assumption).
- Most cells are not batch-specific (shared biology required for MNN pairs).

## Result Interpretation

- Corrected embedding (`reducedDim(out, 'corrected')`): use for UMAP/clustering ONLY.
- Check `metadata(out)$merge.info$lost.var`: fraction of variance lost per merge step; < 2% is typical.
- After integration: cluster cells jointly, then test DE using ORIGINAL counts + batch covariate.
- If batches completely separate in UMAP after correction: check for confounded batch/biology.

## Best Practices

- Always use HVGs (highly variable genes) as input to fastMNN, not all genes.
- Preserve the uncorrected counts for DE analysis; only use corrected values for dimensionality reduction and clustering.
- Check `metadata(mnn.out)$merge.info` to inspect merge order and % variance lost.
- Use `auto.merge=TRUE` to let batchelor choose the merge order (better for >2 batches).
- After fastMNN, `reducedDim(mnn.out, 'corrected')` contains the batch-corrected PCA space for UMAP/clustering.
- Do NOT use the corrected matrix for differential expression — use the original counts with batch as a covariate instead.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `Harmony` | You have many batches (>10); you want fast PCA-space correction. | You want Bioconductor-native integration without Python dependencies. |
| `scVI / scANVI` | You have very large datasets (>100K cells); you want probabilistic latent space. | You want simpler, interpretable methods without neural networks. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Haghverdi L et al. (2018). Nat Biotechnol 36:421.** [PMID:30911987](https://pubmed.ncbi.nlm.nih.gov/30911987)  
  fastMNN scales to millions of cells and performs comparably to slower MNN methods.

- **Luecken MD et al. (2022). Nature Methods 19:41.** [PMID:34535456](https://pubmed.ncbi.nlm.nih.gov/34535456)  
  scANVI and Harmony often outperform fastMNN on large cross-study integration benchmarks.

## Common Errors & Troubleshooting

### `Error: all genes must be the same across batches`

**Cause:** Different gene sets across batches

**Fix:** Intersect genes: `common <- Reduce(intersect, lapply(batches, rownames))`

## Additional Notes from Official Documentation

*Extracted from the batchelor Bioconductor vignette(s)*

### 1 Overview


The batchelor package provides the batchCorrect() generic that dispatches on its PARAM argument.
Users writing code using batchCorrect() can easily change one method for another by simply modifying the class of object supplied as PARAM .
For example:
Developers of other packages can extend this further by adding their batch correction methods to this dispatch system.
This improves interoperability across packages by allowing users to easily experiment with different methods.

```r
B1 <- matrix(rnorm(10000), ncol=50) # Batch 1 
B2 <- matrix(rnorm(10000), ncol=50) # Batch 2

# Switching easily between batch correction methods.
m.out <- batchCorrect(B1, B2, PARAM=ClassicMnnParam())
f.out <- batchCorrect(B1, B2, PARAM=FastMnnParam(d=20))
r.out <- batchCorrect(B1, B2, PARAM=RescaleParam(pseudo.count=0))
```

### 2 Setting up


You will need to Imports: batchelor, methods in your DESCRIPTION file.
You will also need to add import(methods) , importFrom(batchelor, "batchCorrect") and importClassesFrom(batchelor, "BatchelorParam") in your NAMESPACE file.
Obviously, you will also need to have a function that implements your batch correction method.
For demonstration purposes, we will use an identity function that simply returns the input values 1 1 1 Not a very good correction, but thatâs not the point right now. .
This is implemented like so:

```r
noCorrect <- function(...) 
# Takes a set of batches and returns them without modification. 
{
   do.call(cbind, list(...)) 
}
```

### 3 Deriving a BatchelorParam subclass


We need to define a new BatchelorParam subclass that instructs the batchCorrect() generic to dispatch to our new method.
This is most easily done like so:
Note that BatchelorParam itself is derived from a SimpleList and can be modified with standard list operators like $ .
If no parameters are set, the default values in the function will be used 2 2 2 Here there are none in noCorrect() , but presumably your function is more complex than that. .
Additional slots can be specified in the class definition if there are important parameters that need to be manually specified by the user.

```r
NothingParam <- setClass("NothingParam", contains="BatchelorParam")
```

```r
nothing <- NothingParam()
nothing
```

### 4.1 Input


The batchCorrect() generic looks like this:
Any implemented method must accept one or more matrix-like objects containing single-cell gene expression matrices in ... .
Rows are assumed to be genes and columns are assumed to be cells.
If only one object is supplied, batch must be specified to indicate the batches to which each cell belongs.
Alternatively, one or more SingleCellExperiment objects can be supplied, containing the gene expression matrix in the assay.type assay.
These should not be mixed with matrix-like objects, i.e., if one object is a SingleCellExperiment , all objects should be SingleCellExperiment s.
The subset.row= argument specifies a subset of genes on which to perform the correction.
The correct.all= argument specifies whether corrected values should be returned for al

```r
batchCorrect
```

```r
## standardGeneric for "batchCorrect" defined from package "batchelor"
## 
## function (..., batch = NULL, restrict = NULL, subset.row = NULL, 
##     correct.all = FALSE, assay.type = NULL, PARAM) 
## standardGeneric("batchCorrect")
## <bytecode: 0x5a4ebd54b858>
## <environment: 0x5a4ebd55e940>
## Methods may be defined for arguments: PARAM
## Use  showMethods(batchCorrect)  for currently available ones.
```

### 4.2 Output


Any implemented method must return a SingleCellExperiment where the first assay contains corrected gene expression values for all genes.
Corrected values should be returned for all genes if correct.all=TRUE or subset.row=NULL .
If correct.all=FALSE and subset.row is not NULL , values should only be returned for the selected genes.
Cells should be reported in the same order that they are supplied in ... .
In cases with multiple batches, the cell identities are simply concatenated from successive objects in their specified order,
i.e., all cells from the first object (in their provided order), then all cells from the second object, and so on.
If there is only a single batch, the order of cells in that batch should be preserved.
The output object should have row names equal to the row names 

### 4.3 Demonstration


Finally, we define a method that calls our noCorrect function while satisfying all of the above input/output requirements.
To be clear, it is not mandatory to lay out the code as shown below; this is simply one way that all the requirements can be satisfied.
We have used some internal batchelor functions for brevity - please contact us if you find these useful and want them to be exported.
And it works 5 5 5 In a strictly programming sense, as the method itself does no correction at all. :
Remember to export both the new method and the NothingParam class and constructor.

```r
setMethod("batchCorrect", "NothingParam", function(..., batch = NULL, 
    restrict=NULL, subset.row = NULL, correct.all = FALSE, 
    assay.type = "logcounts", PARAM) 
{
    batches <- list(...)
    checkBatchConsistency(batches)

    # Pulling out information from the SCE objects.        
    is.sce <- checkIfSCE(batches)
    if (any(is.sce)) {
        batches[is.sce] <- lapply(batches[is.sce], assay, i=assay.type)
    }

    # Subsetting by 'batch', if only one object is supplied. 
    do.split <- length(batches)==1L
    if (do.split) {
        divided <- divideIntoBatches(batches[[1]], batch=batch, restrict=restrict)
        batches <- divided$batches
        restrict <- divided$restricted
    } 

    # Subsetting by row.
    # This is a per-gene "method", so correct.all=TRUE will ignore subset.row.
    # More complex methods will need to handle this differently.
    if (correct.all) {
        subset.row <- NULL
    } else if (!is.null(subset.row)) {
        subset.row <- normalizeSingleBracketSubscript(originals[[1]], subset.row)
        batches <- lapply(batches, "[", i=subset.row, , drop=FALSE)
    }

    # Don't really need to consider restrict!=NULL here, as this function
    # doesn't do anything with the cells anyway.
    output <- do.call(noCorrect, batches)

    # Reordering the output for correctness if it was previously split.
    if (do.split) {
        d.reo <- divided$reorder
        output <- output[,d.reo,drop=FALSE]
    }

    ncells.per.batch <- vapply(batches, FUN=ncol, FUN.VALUE=0L)
    batch.names <- names(batches)
    if (is.null(batch.names)) {
        batch.names <- seq_along(batches)
    }
    
    SingleCellExperiment(list(corrected=output), 
        colData=DataFrame(batch=rep(batch.names, ncells.per.batch)))
})
```

```r
n.out <- batchCorrect(B1, B2, PARAM=NothingParam())
n.out
```

### 1 Introduction


Batch effects refer to differences between data sets generated at different times or in different laboratories.
These often occur due to uncontrolled variability in experimental factors, e.g., reagent quality, operator skill, atmospheric ozone levels.
The presence of batch effects can interfere with downstream analyses if they are not explicitly modelled.
For example, differential expression analyses typically use a blocking factor to absorb any batch-to-batch differences.
For single-cell RNA sequencing (scRNA-seq) data analyses, explicit modelling of the batch effect is less relevant.
Manny common downstream procedures for exploratory data analysis are not model-based, including clustering and visualization.
It is more generally useful to have methods that can remove batch effects to cre

### 2 Setting up demonstration data


To demonstrate, we will use two brain data sets (Tasic et al. 2016 ; Zeisel et al. 2015 ) from the scRNAseq package.
A more thorough explanation of each of these steps is available in the book .
We apply some quick-and-dirty quality control to both datasets,
using the outlier detection strategy from the scuttle package.
Some preprocessing is required to render these two datasets comparable.
We subset to the common subset of genes:
We compute log-normalized expression values using library size-derived size factors for simplicity.
(More complex size factor calculation methods are available in the scran package.)
Finally, we identify the top 5000 genes with the largest biological components of their variance.
We will use these for all high-dimensional procedures such as PCA and nearest-neigh

```r
library(scRNAseq)
sce1 <- ZeiselBrainData()
sce1
```

```r
## class: SingleCellExperiment 
## dim: 20006 3005 
## metadata(0):
## assays(1): counts
## rownames(20006): Tspan12 Tshz1 ... mt-Rnr1 mt-Nd4l
## rowData names(1): featureType
## colnames(3005): 1772071015_C02 1772071017_G12 ... 1772066098_A12
##   1772058148_F03
## colData names(9): tissue group # ... level1class level2class
## reducedDimNames(0):
## mainExpName: gene
## altExpNames(2): repeat ERCC
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/batchelor.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/batchelor.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Haghverdi L et al. (2018). Nature Biotechnology, 36:421-427.

---
