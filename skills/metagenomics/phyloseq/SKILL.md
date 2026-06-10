---
name: bioconductor-phyloseq
description: phyloseq provides a set of classes and tools to facilitate the import, storage, analysis, and graphical display of microbiome census data.
when_to_use: Use when: Importing and storing complex phylogenetic sequencing data (OTU tables, sample metadata, taxonomy, trees) into a single object using import().; Estimating and visualizing alpha diversity using plot_richness() with measures like "Chao1" or "Shannon".; Performing beta diversity ordination (e.g., PCoA, NMDS, CCA) using ordinate() and visualizing the results with plot_ordination().; Creating explorato. Not for: For advanced network analysis beyond basic ecological similarity, use igraph directly because plot_net() provides only a default Jaccard co-occurrence network.; For complex custom plotting beyond standard wrappers, use ggplot2 directly because phylos
user-invocable: false
---

# phyloseq

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.56.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** ade4, ape, Biobase, BiocGenerics, biomformat, Biostrings, cluster, data.table, foreach, ggplot2, igraph, multtest, plyr, reshape2, scales, vegan
- **Install:** `BiocManager::install("phyloseq")`

## When to Use
- Importing and storing complex phylogenetic sequencing data (OTU tables, sample metadata, taxonomy, trees) into a single object using `import()`.
- Estimating and visualizing alpha diversity using `plot_richness()` with measures like "Chao1" or "Shannon".
- Performing beta diversity ordination (e.g., PCoA, NMDS, CCA) using `ordinate()` and visualizing the results with `plot_ordination()`.
- Creating exploratory bar plots of taxonomic abundance across samples using `plot_bar()`.

## When NOT to Use
- For advanced network analysis beyond basic ecological similarity, use `igraph` directly because `plot_net()` provides only a default Jaccard co-occurrence network.
- For complex custom plotting beyond standard wrappers, use `ggplot2` directly because `phyloseq` wrappers are built on it but may restrict advanced geoms.

## Data Requirements
- Pre-clustered phylogenetic sequencing data (OTU/ASV table).
- Associated sample data (metadata), a phylogenetic tree, and/or taxonomic assignments.
- Raw (untrimmed) OTU-clustered data is strictly required when performing richness estimates.

## Key Parameters
- **measures**: Alpha diversity estimators to calculate in `plot_richness()` (e.g., `c("Observed", "Chao1", "Shannon")`).
- **method**: Ordination method for `ordinate()` (e.g., "PCoA", "NMDS", "CCA").
- **distance**: Distance metric for `ordinate()` (e.g., "bray", "unifrac").
- **maxdist**: Maximum distance required to create an edge in `plot_net()`.
- **type**: What to plot in `plot_ordination()` (e.g., "samples", "species", "biplot", "split").
- **color** / **shape** / **fill**: Variables from `sample_data` or `tax_table` to map to aesthetics in plotting functions.

## Best Practices
- Use raw (untrimmed) OTU-clustered data when performing richness estimates with `plot_richness()`, as estimates depend heavily on singletons.
- Prune absent taxa using `prune_taxa()` and `taxa_sums() > 0` to remove artifacts before downstream analysis.
- Subset large datasets using `subset_taxa()` before rendering computationally heavy plots like `plot_heatmap()` or `plot_tree()`.
- Use scree plots (`plot_scree()`) to evaluate the relative importance of axes after performing ordination.

## Common Pitfalls
- **Richness estimates are skewed or incorrect**: Using normalized or trimmed data removes singletons necessary for accurate alpha diversity estimation. Fix: Ensure you use raw, untrimmed counts in `plot_richness()`.
- **`plot_bar()` is illegible**: Plotting all taxa at once creates a solid block of color due to too many OTUs. Fix: Subset to the most abundant taxa or facet by taxonomic rank (e.g., `facet_grid=~Genus`).
- **`UniFrac()` takes too long**: Calculating UniFrac distances on large datasets (like Global Patterns) is computationally intensive. Fix: Use parallelization or subset the data before running the distance calculation.

## Alternatives
- **vegan**: For underlying ecological distance and ordination calculations without the `phyloseq` S4 object overhead.
- **ape**: For direct phylogenetic tree manipulation and plotting outside of microbiome contexts.
- **ggplot2**: For building custom graphics from scratch when `phyloseq` plot wrappers are too constrained.

## Citations
- McMurdie PJ, Holmes S (2013). "phyloseq: An R Package for Reproducible Interactive Analysis and Graphics of Microbiome Census Data." *PLoS ONE*, 8(4): e61217.
- Caporaso JG, et al. (2011). "Global Patterns of 16S rRNA Diversity at a Depth of Millions of Sequences Per Sample." *PNAS*, 108: 4516-22.

## References
- Homepage: https://bioconductor.org/packages/phyloseq
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/phyloseq/inst/doc/phyloseq-analysis.html
