---
name: bioconductor-qvalue
description: This package takes a list of p-values resulting from the simultaneous testing of many hypotheses and estimates their q-values and local FDR values. The q-value of a test measures the proportion of false positives incurred (called the false
when_to_use: Use when: Use this package when performing simultaneous hypothesis testing on many features (e.g., differential gene expression across thousands of genes) and you need to control the false discovery rate, estimate the proportion of true nulls, or calculate posterior probabilities of the null hypothesis being true (local FDR).
user-invocable: false
---

# qvalue

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.44.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** ggplot2, reshape2
- **Install:** `BiocManager::install("qvalue")`

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

- **`p`**: A vector of p-values (the only required input for the qvalue function)
- **`fdr.level`**: The level at which to control the FDR, returning a logical vector indicating significance
- **`pfdr`**: An indicator to use the positive false discovery rate estimate, making it more robust for small p-values
- **`lambda`**: The tuning parameter(s) used to estimate pi0, defaulting to seq(0, 0.95, 0.05)
- **`pi0.method`**: The method for automatically handling the tuning parameter in pi0 estimation, either "smoother" or "bootstrap"
- **`trunc`**: In lfdr, a logical indicating whether local FDR estimates greater than 1 should be set to 1 (default is TRUE)
- **`stat`**: In empPvals, a vector of observed test statistics
- **`stat0`**: In empPvals, a matrix/vector of empirical null statistics (e.g., from bootstrap or permutations)
- **`pool`**: In empPvals, a logical indicating whether to pool the empirical null statistics

## Workflow Variants

### Fdr Estimation From Pvalues

**Intent**: Estimate q-values, pi0, and local FDR directly from a vector of user-provided p-values, and visualize the results.

**Inputs**:
- `hedenfalk$p (vector of p-values from simultaneous hypothesis tests)`

**Steps**:
1. Load the package and input p-values
2. Run the qvalue function to perform FDR estimation
3. Extract estimated q-values, pi0, and local FDR
4. Summarize and visualize the results using diagnostic plots and histograms

```r
library(qvalue)
data(hedenfalk)
pvalues <- hedenfalk$p
qobj <- qvalue(p = pvalues)
qvalues <- qobj$qvalues
pi0 <- qobj$pi0
lfdr <- qobj$lfdr
summary(qobj)
plot(qobj)
hist(qobj)
```


---

### Fdr Estimation From Test Statistics

**Intent**: Calculate empirical p-values from observed and null test statistics, and then estimate q-values and local FDR.

**Inputs**:
- `hedenfalk$stat (vector of observed test statistics)`
- `hedenfalk$stat0 (matrix of empirical null statistics generated via permutation or bootstrap)`

**Steps**:
1. Load the package and input statistics
2. Calculate empirical p-values using the empPvals function
3. Run the qvalue function on the calculated p-values to estimate FDR

```r
library(qvalue)
data(hedenfalk)
obs_stats <- hedenfalk$stat
null_stats <- hedenfalk$stat0
pvalues <- empPvals(stat = obs_stats, stat0 = null_stats)
qobj <- qvalue(p = pvalues)
```


## Best Practices

- **Check P-value Histogram**: Always view a histogram of the p-values (`hist(p)`) before running `qvalue` to confirm the right tail is flat.
- **Evaluate Pi0 Reliability**: Use `plot(qobj)` to view the estimated $\pi_0$ versus the tuning parameter $\lambda$ to gauge the reliability of the $\pi_0$ estimate.
- **Summarize Results**: Use `summary(qobj)` to view the $\pi_0$ estimate and the cumulative number of significant calls at various p-value, q-value, and local FDR cutoffs.

## Common Pitfalls

- U-shaped p-value histograms are a major red flag indicating that the assumption of null p-values following a Uniform(0,1) distribution is violated. This can occur if a one-sided test was performed on two-sided signal, or if there is strong dependence among variables. Users should also note that q-values are not adjusted p-values (like Bonferroni corrections) and can sometimes be smaller than the original p-values because the maximum possible q-value is capped at the estimated pi0, which is often less than 1.

## Alternatives

- **sva**: A Bioconductor package recommended when there is dependence among variables in the data, often indicated by a U-shaped p-value histogram
- **Benjamini and Hochberg (1995)**: Equivalent to setting lambda = 0 and specifying fdr.level in the qvalue function, which acts as a conservative special case of the Storey methodology

## Citations

- Storey JD. (2002). A direct approach to false discovery rates. *Journal of the Royal Statistical Society, Series B*, 64:479–498.
- Storey JD. (2003). The positive false discovery rate: A Bayesian interpretation and the q-value. *Annals of Statistics*, 31:2013–2035.
- Storey JD, Tibshirani R. (2003). Statistical significance for genome-wide experiments. *Proceedings of the National Academy of Sciences*, 100:9440–9445.

## References

- Homepage: https://bioconductor.org/packages/qvalue
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/qvalue/inst/doc/qvalue.pdf
