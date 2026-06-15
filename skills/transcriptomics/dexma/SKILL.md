---
name: bioconductor-dexma
description: performing all the steps of gene expression meta-analysis considering the possible existence of missing genes. It provides the necessary functions to be able to perform the different methods of gene expression meta-analysis. In addition, it contains functions to apply quality controls, download GEO datasets and show graphical representations of the results.
when_to_use: Use when: Differential Expression Meta-Analysis with DExMA package; Differential expression analysis (DExMA); Quality control and preprocessing (DExMA). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# DExMA

## Workflows

### Standard Workflow

Perform a complete gene expression meta-analysis workflow including data preparation, annotation harmonization, log transformation, heterogeneity testing, optional imputation, meta-analysis, and heatmap visualization.

```r
library(DExMA)

# Create meta-analysis object
phenoGroups <- c("condition", "condition", "state", "state")
phenoCases <- list(Study1 = "Diseased", Study2 = c("Diseased", "ill"),
                   Study3 = "Diseased", Study4 = "ill")
phenoControls <- list(Study1 = "Healthy", Study2 = c("Healthy", "control"),
                      Study3 = "Healthy", Study4 = "control")

newObjectMA <- createObjectMA(listEX = listMatrixEX,
                              listPheno = listPhenodatas,
                              namePheno = phenoGroups,
                              expGroups = phenoCases, 
                              refGroups = phenoControls)

# Harmonize gene IDs
newObjectMA <- allSameID(newObjectMA, finalID = "GeneSymbol", organism = "Homo sapiens")

# Log-transform data
newObjectMA <- dataLog(newObjectMA)

# Test for heterogeneity
heterogeneityTest(newObjectMA)

# Perform meta-analysis
resultsMA <- metaAnalysisDE(newObjectMA, typeMethod = "REM", missAllow = 0.3, proportionData = 0.50)

# Visualize results
makeHeatmap(objectMA = newObjectMA, resMA = resultsMA, scaling = "zscor", 
            regulation = "all", numSig = 40, fdrSig = 0.05, logFCSig = 1.5, show_rownames = TRUE)
```
*Inputs are lists of expression matrices and phenodata; output is a meta-analysis results table and a heatmap of significant genes.*

### Batch Effect Correction

Detect and remove batch effects from individual datasets and calculate individual study effect sizes or p-values.

```r
library(DExMA)

# Remove batch effects
corrected_study2 <- batchRemove(listMatrixEX$Study2, listPhenodatas$Study2, 
                                formula = ~gender+race, 
                                mainCov = "race", nameGroup = "condition")

# Calculate individual study effect sizes
effects <- calculateES(newObjectMA)

# Calculate individual study p-values
pvalues <- pvalueIndAnalysis(newObjectMA)
```
*Inputs are expression matrices and phenodata; outputs are batch-corrected expression matrices, individual study effect sizes, and individual p-values.*

### Download Geo Data

Download public microarray datasets from NCBI GEO for meta-analysis.

```r
library(DExMA)

# Download GEO datasets
GEOobjects <- c("GSE4588", "GSE10325")
# dataGEO <- downloadGEOData(GEOobjects)
```
*Input is a vector of GEO accession IDs; output is a list of downloaded GEO datasets.*

## When to Use
- Performing gene expression meta-analysis across multiple microarray or RNA-Seq datasets using `metaAnalysisDE`.
- Harmonizing heterogeneous gene identifiers across different studies to a common standard (e.g., Official Gene Symbol) using `allSameID`.
- Imputing missing gene expression values across studies using the KNN method via `missGenesImput`.
- Removing batch effects from individual expression matrices using `batchRemove`.

## When NOT to Use
- For single-dataset differential expression analysis, use `limma`, `DESeq2`, or `edgeR` directly because `DExMA` is designed for multi-study meta-analysis.
- For raw RNA-Seq read alignment or quantification, use packages like `Rsubread` because `DExMA` requires pre-normalized expression matrices.

## Data Requirements
- **Input Format**: A list of nested lists (an `objectMA` created via `createObjectMA` or `elementObjectMA`).
- **Structure**: Each study must contain an expression matrix (genes in rows, samples in columns) and a binary vector (0 for reference/control, 1 for experimental/cases).
- **Normalization**: Expression data should be normalized and log-transformed (can use `dataLog` for log-transformation).

## Key Parameters
- **listEX**: A list of expression dataframes, matrices, or `ExpressionSet` objects.
- **listPheno**: A list of phenodata dataframes.
- **finalID**: The target gene ID type (e.g., `"GeneSymbol"`) in `allSameID`.
- **organism**: The organism name (e.g., `"Homo sapiens"`) in `allSameID`.
- **typeMethod**: The meta-analysis method (e.g., `"REM"` for random effects model, `"maxP"` for p-value combination) in `metaAnalysisDE`.
- **missAllow** (`0.3`): The maximum proportion of missing values allowed for a gene.
- **proportionData** (`0.50`): The minimum proportion of datasets in which a gene must be present.

## Best Practices
- Harmonize all dataset gene IDs to a common annotation (e.g., Official Gene Symbol) using `allSameID` before performing meta-analysis.
- Apply `dataLog` to ensure all datasets are in log scale.
- Assess study heterogeneity using `heterogeneityTest` to decide between fixed-effects and random-effects models.
- Use `missGenesImput` to impute missing genes if you want to avoid discarding genes that are unmeasured in a subset of studies.

## Common Pitfalls
- **Mixing log-transformed and non-log-transformed datasets**: Use `dataLog` to automatically detect and log-transform non-log datasets.
- **Discarding too many genes due to missingness**: Adjust `missAllow` and `proportionData` in `metaAnalysisDE`, or use `missGenesImput` to impute missing values.
- **Inconsistent group definitions across studies**: Carefully construct `phenoCases` and `phenoControls` lists when calling `createObjectMA`.

## Alternatives
- `limma` for single-study differential expression and batch correction.
- `swamp` for principal component analysis and batch effect identification (e.g., `prince`).
- `Biobase` for managing `ExpressionSet` objects.

## Citations
- Villatoro-García, J. A., & Carmona-Sáez, P. (2026). Differential Expression Meta-Analysis with DExMA package.

## References
- Homepage: bioconductor.org/packages/DExMA
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/DExMA/inst/doc/DExMA.html
