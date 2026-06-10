---
name: bioconductor-ggtree
description: 'ggtree' extends the 'ggplot2' plotting system which implemented the grammar of graphics. 'ggtree' is designed for visualization and annotation of phylogenetic trees and other tree-like structures with their annotation data.
when_to_use: Use when: Visualizing complex phylogenetic trees (e.g., from RAxML, IQ-TREE, or BEAST) integrated with multi-omics metadata (such as microbiome abundance, genomic features, or clinical traits).; Annotating tree nodes, clades, and leaves with custom shapes, colors, images, or subplots (e.g., barplots, pie charts) using the grammar of graphics.; Displaying circular, radial, rectangular, or slanted tree layout. Not for: For interactive, web-based tree exploration, use phylocanvas or iTOL instead because ggtree produces static vector graphics.; For simple, quick tree plotting without complex annotations, use ape::plot.phylo instead because it has zero overhead and re
user-invocable: false
---

# ggtree

`ggtree` extends the `ggplot2` plotting system to implement the grammar of graphics for phylogenetic trees. It is designed for the visualization, manipulation, and annotation of phylogenetic trees and other tree-like structures with their associated multi-omics and clinical metadata.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.2.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** ape, aplot, cli, dplyr, ggfun, ggiraph, ggplot2, magrittr, purrr, rlang, scales, tidyr, tidytree, treeio, yulab.utils
- **Install:** `BiocManager::install("ggtree")`

## When to Use
- Visualizing complex phylogenetic trees (e.g., from RAxML, IQ-TREE, or BEAST) integrated with multi-omics metadata (such as microbiome abundance, genomic features, or clinical traits).
- Annotating tree nodes, clades, and leaves with custom shapes, colors, images, or subplots (e.g., barplots, pie charts) using the grammar of graphics.
- Displaying circular, radial, rectangular, or slanted tree layouts for large-scale evolutionary studies containing hundreds to thousands of taxa.

## When NOT to Use
- For interactive, web-based tree exploration, use `phylocanvas` or `iTOL` instead because `ggtree` produces static vector graphics.
- For simple, quick tree plotting without complex annotations, use `ape::plot.phylo` instead because it has zero overhead and requires no `ggplot2` syntax.
- For highly customized interactive network visualizations that are not strictly hierarchical, use `ggnetwork` or `tidygraph` instead because `ggtree` is optimized specifically for tree topologies.

## Data Requirements
- **Input format**: Tree objects of class `phylo` (from `ape`), `treedata` (from `treeio`), or standard R dendrograms.
- **Metadata**: A data frame containing a column matching the tip labels of the tree.
- **Scale**: Supports trees from 10 to 10,000+ tips, though rendering times scale with taxon count.

## Key Parameters
- **layout** ("rectangular"): Layout of the tree; options include "circular", "slanted", "fan", "radial", "unrooted", "equal_angle", or "daylight".
- **ladderize** (TRUE): Logical; whether to sort the branches to make the tree look more structured.
- **branch.length** ("branch.length"): Variable to determine branch lengths; set to "none" for cladograms with equal branch lengths.
- **as.Date** (FALSE): Logical; whether to parse the x-axis as dates for time-resolved (chronogram) trees.
- **yscale** (NULL): Variable used to scale the y-axis, useful for custom vertical spacing.

## Best Practices
- Use the `treeio` package to import trees from diverse software formats (e.g., BEAST, MrBayes, NHX) to preserve node-level annotations.
- Attach external metadata using the `%<+%` operator to seamlessly map sample traits to tree tips or internal nodes.
- For large trees, use `layout = "circular"` or `layout = "fan"` to maximize space efficiency and prevent text overlap.
- Adjust label offsets and text sizes dynamically using `geom_tiplab(offset = ...)` to prevent labels from clipping outside the plot boundaries.

## Common Pitfalls
- **Tip labels overlapping or cut off**: Occurs when tree margins are too small or labels are long; fix this by adding `hexpand()` or `xlim()` to extend the plot canvas.
- **Metadata mapping failure**: Occurs when the ID column in the metadata does not match the tip labels exactly; fix this by ensuring `row.names` or a specific ID column matches `tree$tip.label`.
- **Slow rendering of large trees**: Occurs when adding too many individual geom layers to a tree with >10,000 tips; fix this by collapsing clades using `collapse()` before plotting.

## Alternatives
- `ape`: The foundational R phylogenetics package, faster for basic plotting but lacks `ggplot2` integration.
- `ggtreeExtra`: An extension of `ggtree` designed specifically for presenting circular layouts with multiple rings of complex genomic data.
- `phyloseq`: Excellent for microbiome-specific tree plotting, but less flexible for general phylogenetic annotations than `ggtree`.
- `tanggle`: Specifically designed for visualizing phylogenetic networks rather than strict bifurcating trees.

## Citations
- Yu, G., Smith, D. K., Zhu, H., Guan, Y., & Lam, T. T. Y. (2017). ggtree: an R package for visualization and annotation of phylogenetic trees with their covariates and other associated data. *Methods in Ecology and Evolution*, 8(1), 28-36.
- Yu, G. (2022). *Integration, Manipulation and Visualization of Phylogenetic Trees* (1st ed.). Chapman and Hall/CRC.

## References
- Homepage: https://bioconductor.org/packages/ggtree
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ggtree/inst/doc/ggtree.html
