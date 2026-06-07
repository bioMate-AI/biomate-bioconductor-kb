---
name: bioconductor-geneplotter
description: Functions for plotting genomic data
when_to_use: Use when: Visualizing microarray or high-throughput genomic data along chromosomes using cPlot and cColor.; Plotting characteristics of expression levels over contiguous regions of a single chromosome using alongChrom.; Assembling and plotting chromLocation objects to map experimental probe data to physical chromosome locations via buildChromLocation.. Not for: For modern, highly customizable genomic track visualizations (e.g., plotting RNA-seq coverage, BAM alignments, and gene annotations together), use Gviz or ggbio instead.; For general-purpose high-dimensional data visualization (like PCA, t-SNE, or vo
user-invocable: false
---

# geneplotter

Functions for plotting genomic data.

## When to Use
- Visualizing microarray or high-throughput genomic data along chromosomes using `cPlot` and `cColor`.
- Plotting characteristics of expression levels over contiguous regions of a single chromosome using `alongChrom`.
- Assembling and plotting `chromLocation` objects to map experimental probe data to physical chromosome locations via `buildChromLocation`.

## When NOT to Use
- For modern, highly customizable genomic track visualizations (e.g., plotting RNA-seq coverage, BAM alignments, and gene annotations together), use `Gviz` or `ggbio` instead.
- For general-purpose high-dimensional data visualization (like PCA, t-SNE, or volcano plots), use `ggplot2` or `ComplexHeatmap` instead.

## Data Requirements
- **Input**: `ExpressionSet` objects (e.g., `sample.ExpressionSet`) or numeric matrices of genomic data.
- **Annotation**: Requires annotation packages (e.g., `hu6800.db`, `hgu95av2.db`) to build `chromLocation` objects and map probe IDs to chromosomal coordinates.

## Key Parameters
- **useChroms**: A character vector specifying which chromosomes to plot in `cPlot`.
- **plotFormat**: Format of the plot in `alongChrom` (e.g., `"cumulative"`).
- **col**: Color vector for distinguishing chromosomes or experimental groups in `cColor` or `alongChrom`.

## Best Practices
- Use `buildChromLocation` with the appropriate Bioconductor annotation package name (e.g., `"hu6800"`, `"hgu95av2"`) to construct the `chromLocation` object.
- Reorder chromosomes in the `chromLocation` object numerically before plotting with `cPlot` to ensure a logical layout.
- Set up appropriate device dimensions (e.g., using `layout` or `par`) when using `cPlot` to ensure chromosome labels and data points do not overlap.

## Common Pitfalls
- **Mismatched genome builds**: Mapping probe data using an outdated annotation package while comparing to coordinates from a newer genome build. *Fix*: Double-check the source of the metadata and use matching Bioconductor annotation packages.
- **Genes mapped to multiple chromosomes**: Some genes (e.g., in pseudoautosomal regions) may map to multiple chromosomes, causing issues. *Fix*: Filter or assign these genes to a single chromosome before building the location object.

## Alternatives
- **Gviz**: For plotting highly customizable, publication-quality genomic tracks.
- **ggbio**: For grammar-of-graphics based genomic data visualization.
- **RIdeogram**: For idiogram-based visualization of genome-wide data across chromosomes.

## Citations
- Gentleman R. (2023). "geneplotter: Graphic related functions for Bioconductor." *R package version 1.84.0*.

## References
- Homepage: https://bioconductor.org/packages/geneplotter
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/geneplotter/inst/doc/visualizing.pdf
