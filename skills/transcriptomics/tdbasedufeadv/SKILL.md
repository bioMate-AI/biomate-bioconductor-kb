---
name: bioconductor-tdbasedufeadv
description: This is an advanced version of TDbasedUFE, which is a comprehensive package to perform Tensor decomposition based unsupervised feature extraction. In contrast to TDbasedUFE which can perform simple the feature selection and the multiomics analyses, this package can perform more complicated and advanced features, but they are not so popularly required. Only users who require more specific features can make use of its functionality.
when_to_use: Use when: Enrichment; Explanation of TDbasedUFEadv; How to use TDbasedUFEadv; Single-cell RNA-seq analysis (TDbasedUFEadv). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# TDbasedUFEadv

## Workflows

### Standard Workflow

Integrate two omics datasets sharing the same features using memory-efficient SVD with partial summation.

```r
library(TDbasedUFEadv)
library(RTCGA.rnaseq)

# Prepare drug and disease expression datasets
Cancer_cell_lines <- list(ACC.rnaseq, BLCA.rnaseq, BRCA.rnaseq, CESC.rnaseq)
Drug_and_Disease <- prepareexpDrugandDisease(Cancer_cell_lines)
expDrug <- Drug_and_Disease$expDrug
expDisease <- Drug_and_Disease$expDisease

# Compute SVD on the two matrices
SVD <- computeSVD(exprs(expDrug), exprs(expDisease))

# Generate the matrix product and prepare the tensor
Z <- t(exprs(expDrug)) %*% exprs(expDisease)
sample <- outer(
  colnames(expDrug),
  colnames(expDisease),
  function(x, y) { paste(x, y) }
)
Z <- PrepareSummarizedExperimentTensor(
  sample = sample,
  feature = rownames(expDrug),
  value = Z
)
```
*Inputs are two expression matrices sharing features; output is a SummarizedExperiment-like tensor and SVD results.*

### Multi Omics Sharing Features

Integrate multiple omics datasets sharing the same features but having different samples using projection-based SVD and HOSVD.

```r
library(TDbasedUFEadv)
library(RTCGA.rnaseq)
library(RTCGA.clinical)

# Prepare a list of matrices sharing features
Multi <- list(
  BLCA.rnaseq[seq_len(100), 1 + seq_len(1000)],
  BRCA.rnaseq[seq_len(100), 1 + seq_len(1000)],
  CESC.rnaseq[seq_len(100), 1 + seq_len(1000)],
  COAD.rnaseq[seq_len(100), 1 + seq_len(1000)]
)

# Prepare a tensor from the list of matrices
Z <- prepareTensorfromList(Multi, 10L)

# Permute the tensor modes to align features
Z <- aperm(Z, c(2, 1, 3))

# Wrap the tensor using PrepareSummarizedExperimentTensor
Clinical <- list(BLCA.clinical, BRCA.clinical, CESC.clinical, COAD.clinical)
Multi_sample <- list(
  BLCA.rnaseq[seq_len(100), 1, drop = FALSE],
  BRCA.rnaseq[seq_len(100), 1, drop = FALSE],
  CESC.rnaseq[seq_len(100), 1, drop = FALSE],
  COAD.rnaseq[seq_len(100), 1, drop = FALSE]
)
ID_column_of_Multi_sample <- c(770, 1482, 773, 791)
ID_column_of_Clinical <- c(20, 20, 12, 14)

Z <- PrepareSummarizedExperimentTensor(
  feature = colnames(ACC.rnaseq)[1 + seq_len(1000)],
  sample = array("", 1),
  value = Z,
  sampleData = prepareCondTCGA(
    Multi_sample,
    Clinical,
    ID_column_of_Multi_sample,
    ID_column_of_Clinical
  )
)

# Compute HOSVD
HOSVD <- computeHosvd(Z)

# Select features using selectFeatureProj in batch mode
cond <- attr(Z, "sampleData")
index <- selectFeatureProj(HOSVD, Multi, cond, de = 1e-3, input_all = 3)

# Extract and display selected features
head(tableFeatures(Z, index))
```
*Inputs are a list of matrices sharing features and clinical metadata; output is a table of selected features with p-values.*

