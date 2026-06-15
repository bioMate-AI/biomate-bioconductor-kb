---
name: bioconductor-statial
description: Statial is a suite of functions for identifying changes in cell state. The functionality provided by Statial provides robust quantification of cell type localisation which are invariant to changes in tissue structure. In addition to this Statial uncovers changes in marker expression associated with varying levels of localisation. These features can be used to explore how the structure and function of different cell types may be altered by the agents they are surrounded with.
when_to_use: Use when: Statial is a suite of functions for identifying changes in cell state; biologicalHierarchy using unique; clusteringHierarchy using getClusterTree; image6 using assay, colData; p53Relationship using Kontextual; kontextCurve using kontextCurve, kontextPlot. Not for: Requires R ≥ 4.1.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# Statial

## Workflows

### Standard Workflow

Quantify context-aware spatial relationships between cell types using hierarchies and associate them with survival outcomes.

```r
library(Statial)
library(spicyR)
library(SingleCellExperiment)
library(survival)
library(treekoR)

data("kerenSCE")

# Define hierarchy
kerenTree <- treekoR::getClusterTree(t(assay(kerenSCE, "intensities")), kerenSCE$cellType, hierarchy_method="hopach", hopach_K = 1)
parentDf <- parentCombinations(all = unique(kerenSCE$cellType), parentList = getParentPhylo(kerenTree))

# Run Kontextual
kerenKontextual <- Kontextual(cells = kerenSCE, parentDf = parentDf, r = 100, cores = 1)

# Prepare matrix and run survival
kerenSCE$event = 1 - kerenSCE$Censored
kerenSCE$survival = Surv(kerenSCE$Survival_days_capped, kerenSCE$event)
kontextMat <- prepMatrix(kerenKontextual)
kontextMat <- kontextMat[unique(kerenSCE$imageID), ]
kontextMat[is.na(kontextMat)] <- 0

survivalResults = spicy(cells = kerenSCE, alternateResult = kontextMat, condition = "survival", weights = TRUE)
```
*Input: A SingleCellExperiment object containing cell coordinates, cell types, and survival data; Output: Survival analysis results associating context-aware spatial relationships with patient outcomes.*

### Continuous Cell State Changes

Identify continuous changes in cell state (marker expression) as a function of spatial proximity to other cell types, correcting for lateral marker spillover.

```r
library(Statial)
library(SingleCellExperiment)

data("kerenSCE")

# Calculate spatial distances and abundances
kerenSCE <- getDistances(kerenSCE, maxDist = 200, nCores = 1)
kerenSCE <- getAbundances(kerenSCE, r = 200, nCores = 1)

# Calculate continuous state changes for a single image
stateChanges <- calcStateChanges(cells = kerenSCE, type = "distances", image = "6", from = "Keratin_Tumour", to = "Macrophages", marker = "p53", nCores = 1)

# Calculate contamination probabilities and run corrected state changes
kerenSCE <- calcContamination(kerenSCE)
stateChangesCorrected <- calcStateChanges(cells = kerenSCE, type = "distances", nCores = 1, minCells = 100, contamination = TRUE)
```
*Input: A SingleCellExperiment object with cell coordinates and marker intensities; Output: A data frame of state changes corrected for lateral marker spillover.*

## When to Use
- Quantifying context-aware spatial relationships between cell types using `Kontextual` to avoid tissue structure biases.
- Identifying continuous changes in cell state (marker expression) relative to the distance to other cell types using `calcStateChanges`.
- Correcting for lateral marker spillover (contamination) in multiplexed imaging data using `calcContamination`.

## When NOT to Use
- For non-spatial single-cell data, use standard differential expression packages like `scran` or `scater` because `Statial` requires spatial coordinates (`x`, `y`).
- For simple cell-type abundance comparisons without spatial localization or context, use `spicyR` directly.

## Data Requirements
- A `SingleCellExperiment` object containing cell coordinates (`x` and `y` in `colData`), cell type annotations (`cellType`), and marker expression assays.

## Key Parameters
- **r** (100): Radius on which the cell relationship is evaluated in `Kontextual` or `getAbundances`.
- **maxDist** (200): Maximum distance threshold for calculating spatial proximity in `getDistances`.
- **contamination** (TRUE): Logical indicating whether to include contamination probabilities as covariates in `calcStateChanges`.
- **minCells** (100): Minimum number of cells required to perform state change calculations in `calcStateChanges`.
- **cores** (1): Number of cores for parallel processing in `Kontextual`.

## Best Practices
- Define cell type hierarchies using `treekoR::getClusterTree` or biological knowledge to specify appropriate contexts for `Kontextual`.
- Extract pairwise combinations of cell types and their parents using `parentCombinations` before running `Kontextual`.
- Run `calcContamination` to estimate lateral marker spillover probabilities before modeling continuous state changes.

## Common Pitfalls
- Lateral marker spillover (contamination): Adjacent cells wrongly inherit marker expression from neighbors. Fix by setting `contamination = TRUE` in `calcStateChanges` after running `calcContamination`.
- Missing survival data alignment: Ensure the row names of the prepared matrix from `prepMatrix` match the unique image IDs in the `SingleCellExperiment` object before running `spicy`.

## Alternatives
- `spicyR`: For spatial analysis of cell-cell localization without context-aware hierarchy modeling or continuous marker state changes.
- `lisaClust`: For clustering spatial regions rather than modeling continuous cell state changes.

## Citations
- Keren et al. (2018), Cell.

## References
- Homepage: bioconductor.org/packages/Statial
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Statial/inst/doc/Statial.html
