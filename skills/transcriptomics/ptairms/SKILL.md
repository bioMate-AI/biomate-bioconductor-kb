---
name: bioconductor-ptairms
description: This package implements a suite of methods to preprocess data from PTR-TOF-MS instruments (HDF5 format) and generates the 'sample by features' table of peak intensities in addition to the sample and feature metadata (as a single ExpressionSet object for subsequent statistical analysis). This package also permit usefull tools for cohorts management as analyzing data progressively, visualization tools and quality control. The steps include calibration, expiration detection, peak detection and qua
when_to_use: Use when: ptaiMS: Processing and analysis of PTR-TOF-MS data; Metabolomics data analysis (ptairMS). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# ptairMS

## Workflows

### Standard Workflow

Preprocess a directory of raw PTR-TOF-MS HDF5 files to calibrate, detect peaks, align samples, impute missing values, annotate VOCs, and export an ExpressionSet.

```r
library(ptairMS)
dirRaw <- system.file("extdata/exhaledAir", package = "ptairData")

# Create ptrSet
exhaledPtrset <- createPtrSet(
  dir = dirRaw, 
  setName = "exhaledPtrset", 
  mzCalibRef = c(21.022, 60.0525), 
  fracMaxTIC = 0.7, 
  saveDir = NULL
)

# Detect peaks
exhaledPtrset <- detectPeak(exhaledPtrset)

# Align samples
exhaledEset <- alignSamples(exhaledPtrset, group = "individual", fracGroup = 1, fracExp = 1/6)

# Impute missing values
exhaledEset <- ptairMS::impute(exhaledEset, exhaledPtrset)

# Annotate VOCs
exhaledEset <- annotateVOC(exhaledEset)

# Export
writeEset(exhaledEset, dirC = file.path(getwd(), "processed_dataset"))
```
*Note: Inputs are a directory containing raw HDF5 files (.h5); the output is an ExpressionSet object and exported TSV files.*

### Single Raw File Processing

This package implements a suite of methods to preprocess data from PTR-TOF-MS instruments (HDF5 form

**Steps:**
1. Read the raw file using readRaw (exactly as documented)
2. Perform calibration on the single raw object
3. Determine time limits (expiration/headspace limits)
4. Write named output files for the meaningful results

```r
library(ptairMS)
dirRaw <- system.file("extdata/exhaledAir", package = "ptairData")
samplePath <- getFileNames(createPtrSet(dir = dirRaw, setName = "temp", mzCalibRef = c(21.022, 60.0525), saveDir = NULL), fullNames = TRUE)[1]

# 1. Read the raw file
sampleRaw <- readRaw(samplePath, calib = FALSE)

# 2. Perform calibration (done during readRaw or via calibration on ptrSet)
# 3. Determine time limits
expirationLimit <- timeLimits(sampleRaw, fracMaxTIC = 0.5, plotDel = TRUE, mzBreathTracer = 60.05)
```
*Note: Inputs are a path to a single raw HDF5 file; the output is the determined time limits of expiration or headspace duration.*

## When to Use
- To process raw PTR-TOF-MS data in HDF5 format (`.h5` extension) using `createPtrSet()`.
- To perform mass axis calibration using reference masses with `calibration()`.
- To detect and quantify peaks in PTR-TOF-MS spectra using `detectPeak()`.
- To align peaks across multiple samples and generate an `ExpressionSet` using `alignSamples()`.
- To impute missing values by returning to the raw data using `impute()`.
- To annotate features using the Human Breathomics Database via `annotateVOC()`.

## When NOT to Use
- For general LC-MS or GC-MS metabolomics preprocessing; use `xcms` instead.
- For general proteomics mass spectrometry data processing; use `MSnbase` or `Spectra` instead.

## Data Requirements
- Raw PTR-TOF-MS data files in HDF5 format (`.h5`).
- Reference calibration masses (e.g., `c(21.022, 60.0525)`).

## Key Parameters
- **mzCalibRef**: Numeric vector of reference masses used for mass axis calibration.
- **fracMaxTIC** (`0.7`): Fraction of maximum Total Ion Chromatogram (TIC) used to determine expiration or headspace time limits.
- **mzBreathTracer**: Mass used to trace expiration phases (e.g., `60.05` for acetone).
- **calibrationPeriod** (`60`): Time interval in seconds for periodic calibration to correct mass drift.
- **group**: Column name in sample metadata used for grouping during sample alignment.
- **fracGroup**: Minimum fraction of samples in at least one group where a peak must be detected to be retained.
- **fracExp**: Minimum fraction of samples where a peak must be significantly higher than background to be retained.
- **pValGreaterThres**: p-value threshold for comparing expiration/headspace phases to background.

## Best Practices
- Use `plot(ptrSet)` to check calibration errors (in ppm), resolution, and primary ion isotope intensity over time.
- Use `plotCalib()` to inspect the average total ion spectrum around reference masses if calibration errors are high.
- Use `plotTIC()` with `showLimits = TRUE` and `baselineRm = TRUE` to verify the detected expiration or headspace time limits.
- Use `plotRaw()` or `plotFeatures()` to visualize raw spectra and check the robustness of potential markers.
- Perform log2 transformation on the resulting `ExpressionSet` intensities using `log2(exprs(eset))` to stabilize variance before statistical analysis.

## Common Pitfalls
- Calibration drift due to temperature changes. Fix by setting an appropriate `calibrationPeriod` (default 60 seconds) to perform periodic calibration.
- Incorrect expiration or headspace detection. Fix by adjusting `fracMaxTIC` or specifying a specific `mzBreathTracer` in `changeTimeLimits()`.
- Modifying row names of sample metadata during external editing. Fix by ensuring row names always match the exact raw file names when using `importSampleMetadata()`.

## Alternatives
- `xcms` for comprehensive preprocessing of LC-MS and GC-MS data.
- `MSnbase` for general mass spectrometry data container and processing.
- `Spectra` for low-level mass spectrometry raw data representation.

## Citations
- Roquencourt et al. (2026), ptairMS: Processing and analysis of PTR-TOF-MS data.
- Blake et al. (2009), Proton Transfer Reaction Mass Spectrometry.

## References
- Homepage: bioconductor.org/packages/ptairms
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ptairms/inst/doc/ptairMS.html
