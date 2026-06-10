---
name: bioconductor-monocle
description: Monocle performs differential expression and time-series analysis for single-cell expression experiments. It orders individual cells according to progress through a biological process, without knowing ahead of time which genes define progre
when_to_use: Use when: Analyzing single-cell RNA-Seq experiments to study complex biological processes.; Ordering single cells in pseudotime to place them along a trajectory corresponding to a biological process such as cell differentiation.; Performing differential gene expression and clustering to identify important genes and cell states.; Visualizing data distributions or trajectories using plot().. Not for: For bulk RNA-Seq differential expression, use DESeq2 instead because Monocle is specifically designed for single-cell RNA-Seq experiments.; For Python-based single-cell workflows, use Scanpy instead because Monocle is an R package.
user-invocable: false
---

# monocle

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.40.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** Matrix, Biobase, ggplot2, VGAM, DDRTree
- **Imports:** igraph, BiocGenerics, HSMMSingleCell, plyr, cluster, combinat, fastICA, irlba, matrixStats, Rtsne, MASS, reshape2, leidenbase, limma, tibble, dplyr, pheatmap, stringr, proxy, slam, viridis, biocViews, RANN, Rcpp
- **System requirements:** URL
- **Install:** `BiocManager::install("monocle")`

## When to Use
- Analyzing single-cell RNA-Seq experiments to study complex biological processes.
- Ordering single cells in pseudotime to place them along a trajectory corresponding to a biological process such as cell differentiation.
- Performing differential gene expression and clustering to identify important genes and cell states.
- Visualizing data distributions or trajectories using `plot()`.

## When NOT to Use
- For bulk RNA-Seq differential expression, use `DESeq2` instead because Monocle is specifically designed for single-cell RNA-Seq experiments.
- For Python-based single-cell workflows, use `Scanpy` instead because Monocle is an R package.

## Data Requirements
- **Input Format**: Single-cell gene expression data (e.g., RNA-Seq).
- **Structure**: Expression matrices representing unsynchronized individual cells executing a gene expression program.

## Key Parameters
- **warning** (FALSE): Controls whether warnings are displayed during knitr chunk execution via `opts_chunk$set()`.
- **dpi** (600): Sets the resolution for generated plots via `opts_chunk$set()`.
- **cache** (FALSE): Controls whether to cache the knitr code chunks.

## Best Practices
- Load required prerequisite packages like `Biobase`, `reshape2`, and `ggplot2` using `library()` before starting the analysis.
- Use `set.seed()` to ensure reproducibility of the trajectory learning and clustering algorithms.
- Configure global chunk options using `opts_chunk$set()` to ensure high-quality plot outputs.

## Common Pitfalls
- **Missing Dependencies**: Failing to load required packages will cause errors; fix this by running `library(Biobase)` and `library(ggplot2)` at the start of your script.
- **Non-Reproducible Results**: Running the unsupervised trajectory algorithms without a seed can lead to variable results across runs; fix this by setting a random seed with `set.seed()`.

## Alternatives
- `monocle3`: The completely redesigned successor to Monocle, optimized for large datasets and complex trajectories.
- `slingshot`: A flexible, cluster-based trajectory inference tool for single-cell data.
- `scater`: For upstream single-cell preprocessing, normalization, and quality control.

## Citations
- Trapnell C, Cacchiarelli D, et al. (2014). The dynamics and regulators of cell fate decisions are revealed by pseudo-temporal ordering of single cells. Nature Biotechnology, 32:381-386. [PMID:24658644](https://pubmed.ncbi.nlm.nih.gov/24658644)
- Qiu X, Hill A, et al. (2017). Single-cell mRNA quantification and differential analysis with Census. Nature Methods, 14:309-315. [PMID:28114287](https://pubmed.ncbi.nlm.nih.gov/28114287)

## References
- Homepage: https://bioconductor.org/packages/monocle
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/monocle/inst/doc/monocle-vignette.pdf