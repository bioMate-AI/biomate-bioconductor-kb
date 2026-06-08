---
name: bioconductor-ggtree
description: 'ggtree' extends the 'ggplot2' plotting system which implemented the grammar of graphics. 'ggtree' is designed for visualization and annotation of phylogenetic trees and other tree-like structures with their annotation data.
when_to_use: Use when: Visualizing complex phylogenetic trees (e.g., from RAxML, IQ-TREE, or BEAST) integrated with multi-omics metadata (such as microbiome abundance, genomic features, or clinical traits).; Annotating tree nodes, clades, and leaves with custom shapes, colors, images, or subplots (e.g., barplots, pie charts) using the grammar of graphics.; Displaying circular, radial, rectangular, or slanted tree layout. Not for: For interactive, web-based tree exploration, use phylocanvas or iTOL instead because ggtree produces static vector graphics.; For simple, quick tree plotting without complex annotations, use ape::plot.phylo instead because it has zero overhead and re
user-invocable: false
---

# ggtree

`ggtree` extends the `ggplot2` plotting system to implement the grammar of graphics for phylogenetic trees. It is designed for the visualization, manipulation, and annotation of phylogenetic trees and other tree-like structures with their associated multi-omics and clinical metadata.

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

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required libraries
    library(GenomicRanges)
    library(ggtree)
    library(ggplot2)
    
    # Stage 1: Import genomic intervals and metadata
    message("Reading input files...")
    bed_data <- read.table("regions.bed", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
    colnames(bed_data) <- c("chrom", "start", "end", "name", "score", "strand")[1:min(6, ncol(bed_data))]
    
    # Create GRanges object
    gr <- GRanges(
      seqnames = bed_data\$chrom,
      ranges = IRanges(start = bed_data\$start, end = bed_data\$end),
      strand = if ("strand" %in% colnames(bed_data)) bed_data\$strand else "*",
      name = if ("name" %in% colnames(bed_data)) bed_data\$name else paste0("region_", seq_len(nrow(bed_data))),
      score = if ("score" %in% colnames(bed_data)) bed_data\$score else 0
    )
    
    # Stage 2: Compute distance matrix and perform hierarchical clustering
    message("Clustering genomic regions...")
    midpoints <- (start(gr) + end(gr)) / 2
    dist_matrix <- dist(matrix(midpoints, ncol = 1))
    labels(dist_matrix) <- gr\$name
    
    # Generate hierarchical clustering tree
    hc <- hclust(dist_matrix, method = "average")
    
    # Stage 3: Prepare and merge metadata
    message("Preparing metadata...")
    df_meta <- data.frame(
      label = gr\$name,
      chrom = as.character(seqnames(gr)),
      width = width(gr),
      score = gr\$score,
      stringsAsFactors = FALSE
    )
    
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      if ("name" %in% colnames(coldata)) {
        colnames(coldata)[colnames(coldata) == "name"] <- "label"
      }
      df_meta <- merge(df_meta, coldata, by = "label", all.x = TRUE)
    }
    
    # Export combined metadata
    write.csv(df_meta, "tree_metadata.csv", row.names = FALSE)
    
    # Stage 4: Visualize and annotate tree using ggtree
    message("Generating ggtree visualization...")
    p <- ggtree(hc)
    
    # Attach metadata to the tree structure
    p <- p %<+% df_meta
    
    # Add tree annotations and layers
    p <- p + 
      geom_tiplab(aes(label = label), size = 3, hjust = -0.2) +
      geom_tippoint(aes(color = chrom, size = width), alpha = 0.8) +
      geom_treescale()
    
    # Programmatically highlight a clade if the tree has sufficient nodes
    num_tips <- length(hc\$order)
    if (num_tips > 3) {
      # Highlight the second internal node as a representative clade
      target_node <- num_tips + 2
      p <- p + 
        geom_hilight(node = target_node, fill = "steelblue", alpha = 0.3) +
        geom_cladelabel(node = target_node, label = "Clade A", color = "darkblue", offset = 0.5)
    }
    
    # Save the final annotated tree plot
    ggsave("tree_plot.pdf", plot = p, width = 10, height = 8)
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING":
        ggtree: \$(Rscript -e 'cat(as.character(packageVersion("ggtree")))')
    END_VERSIONS
```

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
