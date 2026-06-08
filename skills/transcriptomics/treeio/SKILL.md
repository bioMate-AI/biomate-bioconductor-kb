---
name: bioconductor-treeio
description: 'treeio' is an R package to make it easier to import and store phylogenetic tree with associated data; and to link external data from different sources to phylogeny. It also supports exporting phylogenetic tree with heterogeneous associated
when_to_use: Use when: Phylogenetic Tree Input and Output: Managing phylogenetic tree data using the package's core base classes.; Vignette Redirection: Accessing the full documentation and tutorials by navigating to the external treedata-book resource linked in the package stub.. Not for: Detailed In-Package Tutorials: For comprehensive workflows, use the external treedata-book website because the built-in vignette is only a stub.; Tree Reconstruction: For inferring phylogenetic trees from sequence alignments, use external tools becau
user-invocable: false
---

# treeio

## When to Use
- **Phylogenetic Tree Input and Output**: Managing phylogenetic tree data using the package's core base classes.
- **Vignette Redirection**: Accessing the full documentation and tutorials by navigating to the external `treedata-book` resource linked in the package stub.

## When NOT to Use
- **Detailed In-Package Tutorials**: For comprehensive workflows, use the external `treedata-book` website because the built-in vignette is only a stub.
- **Tree Reconstruction**: For inferring phylogenetic trees from sequence alignments, use external tools because `treeio` focuses strictly on base classes for input and output.

## Data Requirements
- **Tree Files**: Phylogenetic tree files compatible with the package's base classes for input and output.

## Key Parameters
- **tidy** (FALSE): `knitr::opts_chunk$set` option used to control code formatting in the vignette.
- **message** (FALSE): `knitr::opts_chunk$set` option used to suppress messages during document compilation.

## Best Practices
- **Consult External Documentation**: Go to `https://yulab-smu.top/treedata-book/` for the full vignette and comprehensive workflow instructions.
- **Clean Report Compilation**: Set `tidy = FALSE` and `message = FALSE` in `knitr::opts_chunk$set` when compiling reports to avoid clutter.
- **Utilize Base Classes**: Rely on the base classes provided by the package for consistent phylogenetic tree input and output.

## Common Pitfalls
- **Missing Documentation**: Looking for detailed tutorials in the standard vignette fails because it is only a stub. Fix: Go to the external `treedata-book` link provided in the vignette text.
- **Unwanted Compilation Messages**: R outputs verbose messages during document rendering. Fix: Use `message = FALSE` in the `knitr::opts_chunk$set` options.

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required libraries
    library(treeio)
    library(stats)
    
    # Stage 1: Read input transcriptomics data
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Stage 2: Preprocess and compute distance matrix
    # Log-transform counts to stabilize variance across samples
    log_counts <- log2(counts + 1)
    
    # Compute sample-to-sample Euclidean distance based on expression profiles
    sample_dist <- dist(t(log_counts))
    
    # Stage 3: Build hierarchical clustering tree and convert to phylo
    hc <- hclust(sample_dist, method = "average")
    # Convert hclust object to a phylo object using treeio's imported/exported methods
    phylo_tree <- treeio::as.phylo(hc)
    
    # Stage 4: Prepare metadata and QC metrics to link with the tree
    sample_summary <- data.frame(
      sample = colnames(counts),
      total_counts = colSums(counts),
      detected_genes = colSums(counts > 0),
      stringsAsFactors = FALSE
    )
    
    # Merge experimental design metadata with computed QC metrics
    metadata <- merge(coldata, sample_summary, by = "sample")
    
    # Stage 5: Link metadata to the phylogenetic tree using treeio
    # treeio::full_join merges the data frame with the phylo object by matching tip labels
    annotated_tree <- treeio::full_join(
      phylo_tree, 
      metadata, 
      by = c("label" = "sample")
    )
    
    # Stage 6: Export the annotated tree and association table
    # Write the tree with its associated node/tip data in BEAST NEXUS format
    treeio::write.beast(annotated_tree, file = "annotated_tree.beast")
    
    # Convert the treedata object to a tibble/dataframe to export as a flat table
    tree_df <- as.data.frame(treeio::as_tibble(annotated_tree))
    write.csv(tree_df, "tree_metadata_association.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY":
        treeio: \$(Rscript -e 'cat(as.character(packageVersion("treeio")))')
    END_VERSIONS
```

## Alternatives
- **ape**: Provides basic phylogenetic tree structures, but `treeio` offers specialized base classes for input and output.
- **phylobase**: Another package for tree classes, but `treeio` is specifically designed for integration with the `treedata-book` ecosystem.
- **tidytree**: Works alongside `treeio` for tidy data manipulation rather than just input/output.

## Citations
- Guangchuang Yu (2026). "treeio: Base Classes and Functions for Phylogenetic Tree Input and Output".

## References
- Homepage: bioconductor.org/packages/treeio
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/treeio/inst/doc/treeio.html
