---
name: bioconductor-spotsweeper
description: Spatially-aware quality control (QC) software for both spot-level and artifact-level QC in spot-based spatial transcripomics, such as 10x Visium. These methods calculate local (nearest-neighbors) mean and variance of standard QC metrics (library size, unique genes, and mitochondrial percentage) to identify outliers spot and large technical artifacts. Scales linearly with the number of spots and is designed to be used with 'SpatialExperiment' objects.
when_to_use: Use when: Getting Started with `SpotSweeper`; Quality control and preprocessing (SpotSweeper). Not for: Requires R ≥ 4.3.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# SpotSweeper

## Workflows

### Standard Workflow

Identify and visualize spatially-aware local outliers based on library size, unique genes, and mitochondrial percentage.

```r
library(SpotSweeper)
library(SpatialExperiment)

# 1. Load example data and drop out-of-tissue spots
spe <- STexampleData::Visium_humanDLPFC()
spe <- spe[, spe$in_tissue == 1]

# 2. Calculate QC metrics using scuttle
rownames(spe) <- rowData(spe)$gene_name
is.mito <- rownames(spe)[grepl("^MT-", rownames(spe))]
spe <- scuttle::addPerCellQCMetrics(spe, subsets = list(Mito = is.mito))

# 3. Identify local outliers
spe <- localOutliers(spe, metric = "sum", direction = "lower", log = TRUE)
spe <- localOutliers(spe, metric = "detected", direction = "lower", log = TRUE)
spe <- localOutliers(spe, metric = "subsets_Mito_percent", direction = "higher", log = FALSE)

# 4. Combine all outliers into "local_outliers" column
spe$local_outliers <- as.logical(spe$sum_outliers) | 
                      as.logical(spe$detected_outliers) | 
                      as.logical(spe$subsets_Mito_percent_outliers)

# 5. Visualize local outliers
library(escheR)
plotQCmetrics(spe, metric = "sum_log", outliers = "local_outliers", point_size = 1.1, stroke = 0.75) +
  ggtitle("All Local Outliers")
```
Input: A `SpatialExperiment` object with raw counts. Output: A `SpatialExperiment` object with identified local outliers annotated in `colData`.

### Technical Artifact Detection

Identify and visualize technical artifacts (such as tissue hangnails) using local variance of mitochondrial metrics across multiple neighborhood sizes.

```r
library(SpotSweeper)

# 1. Load data with artifact
data(DLPFC_artifact)
spe <- DLPFC_artifact

# 2. Visualize raw mitochondrial percentage
plotQCmetrics(spe, metric = "expr_chrM_ratio", outliers = NULL, point_size = 1.1) +
  ggtitle("Mitochondrial Percent")

# 3. Run findArtifacts to identify artifacts
spe <- findArtifacts(
  spe, 
  mito_percent = "expr_chrM_ratio", 
  mito_sum = "expr_chrM", 
  n_order = 5, 
  name = "artifact"
)

# 4. Visualize identified artifacts
plotQCmetrics(spe, metric = "expr_chrM_ratio", outliers = "artifact", point_size = 1.1) +
  ggtitle("Hangnail artifact")
```
Input: A `SpatialExperiment` object containing technical artifacts (e.g., tissue hangnails). Output: A `SpatialExperiment` object with artifact spots labeled in `colData`.

## When to Use
- Detecting spot-level local outliers in spatial transcriptomics data based on library size, unique genes, and mitochondrial percentage using `localOutliers()`.
- Identifying large technical artifacts (such as tissue hangnails) using local variance of mitochondrial metrics across multiple neighborhood sizes with `findArtifacts()`.
- Visualizing spatial QC metrics and highlighting outliers or artifacts using `plotQCmetrics()`.

## When NOT to Use
- For non-spatial single-cell RNA-seq data, as the outlier detection methods rely on spatial coordinates and nearest-neighbor structures.
- When spatial coordinate metadata is missing from the input `SpatialExperiment` object.

## Data Requirements
- A `SpatialExperiment` object containing spatial coordinates and count data.
- Pre-calculated QC metrics (such as sum, detected genes, and mitochondrial percentage) in the `colData` of the object (e.g., added via `scuttle::addPerCellQCMetrics()`).

## Key Parameters
- **metric**: The QC metric column name in `colData` evaluated by `localOutliers()`.
- **direction**: The direction of outlier detection (`"lower"` or `"higher"`) in `localOutliers()`.
- **log**: Logical flag indicating whether to log-transform the metric in `localOutliers()`.
- **mito_percent**: Column name for mitochondrial percentage in `findArtifacts()`.
- **mito_sum**: Column name for mitochondrial sum in `findArtifacts()`.
- **n_order**: Neighborhood order size used to calculate local variance in `findArtifacts()`.
- **name**: Column name to store the identified artifact logical vector in `colData`.
- **outliers**: Column name of outliers to highlight in `plotQCmetrics()`.

## Best Practices
- Filter out out-of-tissue spots (e.g., `spe$in_tissue == 1`) before running outlier detection.
- Log-transform highly skewed metrics like library size (`sum`) and unique genes (`detected`) by setting `log = TRUE` in `localOutliers()`.
- Combine individual outlier logical vectors (e.g., `sum_outliers`, `detected_outliers`) into a single logical column for comprehensive visualization.

## Common Pitfalls
- *Including out-of-tissue spots*: Running `localOutliers()` on background spots can skew the local neighborhood statistics; subset the object to `in_tissue == 1` first.
- *Using raw values for skewed metrics*: Failing to log-transform library size or detected genes can lead to poor outlier detection; ensure `log = TRUE` is set for these metrics.

## Alternatives
- `scuttle`: For standard non-spatial single-cell quality control metrics.
- `escheR`: For custom spatial visualization of transcriptomics data.

## Citations
- Tott, M. (2026). Getting Started with SpotSweeper. R Package Vignette.

## References
- Homepage: bioconductor.org/packages/spotsweeper
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/spotsweeper/inst/doc/getting_started.html
