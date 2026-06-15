---
name: bioconductor-msdatahub
description: The MsDataHub package uses the ExperimentHub infrastructure to distribute raw mass spectrometry data files, peptide spectrum matches or quantitative data from proteomics and metabolomics experiments.
when_to_use: Use when: The MsDataHub package uses the ExperimentHub infrastructure to distribute raw mass spectrometry data files, peptide spec; data using datatable; install1 using install; lfdia using readQFeaturesFromDIANN; pledia using readQFeaturesFromDIANN; Mass Spectrometry Data on ExperimentHub. Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# MsDataHub

## Workflows

### Standard Workflow

The MsDataHub package uses the ExperimentHub infrastructure to distribute raw mass spectrometry data files, peptide spectrum matches or quantitative data from proteomics and metabolomics experiments.

```r
library(MsDataHub)
library(Spectra)
library(QFeatures)

# 1. Load raw MS data (TripleTOF DDA) and create a Spectra object
f_dda <- PestMix1_DDA.mzML()
s_dda <- Spectra(f_dda)

# 2. Load DIA-NN label-free DIA data and read into QFeatures
lfdia <- read.delim(MsDataHub::benchmarkingDIA.tsv())
qf <- readQFeaturesFromDIANN(lfdia)
```
*Note: Inputs are cached file paths retrieved from MsDataHub accessor functions; outputs are Spectra or QFeatures objects containing mass spectrometry data.*

## When to Use
- **Accessing raw mass spectrometry data files**: Retrieve example raw files (e.g., `.mzML`, `.CDF`) from standard proteomics/metabolomics experiments via `ExperimentHub` caching.
- **Retrieving peptide spectrum matches (PSMs)**: Load identification files (e.g., `.mzid`) using `PSM()` from the `PSMatch` package.
- **Loading quantitative proteomics data tables**: Import tab-delimited tables (e.g., MaxQuant peptide tables, DIA-NN outputs) into `SummarizedExperiment` or `QFeatures` structures using `readSummarizedExperiment()` or `readQFeaturesFromDIANN()`.

## When NOT to Use
- **For raw MS data preprocessing**: For peak picking, alignment, or retention time correction, use `xcms` because `MsDataHub` only distributes pre-existing example datasets.
- **For statistical differential abundance analysis**: For downstream statistical modeling of quantitative proteomics data, use `MSstats` because `MsDataHub` is a data repository rather than an analytical tool.
- **For general-purpose biological annotation**: For annotating genes or proteins, use `AnnotationDbi` or `biomaRt` because `MsDataHub` only provides mass spectrometry-specific data and contaminant databases.

## Data Requirements
- **Raw MS data files**: Open formats such as `.mzML` (e.g., `PestMix1_DDA.mzML()`), `.CDF` (e.g., `ko15.CDF()`), or compressed `.mzML.gz`.
- **Peptide spectrum matches**: Standard `.mzid` format (e.g., `TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01.20141210.mzid()`).
- **Tab-delimited quantitative tables**: Text files (e.g., `cptac_peptides.txt()`, `benchmarkingDIA.tsv()`) containing peptide intensities or DIA-NN report outputs.

## Key Parameters
- **multiplexing** (NULL): In `readQFeaturesFromDIANN()`, set to `"mTRAQ"` for multiplexed plexDIA data.
- **sep** ("\t"): In `readSummarizedExperiment()`, specifies the field separator character for reading text files.
- **ecols** (integer vector): In `readSummarizedExperiment()`, specifies the column indices containing quantitative intensity data.

## Best Practices
- Use `MsDataHub()` inside `DT::datatable()` to browse the complete list of available datasets and their metadata.
- Load raw data files into a `Spectra` object using `Spectra(f)` to leverage memory-efficient backends.
- When reading DIA-NN outputs, use `read.delim()` to load the file path returned by `MsDataHub::benchmarkingDIA.tsv()` before passing it to `readQFeaturesFromDIANN()`.

## Common Pitfalls
- **Attempting to read raw files directly without caching**: Call the specific dataset function (e.g., `PestMix1_DDA.mzML()`) to download and retrieve the local cache path first.
- **Mismatched intensity column selection in MaxQuant tables**: Use `grep("Intensity\\.", names(read.delim(f)))` to dynamically identify quantitative columns before calling `readSummarizedExperiment()`.
- **Incorrect multiplexing parameter for label-free DIA**: Ensure `multiplexing` is omitted or set correctly when using `readQFeaturesFromDIANN()` on label-free vs mTRAQ plexDIA data.

## Alternatives
- **xcms**: For raw LC-MS data preprocessing and peak alignment.
- **MSnbase**: For legacy mass spectrometry data container management and processing.
- **Spectra**: For modern, infrastructure-independent representation of mass spectrometry spectra.
- **MSstats**: For downstream statistical analysis of quantitative proteomics experiments.

## Citations
- Gatto L (2026). MsDataHub: Mass Spectrometry Data on ExperimentHub. R package version 1.12.0.

## References
- Homepage: https://bioconductor.org/packages/MsDataHub
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MsDataHub/inst/doc/MsDataHub.html
