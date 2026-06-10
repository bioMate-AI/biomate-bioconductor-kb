---
name: bioconductor-metabocoreutils
description: MetaboCoreUtils defines metabolomics-related core functionality provided as low-level functions to allow a data structure-independent usage across various R packages. This includes functions to calculate between ion (adduct) and compound ma
when_to_use: Use when: Mass and m/z Conversions: Converting between exact compound masses and ion mass-to-charge ratios ($m/z$) using mass2mz and mz2mass.; Chemical Formula Manipulation: Standardizing chemical formulas to Hill notation (standardizeFormula), adding/subtracting elements (addElements, subtractElements), and calculating exact masses (calculateMass).; Signal Drift Adjustment: Modeling and adjusting for injec. Not for: Full LC-MS Preprocessing: For end-to-end raw data processing (peak picking, alignment, grouping); use high-level packages like xcms instead because MetaboCoreUtils only provides low-level utility functions.; Complex Statistical Modeling: For modeling
user-invocable: false
---

# MetaboCoreUtils

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.20.1 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** MsCoreUtils, BiocParallel
- **Install:** `BiocManager::install("MetaboCoreUtils")`

## When to Use
- **Mass and m/z Conversions**: Converting between exact compound masses and ion mass-to-charge ratios ($m/z$) using `mass2mz` and `mz2mass`.
- **Chemical Formula Manipulation**: Standardizing chemical formulas to Hill notation (`standardizeFormula`), adding/subtracting elements (`addElements`, `subtractElements`), and calculating exact masses (`calculateMass`).
- **Signal Drift Adjustment**: Modeling and adjusting for injection order-dependent signal drift in LC-MS feature abundances using `fit_lm` and `adjust_lm`.
- **Kendrick Mass Defect Calculation**: Identifying homologous series (e.g., lipids) by calculating Kendrick mass defects using `calculateKmd` and `calculateRkmd`.

## When NOT to Use
- **Full LC-MS Preprocessing**: For end-to-end raw data processing (peak picking, alignment, grouping); use high-level packages like `xcms` instead because `MetaboCoreUtils` only provides low-level utility functions.
- **Complex Statistical Modeling**: For modeling non-linear batch effects or complex multi-covariate experimental designs; use dedicated statistical modeling packages because `fit_lm` is designed for simple linear drift adjustments.

## Data Requirements
- **Input Format**: Character vectors for chemical formulas (e.g., `"C6H12O6"`), numeric vectors for masses or $m/z$ values, and matrices for feature abundances.
- **Retention Indexing**: A `data.frame` containing retention times and corresponding index values is required for `indexRtime` and `correctRindex`.
- **Signal Drift**: A matrix of feature abundances (features in rows, samples in columns) and a `data.frame` of covariates (e.g., injection index).

## Key Parameters
- **adduct**: Character string or vector specifying the ESI ion adduct (e.g., `"[M+H]+"` or `"[M+Na]+"`) for mass conversions.
- **data**: A `data.frame` containing the covariates (e.g., `injection_index`) passed to `fit_lm` and `adjust_lm`.
- **minVals**: The minimum number of non-missing values required in QC samples to fit a linear model in `fit_lm`.
- **y**: The response variable (e.g., log2-transformed abundances) passed to `fit_lm`.
- **lm**: A list of fitted linear models passed to `adjust_lm` to correct the data.

## Best Practices
- Always standardize chemical formulas using `standardizeFormula` before comparing them or counting elements (`countElements`) to ensure consistent formatting.
- Use `adductNames` to view the exact spelling of all supported ESI ion adduct definitions before performing $m/z$ conversions.
- When adjusting for signal drift, fit the linear models (`fit_lm`) exclusively on QC samples to ensure the estimated drift is independent of biological covariates.
- Evaluate the estimated signal drifts (e.g., check p-values and R-squared) and filter out poor fits (e.g., p-value > 0.05) before applying `adjust_lm`.

## Common Pitfalls
- **Unstable Drift Models**: Fitting linear models on features with too few QC measurements leads to unstable adjustments; *Fix*: Increase the `minVals` parameter in `fit_lm` to require a strict minimum of non-missing QC values.
- **Adjusting Non-Drifting Features**: Blindly applying `adjust_lm` to all features can introduce noise to features without true signal drift; *Fix*: Filter the list of models returned by `fit_lm` to remove fits with poor p-values before adjustment.
- **Incorrect Adduct Syntax**: Conversions fail if the adduct string is misspelled; *Fix*: Query `adductNames()` to verify the exact string format (e.g., `"[M+H]+"`).

## Alternatives
- **xcms**: Provides a comprehensive, high-level framework for LC-MS data preprocessing (peak picking, retention time alignment) rather than low-level utilities.
- **MsCoreUtils**: Offers core utilities specifically for mass spectrometry data (e.g., spectra processing, noise estimation) rather than chemical formula and adduct calculations.
- **enviPat**: Focuses on fine-grained isotopic pattern calculations and profile simulations rather than basic exact mass and $m/z$ conversions.

## Citations
- Rainer, M., Vicini, P., & Sigurdsson, S. (2022). MetaboCoreUtils: Core Utils for Metabolomics Data.
- Wehrens, R., et al. (2016). Improved batch correction in untargeted MS-based metabolomics. Metabolomics, 12(5), 88.

## References
- Homepage: https://bioconductor.org/packages/MetaboCoreUtils
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MetaboCoreUtils/inst/doc/MetaboCoreUtils.html
