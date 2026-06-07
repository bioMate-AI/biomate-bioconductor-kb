---
name: bioconductor-qvalue
description: This package takes a list of p-values resulting from the simultaneous testing of many hypotheses and estimates their q-values and local FDR values. The q-value of a test measures the proportion of false positives incurred (called the false
when_to_use: Use when: False Discovery Rate Estimation: When analyzing thousands of features (e.g., differential gene expression) to estimate q-values and control the false discovery rate using qvalue.; Estimating True Nulls: When you need to estimate the overall proportion of true null hypotheses ($\pi_0$) from a distribution of p-values using pi0est.; Local FDR Calculation: When you want to calculate the empirical Bay. Not for: Dependent Test Statistics: When tests are strongly dependent or have uncorrected batch effects (indicated by a U-shaped p-value histogram), use the sva package first to correct the data.; Small-scale hypothesis testing: For experiments with very few 
user-invocable: false
---

# qvalue

## When to Use
- **False Discovery Rate Estimation**: When analyzing thousands of features (e.g., differential gene expression) to estimate q-values and control the false discovery rate using `qvalue`.
- **Estimating True Nulls**: When you need to estimate the overall proportion of true null hypotheses ($\pi_0$) from a distribution of p-values using `pi0est`.
- **Local FDR Calculation**: When you want to calculate the empirical Bayesian posterior probability that a null hypothesis is true, conditional on the observed p-value, using `lfdr`.
- **Empirical P-value Calculation**: When you have observed test-statistics and simulated/resampled null statistics and need to compute p-values using `empPvals`.

## When NOT to Use
- **Dependent Test Statistics**: When tests are strongly dependent or have uncorrected batch effects (indicated by a U-shaped p-value histogram), use the `sva` package first to correct the data.
- **Small-scale hypothesis testing**: For experiments with very few tests, use standard Benjamini-Hochberg adjustment because the estimation of $\pi_0$ is highly unstable with small sample sizes.

## Data Requirements
- A numeric vector of p-values strictly bounded between 0 and 1, OR a vector of observed statistics and a matrix of empirical null statistics.
- P-values must follow a Uniform(0,1) distribution under the null hypothesis (the right tail of the p-value histogram should be fairly flat).

## Key Parameters
- **p** (required): A vector of p-values.
- **fdr.level** (NULL): The level at which to control the false discovery rate; returns a logical vector indicating significant tests.
- **pfdr** (FALSE): Indicator of whether to use the positive false discovery rate (pFDR) to make the estimate more robust for small p-values.
- **lambda** (seq(0, 0.95, 0.05)): Values of the tuning parameter considered in estimating $\pi_0$.
- **pi0.method** ("smoother"): Method for automatically handling the tuning parameter in $\pi_0$ estimation ("smoother" or "bootstrap").
- **trunc** (TRUE): If TRUE, local FDR estimates > 1 are set to 1 in `lfdr`.
- **stat** (NULL): Vector of observed test-statistics calculated on the original data for `empPvals`.
- **stat0** (NULL): Matrix of empirical null statistics for `empPvals`.

## Best Practices
- **Check P-value Histogram**: Always view a histogram of the p-values (`hist(p)`) before running `qvalue` to confirm the right tail is flat.
- **Evaluate Pi0 Reliability**: Use `plot(qobj)` to view the estimated $\pi_0$ versus the tuning parameter $\lambda$ to gauge the reliability of the $\pi_0$ estimate.
- **Summarize Results**: Use `summary(qobj)` to view the $\pi_0$ estimate and the cumulative number of significant calls at various p-value, q-value, and local FDR cutoffs.

## Common Pitfalls
- **U-shaped p-value histograms**: Indicates dependence among variables or a one-sided test on data with two-sided signal. *Fix: Compute p-values using a different model or use the `sva` package to correct for dependence.*
- **Assuming q-values are adjusted p-values**: Users often worry when q-values are smaller than original p-values. *Fix: Understand that q-values are population quantities bounded by $\pi_0$, not Bonferroni adjusted p-values.*
- **Incorrect empirical p-values**: Passing statistics where larger values do not indicate more evidence against the null. *Fix: Ensure statistics passed to `empPvals` are constructed such that larger values are "more extreme" (e.g., absolute values of t-statistics).*

## Alternatives
- **sva**: For correcting dependent variables and batch effects before computing p-values.
- **fdrtool**: Estimates local FDR and tail area FDR directly from z-scores or p-values.
- **IHW**: Incorporates covariates (like base mean expression) to increase statistical power.
- **ashr**: Uses adaptive shrinkage to model the distribution of effects, providing robust local FDR estimates.

## Citations
- Storey JD. (2002). A direct approach to false discovery rates. *Journal of the Royal Statistical Society, Series B*, 64:479–498.
- Storey JD. (2003). The positive false discovery rate: A Bayesian interpretation and the q-value. *Annals of Statistics*, 31:2013–2035.
- Storey JD, Tibshirani R. (2003). Statistical significance for genome-wide experiments. *Proceedings of the National Academy of Sciences*, 100:9440–9445.

## References
- Homepage: https://bioconductor.org/packages/qvalue
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/qvalue/inst/doc/qvalue.pdf
