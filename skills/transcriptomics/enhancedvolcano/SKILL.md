---
name: bioconductor-enhancedvolcano
description: Volcano plots represent a useful way to visualise the results of differential expression analyses. Here, we present a highly-configurable function that produces publication-ready volcano plots. EnhancedVolcano will attempt to fit as many po
when_to_use: Use when: Publication-Ready Visualization: Creating highly-configurable volcano plots from differential expression results using the EnhancedVolcano() function.; Targeted Gene Labeling: Visualizing specific genes of interest by supplying a vector of variables to the selectLab parameter.; Highlighting Key Variables: Emphasizing specific points by encircling them or shading them using the encircle and shade p. Not for: For performing differential expression analysis: Use DESeq2 (e.g., DESeq() and results()) instead, because EnhancedVolcano only visualizes the statistical output.; For mapping gene identifiers: Use mapIds() from AnnotationDbi instead, as EnhancedVolc
user-invocable: false
---

# EnhancedVolcano

## When to Use
- **Publication-Ready Visualization**: Creating highly-configurable volcano plots from differential expression results using the `EnhancedVolcano()` function.
- **Targeted Gene Labeling**: Visualizing specific genes of interest by supplying a vector of variables to the `selectLab` parameter.
- **Highlighting Key Variables**: Emphasizing specific points by encircling them or shading them using the `encircle` and `shade` parameters.

## When NOT to Use
- **For performing differential expression analysis**: Use `DESeq2` (e.g., `DESeq()` and `results()`) instead, because EnhancedVolcano only visualizes the statistical output.
- **For mapping gene identifiers**: Use `mapIds()` from `AnnotationDbi` instead, as EnhancedVolcano requires the labels to be pre-formatted and mapped before plotting.

## Data Requirements
- A data-frame, data-matrix, or tibble of test results containing point labels, log2 fold changes, and adjusted or unadjusted P values.

## Key Parameters
- **lab**: A vector of point labels (e.g., `rownames(res)`).
- **x**: The column name in the results object containing log2 fold changes (e.g., 'log2FoldChange').
- **y**: The column name in the results object containing P values (e.g., 'pvalue').
- **pCutoff** (10e-6): The statistical significance threshold for P values.
- **FCcutoff** (2.0): The threshold for absolute log2 fold changes.
- **drawConnectors**: A logical indicating whether to add connectors from labels to points to maximize free space.
- **colCustom**: A named vector of custom key-value pairs to over-ride the default colour scheme.
- **boxedLabels**: A logical indicating whether to draw simple boxes around the plot's labels to improve clarity.

## Best Practices
- Use `lfcShrink()` from `DESeq2` to obtain moderated 'shrunk' estimates of log2FC differences before plotting.
- Set `drawConnectors = TRUE` to fit more labels in the plot window without overcrowding the points.
- Use `parseLabels = TRUE` along with `italic()` to parse and present labels as italicised text.
- Disable default gridlines (`gridlines.major = FALSE`, `gridlines.minor = FALSE`) to make extra threshold lines (`hline`, `vline`) more visible.

## Common Pitfalls
- **Overcrowded labels**: Too many significant genes can clog up the plot. *Fix*: Use the `selectLab` parameter to only label key variables of interest.
- **Legend taking up too much space**: The default legend might obscure data. *Fix*: Change `legendPosition` to 'none' to make the legend completely invisible.
- **Missing dependencies for encircling**: Attempting to encircle points without the required dependencies will fail. *Fix*: Ensure the `ggalt` package is installed before using the `encircle` parameter.

## Alternatives
- **ggplot2**: The underlying engine for EnhancedVolcano, which can be used directly for fully custom plots but requires more manual configuration for label repulsion and cutoffs.
- **ggrepel**: Provides the label repulsion engine used internally by EnhancedVolcano, useful if building a custom volcano plot from scratch.

## Citations
- Blighe, K, S Rana, and M Lewis. 2018. “EnhancedVolcano: Publication-ready volcano plots with enhanced colouring and labeling.” https://github.com/kevinblighe/EnhancedVolcano.

## References
- Homepage: https://bioconductor.org/packages/EnhancedVolcano
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/EnhancedVolcano/inst/doc/EnhancedVolcano.pdf
