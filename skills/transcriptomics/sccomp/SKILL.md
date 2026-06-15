---
name: bioconductor-sccomp
description: A robust and outlier-aware method for testing differential tissue composition from single-cell data. This model can infer changes in tissue composition and heterogeneity, and can produce realistic data simulations based on any existing dataset. This model can also transfer knowledge from a large set of integrated datasets to increase accuracy further.
when_to_use: Use when: sccomp; Differential expression analysis (sccomp); Single-cell RNA-seq analysis (sccomp). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# sccomp

## Workflows

### Standard Workflow

Estimate and test differences in cell type composition across groups from single-cell count data, with optional outlier removal and visualization.

```r
library(sccomp)
library(dplyr)

# Estimate composition and test differences with outlier removal
sccomp_result <- counts_obj |>
  sccomp_estimate(
    formula_composition = ~ type,
    sample = "sample",
    cell_group = "cell_group",
    abundance = "count",
    cores = 1, 
    verbose = FALSE
  ) |>
  sccomp_remove_outliers(cores = 1, verbose = FALSE, max_sampling_iterations = 2000) |>
  sccomp_test()

# Generate boxplot visualization
sccomp_result |> sccomp_boxplot(factor = "type")
```
*Input: A count data frame or SingleCellExperiment/Seurat object. Output: A tibble containing composition effects, FDR, and outlier annotations.*

### Differential Variability Analysis

Model and test differences in cell-group variability across groups.

```r
library(sccomp)

# Estimate both composition and variability
res <- seurat_obj |>
  sccomp_estimate(
    formula_composition = ~ type,
    formula_variability = ~ type,
    sample = "sample",
    cell_group = "cell_group",
    cores = 1, 
    verbose = FALSE
  )

# Test and plot credible intervals
plots <- res |> sccomp_test() |> plot()
plots$credible_intervals_1D
```
*Input: A Seurat or SingleCellExperiment object. Output: A model fit with variability effects and 1D/2D credible interval plots.*

### Model Comparison Loo

Compare different composition models (e.g., with vs. without a covariate) using leave-one-out (loo) cross-validation.

```r
library(sccomp)
library(loo)

# Fit model with factor association
model_with_factor_association <- seurat_obj |>
  sccomp_estimate(
    formula_composition = ~ type,
    sample = "sample",
    cell_group = "cell_group",
    inference_method = "hmc",
    enable_loo = TRUE,
    verbose = FALSE
  )

# Fit baseline model without association
model_without_association <- seurat_obj |>
  sccomp_estimate(
    formula_composition = ~ 1,
    sample = "sample",
    cell_group = "cell_group",
    inference_method = "hmc",
    enable_loo = TRUE,
    verbose = FALSE
  )

# Compare models using leave-one-out cross-validation
loo_compare(
  attr(model_with_factor_association, "fit")$loo(),
  attr(model_without_association, "fit")$loo()
)
```
*Input: A Seurat or SingleCellExperiment object. Output: A comparison table containing elpd_diff and se_diff.*

### Random Effects Modeling

Model cell-type proportions with both fixed effects and random effects (e.g., random intercepts or random slopes).

```r
library(sccomp)

# Fit a random intercept model
res <- seurat_obj |>
  sccomp_estimate(
    formula_composition = ~ type + (1 | group__),
    sample = "sample",
    cell_group = "cell_group",
    bimodal_mean_variability_association = TRUE,
    cores = 1, 
    verbose = FALSE
  )
```
*Input: A Seurat or SingleCellExperiment object with grouping variables in metadata. Output: A model fit containing fixed and random effect estimates.*

## When to Use
- To perform robust differential composition analysis on single-cell RNA-seq, CyTOF, or microbiome data using sum-constrained Beta-binomial modeling (`sccomp_estimate`).
- To identify and probabilistically remove outliers from composition estimation (`sccomp_remove_outliers`).
- To perform differential variability analysis across groups (`sccomp_estimate` with `formula_variability`).
- To model multi-level or hierarchical structures with random effects (e.g., random intercepts or random slopes) in single-cell datasets.

## When NOT to Use
- For standard differential gene expression analysis, use packages like `DESeq2` or `edgeR` instead of `sccomp` which is designed for cell-type composition.
- When counts are available, do not model proportions directly (e.g., using `abundance = "proportion"`) because it fails to model uncertainty for rare cell groups; use raw counts instead.

## Data Requirements
- Input can be a `Seurat` object, `SingleCellExperiment` object, or a count tibble/data frame containing columns for sample, cell group, and abundance (counts).
- For single-cell RNA sequencing, it is recommended to set `bimodal_mean_variability_association = TRUE`. For CyTOF and microbiome data, set `bimodal_mean_variability_association = FALSE`.

## Key Parameters
- **formula_composition**: Formula for modeling cell-type composition (e.g., `~ type`).
- **formula_variability**: Formula for modeling cell-group variability (e.g., `~ type`).
- **sample**: Column name representing the sample identifier.
- **cell_group**: Column name representing the cell group/type identifier.
- **abundance** (`"count"`): Column name representing counts or proportions.
- **bimodal_mean_variability_association** (`FALSE`): Logical indicating whether to model bimodal mean-variability association (recommended `TRUE` for scRNA-seq).
- **enable_loo** (`FALSE`): Logical indicating whether to enable leave-one-out cross-validation.
- **inference_method** (`"hcm"`): Method used for inference (e.g., `"hmc"`).

## Best Practices
- Do not run `sccomp_remove_outliers()` when performing model comparison with `loo_compare()`, as leave-one-out cross-validation requires the models to be fit on the exact same data.
- Verify the mean-variability association using `plot_2D_intervals()` or `plots$credible_intervals_2D` to ensure the linear association is satisfied before interpreting differential variability.
- Use `sccomp_proportional_fold_change()` to obtain intuitive proportional fold changes for communication, but rely on `sccomp_test()` for statistical significance.

## Common Pitfalls
- Using proportions instead of counts when counts are available: This discards critical uncertainty information for rare cell types. Fix: Pass raw counts and set `abundance = "count"`.
- Running outlier removal before model comparison: This causes `loo_compare()` to fail or be invalid because different numbers of data points may be removed. Fix: Omit `sccomp_remove_outliers()` when comparing models.

## Alternatives
- `scCODA`: Uses a Dirichlet-multinomial model but does not model group-specific variability or outliers.
- `propeller`: Uses a logit-linear model with `limma` but does not model data count distribution directly.
- `corncob`: Uses a Beta-binomial model but does not support mixed-effect modeling or outlier detection.
- `ANCOM-BC`: Uses a log-linear model designed primarily for microbiome data.

## Citations
- Mangiola, Stefano, et al. 2023. "Sccomp: Robust Differential Composition and Variability Analysis for Single-Cell Data." Proceedings of the National Academy of Sciences 120 (33): e2203828120. https://doi.org/10.1073/pnas.2203828120

## References
- Homepage: bioconductor.org/packages/sccomp
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/sccomp/inst/doc/vignettes.html
