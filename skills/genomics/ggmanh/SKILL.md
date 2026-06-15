---
name: bioconductor-ggmanh
description: Manhattan plot and QQ Plot are commonly used to visualize the end result of Genome Wide Association Study. The "ggmanh" package aims to keep the generation of these plots simple while maintaining customizability. Main functions include manhattan_plot, qqunif, and thinPoints.
when_to_use: Use when: Manhattan plot and QQ Plot are commonly used to visualize the end result of Genome Wide Association Study; manh minimum using manhattan_plot; simdata w signif using rbind; manh badscale using manhattan_plot; manh goodscale using manhattan_plot; plot labelled data biglabel using manhattan_data_preprocess, manhattan_plot. Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# ggmanh

## Workflows

### Standard Workflow

```r
library(ggmanh)
# Format chromosome column as a factor
simdata$chromosome <- factor(simdata$chromosome, c(1:22,"X"))
# Generate standard Manhattan plot
g1 <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
# Generate rescaled Manhattan plot
g2 <- manhattan_plot(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", rescale = TRUE)
# Preprocess data
mpdata <- manhattan_data_preprocess(x = simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
# Generate plots using preprocessed data with labels
g3 <- manhattan_plot(x = mpdata, label.colname = "label")
# Zoom into Chromosome 5
manhattan_plot(simdata, chromosome = 5, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
```
*Note*: Input is a data frame of GWAS summary statistics; output is a customized Manhattan plot object.

### Binned Manhattan Plot

```r
library(ggmanh)
# Basic Binned Manhattan Plot
binned_manhattan_plot(simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
# Preprocess binned data
mpdat <- binned_manhattan_preprocess(simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", bins.x = 7, bins.y = 100)
# Plot preprocessed binned data
binned_manhattan_plot(mpdat, bin.outline = TRUE)
```
*Note*: Input is a data frame of GWAS summary statistics; output is a binned grid-based Manhattan plot.

### Gds Variant Annotation Plotting

```r
library(ggmanh)
# Annotate variants using gds_annotate
simdata_label$label <- gds_annotate(x = simdata_label, annot.method = "position", chr = "chromosome", pos = "position", ref = "Reference", alt = "Alternate")
# Plot annotated data
manhattan_plot(simdata_label, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", label.colname = "label")
```
*Note*: Inputs are a data frame of GWAS summary statistics and a GDS file; output is an annotated Manhattan plot.

## When to Use
- To visualize Genome Wide Association Study (GWAS) results using standard Manhattan plots (`manhattan_plot`).
- To rescale the y-axis of a Manhattan plot when highly significant p-values mask lower-significance patterns (`rescale = TRUE`).
- To create binned grid-based Manhattan plots for extremely large datasets to avoid plotting individual points (`binned_manhattan_plot`).
- To annotate variants with gene/consequence information from a GDS file using `gds_annotate`.

## When NOT to Use
- When using discrete palettes for continuous variables (or vice versa) in `binned_manhattan_plot`, as the plot will fail.

## Data Requirements
- **Input data frame**: Must contain at least three columns representing chromosome, position, and p-value.
- **Chromosome column**: Recommended to be formatted as a factor to avoid ambiguity in plotting order.
- **GDS file**: For variant annotation, a SeqArray-formatted GDS file containing annotations (e.g., `annotation/symbol`, `annotation/consequence`).

## Key Parameters
- **x**: A data.frame, MPdata, or GRanges object containing the GWAS results.
- **pval.colname**: Name of the column containing p-values.
- **chr.colname**: Name of the column containing chromosomes.
- **pos.colname**: Name of the column containing genomic positions.
- **rescale** (FALSE): Logical indicating whether to rescale the y-axis near the significance cutoff.
- **label.colname**: Name of the column containing labels for annotation.
- **chromosome**: Specific chromosome number/name to zoom into.
- **bins.x**: Number of horizontal bins for the widest chromosome in binned plots.

## Best Practices
- Convert the chromosome column to a factor before plotting to ensure correct ordering on the x-axis.
- Preprocess data using `manhattan_data_preprocess` or `binned_manhattan_preprocess` first if you plan to customize the plot multiple times, avoiding redundant computation.
- Set non-significant labels to `""` or `NA` to avoid overlapping labels and extremely slow plotting times.

## Common Pitfalls
- Attempting to label all points: This can cause the plotting process to take hours. Set labels for non-significant points to `""` or `NA`.
- Using incompatible palettes: Ensure continuous palettes are used for continuous variables and discrete palettes for discrete variables in `binned_manhattan_plot`.

## Alternatives
- `qqman` for basic Manhattan and QQ plots.

## References
- Homepage: bioconductor.org/packages/ggmanh
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ggmanh/inst/doc/ggmanh.html
