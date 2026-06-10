---
name: bioconductor-scdblfinder
description: The scDblFinder package gathers various methods for the detection and handling of doublets/multiplets in single-cell sequencing data (i.e. multiple cells captured within the same droplet or reaction volume). It includes methods formerly fou
when_to_use: Use when: Identifying heterotypic doublets in single-cell RNA sequencing data using the scDblFinder iterative classifier.; Detecting doublets in multiplexed samples by processing each capture separately using the samples argument.; Testing for specific doublet type enrichments (e.g., combinations of clusters) using doubletPairwiseEnrichment or clusterStickiness.; Recovering intra-sample doublets that are ne. Not for: For identifying homotypic doublets or inter-sample doublets in multiplexed experiments (use cell hashing or genotype-based SNP calls instead, as scDblFinder focuses on transcriptionally distinct heterotypic doublets).
user-invocable: false
---

# scDblFinder

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.26.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** SingleCellExperiment
- **Imports:** igraph, Matrix, BiocGenerics, BiocParallel, BiocNeighbors, BiocSingular, S4Vectors, SummarizedExperiment, scran, scater, scuttle, bluster, DelayedArray, xgboost, MASS, IRanges, GenomicRanges, GenomeInfoDb, Rsamtools, rtracklayer
- **Install:** `BiocManager::install("scDblFinder")`

## When to Use
- Identifying heterotypic doublets in single-cell RNA sequencing data using the `scDblFinder` iterative classifier.
- Detecting doublets in multiplexed samples by processing each capture separately using the `samples` argument.
- Testing for specific doublet type enrichments (e.g., combinations of clusters) using `doubletPairwiseEnrichment` or `clusterStickiness`.
- Recovering intra-sample doublets that are neighbors to known inter-sample doublets (e.g., from cell hashing) using `recoverDoublets`.

## When NOT to Use
- For identifying homotypic doublets or inter-sample doublets in multiplexed experiments (use cell hashing or genotype-based SNP calls instead, as `scDblFinder` focuses on transcriptionally distinct heterotypic doublets).

## Data Requirements
- A `SingleCellExperiment` object or a simple count matrix containing raw counts (assay 'counts').
- Empty droplets should already be removed prior to running the tool.

## Key Parameters
- **samples** (NULL): Column name in `colData` or a vector indicating the sample/capture of origin to process batches separately.
- **clusters** (FALSE): Cluster labels or `TRUE` to use `fastcluster`; enables cluster-based artificial doublet generation.
- **dbr** (NULL): Expected proportion of doublets; if omitted, automatically estimated based on the number of captured cells.
- **dbr.per1k** (0.008): Expected doublet rate per thousand cells, defaulting to standard 10X rates.
- **artificialDoublets** (NULL): Number of artificial doublets to generate; defaults to roughly the number of cells.
- **nfeatures** (1000): Number of top expressed genes to retain for dimensionality reduction to speed up analysis.

## Best Practices
- Always split multi-sample datasets by providing the `samples` argument so doublets are sought independently for each capture.
- Use the cluster-based approach (`clusters=TRUE`) if your dataset has a very clear cluster structure to avoid generating unidentifiable homotypic artificial doublets.
- Check the distribution of doublet scores (`hist(sce$scDblFinder.score)`); a bimodal distribution indicates successful doublet identification.
- If running multiple samples with the cluster-based approach, pre-cluster all samples together using `fastcluster` and pass the labels to the `clusters` argument to ensure concordant labels across samples.

## Common Pitfalls
- **Way too many doublets called**: Often caused by pooling multiple samples without specifying the `samples` argument, making the tool assume a massive single capture. *Fix*: Provide the `samples` argument to split cells by capture/batch.
- **'Size factors should be positive' error**: Caused by cells with zero reads or very low read counts that drop to zero after feature selection. *Fix*: Filter out empty droplets and extremely low-count cells before running `scDblFinder`.
- **Nonsensical cluster labels across samples**: When running multiple samples without providing cluster labels, `scDblFinder` clusters them sample-wise, leading to mismatched labels. *Fix*: Pre-cluster all samples together using `fastcluster` and pass the labels to the `clusters` argument.

## Alternatives
- **computeDoubletDensity**: A simpler density-based method (formerly `scran::doubletCells`) that identifies cells with a high local density of artificial doublets.
- **findDoubletClusters**: Identifies entire clusters that are likely composed of doublets by checking if their expression profile lies between two other clusters.
- **directDblClassification**: Trains a classifier directly on gene expression without the kNN step, though generally yields worse predictions than `scDblFinder`.

## Citations
- Germain, P. L., Lun, A., Macnair, W., & Robinson, M. D. (2021). Doublet identification in single-cell sequencing data using scDblFinder. F1000Research, 10, 979.
- Howitt et al., 2024. (Referenced regarding doublets in 10x Flex datasets).

## References
- Homepage: bioconductor.org/packages/scDblFinder
- Vignette: vignette_0_d20f7c0c.txt
