---
name: bioconductor-mixomics
description: Multivariate methods are well suited to large omics data sets where the number of variables (e.g. genes, proteins, metabolites) is much larger than the number of samples (patients, cells, mice). They have the appealing properties of reducin
when_to_use: Use when: Performing unsupervised exploratory analysis and dimensionality reduction using pca and spca.; Integrating multiple omics datasets measured on the same samples (N-integration) using DIABLO.; Conducting supervised classification and feature selection for multi-class problems using splsda.. Not for: For simple univariate differential expression, use limma or DESeq2 instead because mixOmics is designed for multivariate feature selection and integration.; For raw mass spectrometry or sequencing read preprocessing, use xcms or edgeR for normalizati
user-invocable: false
---

# mixOmics

## When to Use
- Performing unsupervised exploratory analysis and dimensionality reduction using `pca` and `spca`.
- Integrating multiple omics datasets measured on the same samples (N-integration) using DIABLO.
- Conducting supervised classification and feature selection for multi-class problems using `splsda`.

## When NOT to Use
- For simple univariate differential expression, use `limma` or `DESeq2` instead because `mixOmics` is designed for multivariate feature selection and integration.
- For raw mass spectrometry or sequencing read preprocessing, use `xcms` or `edgeR` for normalization, as `mixOmics` requires pre-processed, normalized continuous matrices.

## Data Requirements
- Input: Numeric data matrix or data frames with $N$ observations (samples) in rows and $P$ predictors (variables) in columns.
- Pre-filtering: Data should be pre-filtered (e.g., < 10K predictors) to remove near-zero variance predictors and reduce computational time.
- Normalization: Data must be normalized prior to analysis (e.g., log-transformed for transcriptomics, CLR-transformed for compositional microbiome data).

## Key Parameters
- **ncomp** (none): The number of principal components or latent dimensions to extract in `pca`, `spca`, or `splsda`.
- **scale** (TRUE): Logical indicating whether to scale variables to unit variance before analysis in `pca` or `tune.pca`.
- **center** (TRUE): Logical indicating whether to center variables to zero mean in `pca`.
- **keepX** (none): A numeric vector specifying the number of variables to select on each component in sparse methods like `spca`.
- **comp** (none): Specifies which components to plot in `plotIndiv` or `plotVar` (e.g., `c(1, 2)`).
- **group** (none): Factor vector used to color samples by class in `plotIndiv` or `biplot`.

## Best Practices
- Use `tune.pca` to evaluate the cumulative proportion of explained variance and choose the optimal `ncomp` via a screeplot.
- Center and scale the data in `pca` to ensure variables with large variances do not dominate the components.
- Use `selectVar` to extract and rank the most important variables contributing to each component.
- Visualize sample clustering with `plotIndiv` and variable correlations with `plotVar` (correlation circle plot).

## Common Pitfalls
- **Misinterpreting correlation circle plots on unscaled data**: If data is not scaled, cosine angles do not accurately reflect correlations; fix this by ensuring `scale = TRUE` is set in the PCA/PLS method.
- **Overfitting in supervised models**: Using PLS-DA without cross-validation can yield perfect separation by chance; fix this by using cross-validation functions like `perf` and `tune.splsda` to objectively select `ncomp` and `keepX`.
- **Incorrect data orientation**: `mixOmics` expects samples in rows and variables in columns; fix this by transposing the matrix if samples are in columns.

## Alternatives
- **MOFA2**: Differs by using Bayesian Group Factor Analysis for multi-omics integration, handling missing values natively.
- **RGCCA**: Differs by focusing on regularized generalized canonical correlation analysis, which forms the theoretical basis for some mixOmics methods but offers different tuning.

## Citations
- Rohart F, Gautier B, Singh A, Lê Cao KA (2017). "mixOmics: An R package for 'omics feature selection and multiple data integration." PLOS Computational Biology, 13(11): e1005752.
- Singh A, Shannon CP, Gautier B, Rohart F, Vacher M, Tebbutt SJ, Lê Cao KA (2019). "DIABLO: an integrative, multi-omics, multivariate method for multi-group classification." Bioinformatics, 35(17): 3055-3062.

## References
- Homepage: http://www.mixOmics.org
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/mixOmics/inst/doc/vignettes.html