### Multi Omics Sharing Samples

Integrate multiple omics datasets sharing the same samples using projection-based SVD and HOSVD.

```r
library(TDbasedUFEadv)

# Prepare a tensor from the list of matrices and wrap in a SummarizedExperiment-like object
# Z <- PrepareSummarizedExperimentTensor(sample = sample, feature = feature, value = value)

# Compute HOSVD
# HOSVD <- computeHosvd(Z)

# Select features across individual profiles
# index <- selectFeature(HOSVD, input_all, de = 0.05)

# Extract, print, and save selected features
# head(tableFeatures(Z, index))
```
*Inputs are multi-omics matrices sharing samples; output is a table of selected features.*

## When to Use
- Unsupervised feature extraction (e.g., gene selection) from multi-omics datasets where either features (genes) or samples are shared.
- When dealing with a small number of samples associated with a large number of features (common in genomics).
- Evaluating selected genes via enrichment analysis using tools like `enrichR::enrichr`, `STRINGdb::STRINGdb`, or `DOSE::enrichDGN`.

## When NOT to Use
- For supervised differential expression analysis where group labels are strictly used to guide the mathematical decomposition; use `DESeq2` or `limma` instead.
- When you prefer a fully automated, non-interactive pipeline without manual/interactive selection of singular value vectors; use standard `SVD` or `HOSVD` packages directly.

## Data Requirements
- Input data should be matrix-like (e.g., gene expression matrices from `RTCGA.rnaseq` like `BLCA.rnaseq`).
- For feature-sharing multi-omics, a list of matrices (e.g., `Multi`) where rows represent features and columns represent samples.
- Metadata/clinical data (e.g., `BLCA.clinical`) to construct condition vectors for selecting singular value vectors.

## Key Parameters
- **de** (1e-3): Standard deviation threshold for feature selection in `selectFeatureProj` or `selectFeature`.
- **input_all**: Vector of selected singular value vectors in `selectSingularValueVectorLarge` or `selectFeatureProj`.

## Best Practices
- Master the basic `TDbasedUFE` package workflows before moving to the advanced features of `TDbasedUFEadv`.
- Use memory-efficient SVD with partial summation (`computeSVD`) when the number of features is too large to construct a full tensor.
- Verify the success of singular value vector selection interactively using histograms and standard deviation optimization via `selectSingularValueVectorLarge`.
- Perform downstream enrichment analysis on selected genes using `enrichR::enrichr` or `STRINGdb::STRINGdb` to biologically validate the unsupervised feature selection.

## Common Pitfalls
- **Out of memory errors**: Attempting to apply `computeHosvd` on a full tensor with too many features. *Fix*: Use `computeSVD` with partial summation to reduce memory requirements.
- **Incorrect tensor permutation**: Forgetting to align features across datasets. *Fix*: Use `aperm` to permute the tensor modes appropriately before wrapping with `PrepareSummarizedExperimentTensor`.

## Alternatives
- `DESeq2`: For supervised differential expression analysis.
- `limma`: For linear modeling of gene expression data.
- `TDbasedUFE`: For simpler, standard unsupervised feature extraction workflows.

## Citations
- Taguchi, Y-H. 2020. Unsupervised Feature Extraction Applied to Bioinformatics. Springer International Publishing. https://doi.org/10.1007/978-3-030-22456-1
- Taguchi, Y-H. 2023. TDbasedUFE: Tensor Decomposition Based Unsupervised Feature Extraction.

## References
- Homepage: bioconductor.org/packages/TDbasedUFEadv
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/TDbasedUFEadv/inst/doc/Enrichment.html
