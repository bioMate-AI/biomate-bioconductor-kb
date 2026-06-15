---
name: bioconductor-scdesign3
description: We present a statistical simulator, scDesign3, to generate realistic single-cell and spatial omics data, including various cell states, experimental designs, and feature modalities, by learning interpretable parameters from real data. Using a unified probabilistic model for single-cell and spatial omics data, scDesign3 infers biologically meaningful parameters; assesses the goodness-of-fit of inferred cell clusters, trajectories, and spatial locations; and generates in silico negative and positi
when_to_use: Use when: scDesign3-quickstart-vignette; Single-cell RNA-seq analysis (scDesign3). Not for: Requires R ≥ 4.3.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# scDesign3

## Workflows

### Standard Workflow

Simulate a single-cell RNA-seq dataset with a continuous developmental trajectory from a reference dataset and visualize the simulation quality.

```r
library(scDesign3)
library(SingleCellExperiment)
library(ggplot2)

# Load example data
data("example_count", package = "scDesign3")
data("pseudotime", package = "scDesign3")

# Construct reference SingleCellExperiment
example_sce <- SingleCellExperiment(
  assays = list(counts = example_count, logcounts = log1p(example_count)),
  colData = DataFrame(pseudotime = pseudotime)
)

# Run simulation
set.seed(123)
example_simu <- scdesign3(
  sce = example_sce,
  assay_use = "counts",
  celltype = NULL,
  pseudotime = "pseudotime",
  spatial = NULL,
  other_covariates = NULL,
  mu_formula = "s(pseudotime, k = 10, bs = 'cr')",
  sigma_formula = "1",
  family_use = "nb",
  n_cores = 2,
  usebam = FALSE,
  corr_formula = "1",
  copula = "gaussian",
  DT = TRUE,
  pseudo_obs = FALSE,
  return_model = FALSE,
  nonzerovar = FALSE
)

# Create simulated SingleCellExperiment
simu_sce <- SingleCellExperiment(
  list(counts = example_simu$new_count), 
  colData = example_simu$new_covariate
)
logcounts(simu_sce) <- log1p(counts(simu_sce))

# Visualize and compare
compare_figure <- plot_reduceddim(
  ref_sce = example_sce, 
  sce_list = list(simu_sce), 
  name_vec = c("Reference", "scDesign3"),
  assay_use = "logcounts", 
  if_plot = TRUE, 
  color_by = "pseudotime", 
  n_pc = 20
)
plot(compare_figure$p_umap)
```
*Input: A SingleCellExperiment reference object with pseudotime. Output: A simulated SingleCellExperiment object and a UMAP comparison plot.*

## When to Use
- To simulate realistic single-cell RNA-seq data with continuous developmental trajectories using `scdesign3()`.
- To generate synthetic count matrices that preserve the correlation structure and marginal distributions of a reference dataset.
- To visualize and compare simulated data against reference data using dimensionality reduction plots via `plot_reduceddim()`.

## When NOT to Use
- For simple clustering or differential expression analysis without simulation, use packages like `scran` or `scater` directly.

## Data Requirements
- A `SingleCellExperiment` object containing a raw count matrix in its assays (e.g., `"counts"`).
- Cell covariates (such as cell types, pseudotime, or spatial coordinates) stored in the `colData` of the `SingleCellExperiment` object.

## Key Parameters
- **sce**: The input `SingleCellExperiment` reference object.
- **assay_use** (`"counts"`): The assay name in `sce` to use for simulation.
- **pseudotime**: Column name in `colData` representing pseudotime.
- **mu_formula**: Formula for the mean parameter of the marginal distribution (e.g., `"s(pseudotime, k = 10, bs = 'cr')"`).
- **sigma_formula** (`"1"`): Formula for the dispersion/variance parameter.
- **family_use** (`"nb"`): Distribution family to use (e.g., `"nb"` for negative binomial).
- **copula** (`"gaussian"`): Copula type to model gene correlation (e.g., `"gaussian"` or `"vine"`).
- **n_cores** (`2`): Number of cores to use for parallel computation.

## Best Practices
- Set a seed using `set.seed()` before running `scdesign3()` and visualization functions to ensure reproducibility of the simulated counts and UMAP layouts.
- To model dispersion varying along pseudotime, set `sigma_formula` to a spline formula (e.g., `"s(pseudotime, k = 5, bs = 'cr')"`), keeping in mind this increases computational cost.

## Common Pitfalls
- High computational cost when modeling complex dispersion: Setting a complex `sigma_formula` along pseudotime can significantly increase runtime. Fix: Keep `sigma_formula = "1"` unless variable dispersion is critical.

## Alternatives
- `scater`: For basic single-cell visualization and QC, but does not perform parametric simulation.
- `scran`: For normalization and variance modeling, but not for generating synthetic datasets.

## Citations
- Song, Dongyuan, and Qingyang Wang. 2026. "scDesign3: A unified probabilistic framework for single-cell and spatial omics simulation."

## References
- Homepage: bioconductor.org/packages/scDesign3
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/scDesign3/inst/doc/scDesign3-quickstart-vignette.html
