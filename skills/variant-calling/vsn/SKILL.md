---
name: bioconductor-vsn
description: The package implements a method for normalising microarray intensities from single- and multiple-color arrays. It can also be used for data from other technologies, as long as they have similar format. The method uses a robust variant of th
when_to_use: Use when: Microarray Normalization: Normalizing and variance-stabilizing unnormalised microarray intensity data (e.g., two-colour spotted cDNA arrays or single-colour arrays) using justvsn or vsn2.; Affymetrix Preprocessing: Applying variance stabilization, background correction, and transformation to Affymetrix genechip data via the vsnrma wrapper.; Reference-Based Normalization: Normalizing new test array. Not for: For summarizing Affymetrix data without VSN's specific variance stabilization, use rma from the affy package because it provides standard robust multi-array average summarization.; For addressing variance dependencies on factors other than the mean i
user-invocable: false
---

# vsn

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 3.80.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** Biobase
- **Imports:** affy, limma, lattice, ggplot2
- **Install:** `BiocManager::install("vsn")`

## When to Use
- **Microarray Normalization**: Normalizing and variance-stabilizing unnormalised microarray intensity data (e.g., two-colour spotted cDNA arrays or single-colour arrays) using `justvsn` or `vsn2`.
- **Affymetrix Preprocessing**: Applying variance stabilization, background correction, and transformation to Affymetrix genechip data via the `vsnrma` wrapper.
- **Reference-Based Normalization**: Normalizing new test arrays against an existing reference dataset without altering the reference model using the `reference` argument in `vsn2`.
- **Spike-in Calibration**: Fitting calibration and transformation parameters on a subset of features (like spike-in probes) using `vsn2`, and then applying the model to the complete dataset using `predict`.

## When NOT to Use
- For summarizing Affymetrix data without VSN's specific variance stabilization, use `rma` from the `affy` package because it provides standard robust multi-array average summarization.
- For addressing variance dependencies on factors other than the mean intensity (e.g., gene-inherent properties or sample-inherent transcriptional control tightness), use specialized models because VSN only addresses the dependence of variance on the mean intensity.
- For reading and processing raw image quantitation files directly into R, use `read.maimages` from the `limma` package because `vsn` expects already-imported data structures.

## Data Requirements
- **Input Format**: An `ExpressionSet`, `AffyBatch` (from the `affy` package), `RGList` (from the `limma` package), `NChannelSet`, or a raw numeric matrix.
- **Data Structure**: Rows represent features (e.g., spots, probes) and columns represent samples or arrays.
- **Normalization State**: Unnormalised, raw intensity data (do not log-transform prior to VSN, as it applies its own generalized logarithm, $glog_2$, transformation).

## Key Parameters
- **strata**: Allows choosing different offset and scaling factors for different groups of rows (e.g., print-tip groups or sectors).
- **calib**: Controls the calibration behavior (e.g., choosing the same offset and scaling factor throughout if calibration was already done).
- **backgroundsubtract** (FALSE): When set to TRUE in `justvsn` for an `RGList`, subtracts local background estimates from the incoming data.
- **lts.quantile**: Controls the robustness of the parameter estimation algorithm; setting it to 1 corresponds to least sum of squares regression (no outlier removal), useful for trusted spike-in sets.
- **reference**: Allows passing an existing fitted `vsn` object to normalize new arrays against a reference dataset.
- **ranks** (TRUE): Used in `meanSdPlot` to distribute data evenly along the x-axis by rank rather than average intensity.

## Best Practices
- **Verify Variance Stabilization**: Use `meanSdPlot` after normalization to verify variance stabilization by checking if the running median of the standard deviation is approximately a horizontal line.
- **Two-Step Fitting**: When fitting parameters on a subset of data (e.g., spike-ins) using `vsn2`, apply the model to the complete dataset using the `predict` method.
- **Background Correction**: Avoid subtracting local background estimates unless there is actual local variability (like a spatial gradient), as VSN already estimates and subtracts an overall background estimate.
- **Affymetrix Workflows**: For Affymetrix genechip data, use the `vsnrma` wrapper to seamlessly combine VSN's background correction, between-array normalization, and transformation with RMA summarization.

## Common Pitfalls
- **Optimization Convergence Failure**: Encountering the error "L-BFGS-B needs finite values of 'fn'" due to unsuitable data or flat parameter space directions. *Fix*: Check data quality, experimental design, or prior preprocessing steps for incompatible measurements.
- **Systematic Trends Post-Normalization**: Observing an overall trend in the `meanSdPlot` after normalization. *Fix*: Investigate raw data integrity or inadequate prior preprocessing, as this indicates the variance stabilization failed.
- **Increased Random Noise**: Adding random noise to the signal by unnecessarily subtracting local background estimates. *Fix*: Rely on VSN's overall background estimate and leave `backgroundsubtract=FALSE` unless spatial gradients are explicitly present.
- **Metadata Loss During Coercion**: Losing sample metadata when `justvsn` converts an `RGList` to an `NChannelSet`. *Fix*: Manually construct and assign an `AnnotatedDataFrame` to the `phenoData` slot of the resulting object.

## Alternatives
- **affy**: Provides the standard `rma` function for Affymetrix genechip preprocessing without VSN's specific generalized logarithm transformation.
- **limma**: Provides `read.maimages` for importing data and `lmFit`/`eBayes` for linear modeling and differential expression, often used downstream of VSN.
- **quantreg**: Provides quantile regression, which is a more rigorous alternative to the simple running median used in `meanSdPlot` for assessing variance.

## Citations
- Huber W, et al. (2002). Variance stabilization applied to microarray data calibration and to the quantification of differential expression. *Bioinformatics*, 18(Suppl 1), S96-S104.
- Rocke DM, Durbin B (2001). A model for measurement error for gene expression arrays. *Journal of Computational Biology*, 8(6), 557-569.
- Irizarry RA, et al. (2003). Summaries of Affymetrix Microarray Probe Level Data. *Nucleic Acids Research*, 31(4), e15.

## References
- Homepage: https://bioconductor.org/packages/vsn
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/vsn/inst/doc/vsn.pdf
