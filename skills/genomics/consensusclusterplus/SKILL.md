---
name: bioconductor-consensusclusterplus
description: algorithm for determining cluster count and membership by stability evidence in unsupervised analysis
when_to_use: Use when: Unsupervised class discovery from gene expression data (e.g., microarray data).; Determining optimal cluster count and membership using consensus clustering resampling.; Generating consensus matrices, CDF plots, and tracking plots to assess cluster stability.; Calculating cluster-consensus and item-consensus metrics using the calcICL function.. Not for: For extremely large datasets without pre-computing distance matrices (use a pre-computed dist object instead to save time).; If you need non-resampling based clustering (use standard hclust or kmeans instead).
user-invocable: false
---

# ConsensusClusterPlus

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.76.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** ALL, cluster
- **Imports:** Biobase, ALL, cluster
- **System requirements:** URL
- **Install:** `BiocManager::install("ConsensusClusterPlus")`

## When to Use
- Unsupervised class discovery from gene expression data (e.g., microarray data).
- Determining optimal cluster count and membership using consensus clustering resampling.
- Generating consensus matrices, CDF plots, and tracking plots to assess cluster stability.
- Calculating cluster-consensus and item-consensus metrics using the `calcICL` function.

## When NOT to Use
- For extremely large datasets without pre-computing distance matrices (use a pre-computed `dist` object instead to save time).
- If you need non-resampling based clustering (use standard `hclust` or `kmeans` instead).

## Data Requirements
- A matrix of numerical values where columns are samples (items) and rows are features (e.g., genes).
- Alternatively, a pre-computed distance matrix (`dist` object) can be provided.
- Data is typically filtered for highly variable features (e.g., top 5000 genes by `mad`) and median-centered using `sweep` and `median`.

## Key Parameters
- **d**: The input data matrix or pre-computed distance matrix.
- **maxK**: The maximum evaluated cluster count (e.g., 6).
- **reps**: The number of resamplings to perform (e.g., 50 for testing, 1000 in practice).
- **pItem**: The proportion of items to resample in each iteration (e.g., 0.8).
- **pFeature**: The proportion of features to resample in each iteration (e.g., 1).
- **clusterAlg**: The clustering algorithm to use (e.g., "hc", "pam", "km", or a custom function).
- **distance**: The distance metric to use (e.g., "pearson", "spearman", "euclidean", "manhattan").
- **plot**: The output format for graphical results (e.g., "png", "pdf", "pngBMP").

## Best Practices
- Filter the dataset to the most informative/variable genes using `mad` before clustering.
- Median-center the data using `sweep` and `median` if using Pearson correlation distance.
- Use a high number of `reps` (e.g., 1,000) and a higher `maxK` (e.g., 20) in real-world practice.
- Run `calcICL` after `ConsensusClusterPlus` to generate and plot cluster-consensus and item-consensus metrics.

## Common Pitfalls
- Computation time is too long for large datasets with feature resampling. *Fix*: Provide a pre-computed distance matrix to `d` or use `plot="pngBMP"` to avoid plotting massive dendrograms.
- Results change between runs making analysis irreproducible. *Fix*: Always specify a random `seed` parameter in the `ConsensusClusterPlus` call.
- Consensus matrix dendrogram fails to plot for large datasets. *Fix*: Use `plot="pngBMP"` which uses the bitmap function rather than png.

## Alternatives
- **cluster**: For standard clustering algorithms like `diana` or `pam` without consensus resampling.
- **NMF**: For non-negative matrix factorization based clustering.
- **mclust**: For model-based clustering.

## Citations
- Monti, S., Tamayo, P., Mesirov, J., Golub, T. (2003) Consensus Clustering: A Resampling-Based Method for Class Discovery and Visualization of Gene Expression Microarray Data. Machine Learning, 52, 91-118.
- Wilkerson, M.D., Hayes, D.N. (2010). ConsensusClusterPlus: a class discovery tool with confidence assessments and item tracking. Bioinformatics, 26(12):1572-3.

## References
- Homepage: https://bioconductor.org/packages/ConsensusClusterPlus
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ConsensusClusterPlus/inst/doc/ConsensusClusterPlus.pdf
