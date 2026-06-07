---
name: bioconductor-mscoreutils
description: MsCoreUtils defines low-level functions for mass spectrometry data and is independent of any high-level data structures. These functions include mass spectra processing functions (noise estimation, smoothing, binning, baseline estimation),
when_to_use: Use when: Quantitative Aggregation: Calculating the robust summary of matrix columns (e.g., summarizing peptide quantitation values into protein intensities) using robustSummary().; Spectra Processing: Performing low-level mass spectra processing such as noise estimation, smoothing, and binning using functions like noise(), smooth(), and bin().; Missing Data Imputation: Imputing missing data in quantitative. Not for: For high-level, formal data structure manipulation of MS data, use Spectra or MSnbase instead because MsCoreUtils only provides low-level functions independent of high-level data structures.; For complete end-to-end LC-MS preprocessing workflows, use
user-invocable: false
---

# MsCoreUtils

## When to Use
- **Quantitative Aggregation**: Calculating the robust summary of matrix columns (e.g., summarizing peptide quantitation values into protein intensities) using `robustSummary()`.
- **Spectra Processing**: Performing low-level mass spectra processing such as noise estimation, smoothing, and binning using functions like `noise()`, `smooth()`, and `bin()`.
- **Missing Data Imputation**: Imputing missing data in quantitative matrices using methods like `impute_knn()`, `impute_RF()`, or `impute_matrix()`.
- **Data Normalization**: Normalizing data matrices using `normalize_matrix()`.

## When NOT to Use
- For high-level, formal data structure manipulation of MS data, use **Spectra** or **MSnbase** instead because `MsCoreUtils` only provides low-level functions independent of high-level data structures.
- For complete end-to-end LC-MS preprocessing workflows, use **xcms** instead because `MsCoreUtils` provides individual utility functions rather than a full pipeline.

## Data Requirements
- Basic R classes such as `matrix` or numeric vectors.
- For `robustSummary()`, a numeric `matrix` where columns represent samples and rows represent features (e.g., peptides).

## Key Parameters
- **x** (matrix): A numeric matrix provided to functions like `robustSummary()`.
- **nrow** (numeric): Number of rows when constructing a `matrix()` for testing or processing.

## Best Practices
- Use `robustSummary()` to aggregate quantitative values robustly, which is typically used internally by high-level functions like `MSnbase::combineFeatures()`.
- Check available imputation and normalization methods using `imputeMethods()` and `normalizeMethods()`.
- Ensure input data is in standard base R formats (like `matrix`) before applying `MsCoreUtils` functions.

## Common Pitfalls
- **High-level object errors**: Passing a `Spectra` or `QFeatures` object directly to `MsCoreUtils` functions. *Fix*: Extract the underlying `matrix` or numeric vectors first, as `MsCoreUtils` is independent of high-level data structures.
- **Missing dependencies**: Attempting to use advanced imputation methods without required packages. *Fix*: Ensure all suggested packages for specific `impute_*` functions are installed.
- **Incorrect matrix orientation**: Summarizing across the wrong dimension. *Fix*: Remember that `robustSummary()` calculates the robust summary of the *columns* of a matrix.

## Alternatives
- **MSnbase**: Provides high-level data structures and methods (like `combineFeatures()`) that wrap `MsCoreUtils` functions.
- **QFeatures**: Provides `aggregateFeatures()` for high-level quantitative feature aggregation.
- **Spectra**: For high-level mass spectrometry data handling and processing.

## Citations
- Sticker et al. "Robust summarization and inference in proteome-wide label-free quantification." https://doi.org/10.1101/668863.
- Rainer et al. (2022). "A Modular and Expandable Ecosystem for Metabolomics Data Annotation in R."

## References
- Homepage: bioconductor.org/packages/MsCoreUtils
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MsCoreUtils/inst/doc/MsCoreUtils.html
