---
name: bioconductor-standr
description: standR is an user-friendly R package providing functions to assist conducting good-practice analysis of Nanostring's GeoMX DSP data. All functions in the package are built based on the SpatialExperiment object, allowing integration into various spatial transcriptomics-related packages from Bioconductor. standR allows data inspection, quality control, normalization, batch correction and evaluation with informative visualizations.
when_to_use: Use when: standR_introduction; Differential expression analysis (standR); Data normalization and preprocessing (standR); Quality control and preprocessing (standR). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# standR

## Workflows

### Standard Workflow

Perform quality control, TMM normalization, and RUV4 batch correction on NanoString GeoMx DSP data.

```r
library(standR)
library(SpatialExperiment)
library(limma)
library(ExperimentHub)

# Load data
eh <- ExperimentHub()
countFile <- eh[["EH7364"]]
sampleAnnoFile <- eh[["EH7365"]]
featureAnnoFile <- eh[["EH7366"]]

spe <- readGeoMx(countFile, sampleAnnoFile, featureAnnoFile = featureAnnoFile, rmNegProbe = TRUE)

# Preprocess and QC
colData(spe)$regions <- paste0(colData(spe)$region,"_",colData(spe)$SegmentLabel) |> 
  (\(.) gsub("_Geometric Segment","",.))() |>
  paste0("_",colData(spe)$pathology) |>
  (\(.) gsub("_NA","_ns",.))()

spe <- addPerROIQC(spe, rm_genes = TRUE)
spe <- spe[,rownames(colData(spe))[colData(spe)$lib_size > 50000]]

# Normalization
colData(spe)$biology <- paste0(colData(spe)$disease_status, "_", colData(spe)$regions)
spe_tmm <- geomxNorm(spe, method = "TMM")

# Batch correction
spe <- findNCGs(spe, batch_name = "SlideName", top_n = 500)
spe_ruv <- geomxBatchCorrection(spe, factors = "biology", NCGs = metadata(spe)$NCGs, k = 5)
```
*Input: Raw NanoString GeoMx DSP count and annotation files from ExperimentHub; Output: A normalized, batch-corrected SpatialExperiment object.*

## When to Use
- Analyzing NanoString GeoMx DSP data using `SpatialExperiment` structures.
- Performing gene-level and ROI-level quality control using `addPerROIQC` and filtering based on library size (`lib_size`).
- Normalizing spatial transcriptomics data with TMM or other methods via `geomxNorm`.
- Removing slide-associated batch effects using `findNCGs` and `geomxBatchCorrection`.

## When NOT to Use
- For single-cell RNA-seq data without spatial coordinates, use standard packages like `scran` or `Seurat` because `standR` is tailored for GeoMx DSP spatial data.
- For spatial datasets requiring continuous cell state modeling across microenvironments, use `Statial` because `standR` focuses on ROI-level profiling and batch correction.

## Data Requirements
- Input counts, sample annotations, and feature annotations loaded into a `SpatialExperiment` object using `readGeoMx`.
- Requires metadata columns such as `lib_size` for ROI filtering, and slide/batch information (e.g., `SlideName`) for batch correction.

## Key Parameters
- **rmNegProbe** (TRUE): Parameter in `readGeoMx` to remove negative probes.
- **rm_genes** (TRUE): Parameter in `addPerROIQC` to remove non-expressed genes.
- **y_threshold** (50000): Library size threshold used in `plotROIQC` to identify low-quality ROIs.
- **method** ("TMM"): Normalization method in `geomxNorm`.
- **batch_name** ("SlideName"): Column name in `colData` representing the batch variable in `findNCGs`.
- **top_n** (500): Number of top least variable genes to select as negative control genes in `findNCGs`.
- **factors** ("biology"): Biological factors to preserve during batch correction in `geomxBatchCorrection`.
- **k** (5): Number of factors of unwanted variation to remove in `geomxBatchCorrection`.

## Best Practices
- Merge region-related annotations (e.g., `region`, `SegmentLabel`, `pathology`) to avoid collinearity before batch correction.
- Run gene-level QC using `addPerROIQC` and visualize removed genes with `plotGeneQC`.
- Perform ROI-level QC using `plotROIQC` to identify low library size or low cell count regions.
- Inspect technical variations using Relative Log Expression (`plotRLExpr`) and Principal Component Analysis (`drawPCA`) before and after normalization.

## Common Pitfalls
- Collinearity in batch correction: Avoid by merging overlapping annotations in `colData` before running `geomxBatchCorrection`.
- Incorrect normalization method: Using `"RPKM"` or `"TPM"` in `geomxNorm` without adding a `genelength` column to `rowData` will fail.
- Low library size ROIs confounding downstream analysis: Filter out low-quality ROIs (e.g., `lib_size > 50000`) before normalization.

## Alternatives
- `edgeR`: For general differential expression and TMM normalization without spatial-specific workflows.
- `limma`: For linear modeling of expression data without built-in GeoMx-specific QC and batch correction.
- `DESeq2`: For alternative normalization and differential testing on count data.

## Citations
- Ning Liu, Dharmesh Bhuva, Ahmed Mohamed, Chin Wee Tan, Melissa Davis (2026). standR: An R package for NanoString GeoMx DSP data analysis.

## References
- Homepage: bioconductor.org/packages/standr
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/standr/inst/doc/standR_introduction.html
