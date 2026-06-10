---
name: bioconductor-apeglm
description: apeglm provides Bayesian shrinkage estimators for effect sizes for a variety of GLM models, using approximation of the posterior for individual coefficients.
when_to_use: Use when: Log Fold Change Shrinkage: Shrinking effect sizes for negative binomial GLMs in RNA-seq differential expression analysis (typically called via the DESeq2::lfcShrink wrapper).; Beta-Binomial Modeling: Estimating and shrinking GLM coefficients for binomial or beta-binomial rate data, such as allele-specific count ratios.; False Sign Rate Evaluation: Calculating local false sign rates (FSR) and s-val. Not for: Direct Log2 Scale Requirements: If you require coefficients directly estimated on the log2 scale without manual conversion, note that apeglm natively estimates coefficients on the natural log scale (though DESeq2::lfcShrink converts these to log2 int
user-invocable: false
---

# apeglm

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.34.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** SummarizedExperiment, GenomicRanges, Rcpp
- **Imports:** emdbook, SummarizedExperiment, GenomicRanges, Rcpp
- **System requirements:** URL
- **Install:** `BiocManager::install("apeglm")`

## When to Use
- **Log Fold Change Shrinkage**: Shrinking effect sizes for negative binomial GLMs in RNA-seq differential expression analysis (typically called via the `DESeq2::lfcShrink` wrapper).
- **Beta-Binomial Modeling**: Estimating and shrinking GLM coefficients for binomial or beta-binomial rate data, such as allele-specific count ratios.
- **False Sign Rate Evaluation**: Calculating local false sign rates (FSR) and s-values via `svalue` to control the probability of false-sign-or-small (FSOS) events.

## When NOT to Use
- **Direct Log2 Scale Requirements**: If you require coefficients directly estimated on the log2 scale without manual conversion, note that `apeglm` natively estimates coefficients on the natural log scale (though `DESeq2::lfcShrink` converts these to log2 internally).
- **Non-GLM Continuous Data**: For standard linear modeling of continuous data (e.g., microarray log-intensities) where negative binomial or beta-binomial likelihoods do not apply.

## Data Requirements
- **Input Counts**: A `SummarizedExperiment` object or a matrix of raw integer counts passed to the `Y` parameter.
- **Design Matrix**: A model matrix `x` specifying the experimental design (typically created using `model.matrix`).
- **Dispersions**: A numeric vector of dispersion parameters `param` (e.g., estimated using `dispersions` from `DESeq2`).
- **MLE Estimates**: A matrix `mle` containing maximum likelihood estimates of the coefficients and their standard errors, scaled to the natural log scale.
- **Offsets**: A matrix of offsets `offset` matching the dimensions of the count matrix (e.g., log of `sizeFactors`).

## Key Parameters
- **Y**: The input data, which can be a `SummarizedExperiment` or a matrix of counts.
- **x**: The design matrix (model matrix) for the GLM.
- **log.lik**: The log-likelihood function to use (set to `NULL` when using fast C++ methods).
- **param**: Parameter values for the likelihood, such as dispersion estimates.
- **coef**: The integer index of the coefficient in the design matrix to shrink.
- **threshold**: A numeric value on the natural log scale specifying the threshold for false-sign-or-small (FSOS) event probability calculation.
- **mle**: A matrix of maximum likelihood estimates and their standard errors.
- **method**: The estimation method to use, such as `"nbinomR"`, `"nbinomCR"`, `"nbinomC"`, `"betabinCR"`, `"betabinC"`, or `"general"`.

## Best Practices
- **Use Integrated Wrappers**: For standard RNA-seq workflows, call `lfcShrink(dds, coef=2, type="apeglm")` from the `DESeq2` package to automatically handle scaling and parameter setup.
- **Select Fast C++ Methods**: Use `method="nbinomCR"` (which calculates posterior standard deviations) or `method="nbinomC"` (which returns only MAP coefficients) to achieve 10x to 100x speedups over the default `"general"` method.
- **Scale Thresholds Correctly**: When specifying a custom `threshold` in `apeglm`, multiply your log2-scale threshold by `log(2)` to convert it to the natural log scale required by the function.
- **Iterative Beta-Binomial Fitting**: When modeling ratios of counts, perform iterative estimation of MLE coefficients and beta-binomial dispersions using `bbEstDisp`.

## Common Pitfalls
- **Mismatched Coefficient Scales**: Comparing raw `apeglm` output directly to log2 fold changes; fix this by multiplying the `apeglm` MAP estimates by `log2(exp(1))` to convert them from the natural log scale to the log2 scale.
- **Slow Execution on Large Datasets**: Using the default `"general"` method on large count matrices; fix this by setting `method="nbinomCR"` or `method="nbinomC"` for negative binomial data.
- **Line Search Failures**: Encountering line search routine failures during beta-binomial dispersion estimation; fix this by ensuring your initial dispersion estimates and input counts are properly filtered and bounded.

## Alternatives
- **DESeq2 (normal method)**: Provides the original normal-prior-based shrinkage estimator via `lfcShrink(type="normal")`.
- **edgeR**: Can be used as an alternative framework to estimate size factors and dispersions prior to shrinkage.
- **zinbwave**: Useful in combination with `apeglm` to model zero-inflated negative binomial data by estimating and down-weighting excess zero components.

## Citations
- Zhu, A., Ibrahim, J. G., & Love, M. I. (2018). "Heavy-tailed prior distributions for sequence count data: adaptive shrinkage and its precision." *Bioinformatics*, 35(12), 2084-2092.
- Stephens, M. (2016). "False discovery rates: a new dataset may warrant a new look." *Biostatistics*, 18(2), 275–294.
- Love, M. I., Huber, W., & Anders, S. (2014). "Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2." *Genome Biology*, 15(12), 550.

## References
- Homepage: https://bioconductor.org/packages/apeglm
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/apeglm/inst/doc/apeglm.html
