---
name: bioconductor-dirichletmultinomial
description: Dirichlet-multinomial mixture models can be used to describe variability in microbial metagenomic data. This package is an interface to code originally made available by Holmes, Harris, and Quince, 2012, PLoS ONE 7(2): 1-15, as discussed fu
when_to_use: Use when: Fitting Dirichlet-Multinomial models to microbial metagenomic count data using dmn().; Identifying the optimal number of Dirichlet components (clusters) by comparing laplace(), AIC(), or BIC() scores.; Building generative classifiers for phenotypic groups using dmngroup().; Assigning new samples to classes using predict().. Not for: For continuous covariate modeling, use alternative regression frameworks because dmngroup() is designed for discrete phenotypic categories (e.g., 'Lean', 'Obese').
user-invocable: false
---

# DirichletMultinomial

## When to Use
- Fitting Dirichlet-Multinomial models to microbial metagenomic count data using `dmn()`.
- Identifying the optimal number of Dirichlet components (clusters) by comparing `laplace()`, `AIC()`, or `BIC()` scores.
- Building generative classifiers for phenotypic groups using `dmngroup()`.
- Assigning new samples to classes using `predict()`.

## When NOT to Use
- For continuous covariate modeling, use alternative regression frameworks because `dmngroup()` is designed for discrete phenotypic categories (e.g., 'Lean', 'Obese').

## Data Requirements
- A matrix of raw integer counts (samples in rows, taxa in columns).
- Phenotypic information as a factor for classification.

## Key Parameters
- **count** (default): The matrix of samples by taxa counts provided to `dmn()` or `dmngroup()`.
- **k** (default): The number of Dirichlet components to model in `dmn()` or `dmngroup()`.
- **assign** (FALSE): Set to `TRUE` in `predict()` or `mixture()` to return the component/class with the maximum value.
- **scale** (FALSE): Set to `TRUE` in `fitted()` to scale the posterior mean difference by theta.

## Best Practices
- Fit models across a range of components (e.g., `k=1:7`) and select the best fit using `which.min(lplc)` on the Laplace scores.
- Use `cvdmngroup()` to perform cross-validation and assess classifier performance via ROC curves.
- Use `heatmapdmn()` to visualize samples arranged by their dominant Dirichlet component.

## Common Pitfalls
- Cross-validation with `cvdmngroup()` is computationally expensive; fix this by using `mc.preschedule=FALSE` and running it on multiple cores via the `parallel` package.
- Passing non-integer or normalized data to `dmn()` violates the multinomial assumption; fix this by ensuring the input is a raw count matrix.

## Alternatives
- `vegan`: For standard distance-based clustering and ordination rather than generative mixture modeling.
- `phyloseq`: For general microbiome data manipulation and visualization.

## Citations
- Holmes et al., 2012, PLoS ONE 7(2): 1-15. https://doi.org/10.1371/journal.pone.0030126

## References
- Homepage: https://bioconductor.org/packages/DirichletMultinomial
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/DirichletMultinomial/inst/doc/DirichletMultinomial.pdf
