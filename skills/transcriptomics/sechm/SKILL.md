---
name: bioconductor-sechm
description: sechm provides a simple interface between SummarizedExperiment objects and the ComplexHeatmap package. It enables plotting annotated heatmaps from SE objects, with easy access to rowData and colData columns, and implements a number of features to make the generation of heatmaps easier and more flexible. These functionalities used to be part of the SEtools package.
when_to_use: Use when: sechm provides a simple interface between SummarizedExperiment objects and the ComplexHeatmap package. Not for: Requires R ≥ 4.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# sechm

## Workflows

### Standard Workflow

sechm provides a simple interface between SummarizedExperiment objects and the ComplexHeatmap package. It enables plotting annotated heatmaps from SE objects, with easy access to rowData and colData columns, and implements a number of features to make the generation of heatmaps easier and more flexible.

```r
library(SummarizedExperiment)
library(sechm)

# Load example data
data("Chen2017", package="sechm")
SE <- Chen2017

# 1. Basic scaled heatmap of top variable genes
g <- c("Egr1", "Nr4a1", "Fos", "Egr2", "Sgk1", "Arc", "Dusp1", "Fosb", "Sik1")
sechm(SE, features=g, do.scale=TRUE)

# 2. Heatmap of Log2 Fold Changes with quantile capping (breaks)
sechm(SE, features=g, assayName="logFC", breaks=0.985)

# 3. Customizing colors using global package options
setSechmOption("hmcols", value=c("white","grey","black"))
sechm(SE, features=g, do.scale=TRUE)
resetAllSechmOptions()
```
*Input: A SummarizedExperiment object and a vector of feature names. Output: A Heatmap object from ComplexHeatmap.*

## When to Use
- To plot highly customizable, annotated heatmaps directly from `SummarizedExperiment` objects using `sechm()`.
- To display row and column annotations automatically extracted from `rowData` and `colData` (e.g., `top_annotation`, `left_annotation`).
- To combine multiple heatmaps from different `SummarizedExperiment` objects with aligned rows and consistent scales using `crossHm()`.
- To highlight specific genes of interest on a large heatmap using the `mark` argument.

## When NOT to Use
- For plotting heatmaps from raw matrices or data frames without a `SummarizedExperiment` container, use `ComplexHeatmap::Heatmap` or `pheatmap` directly.

## Data Requirements
- A `SummarizedExperiment` object containing at least one assay (e.g., `"logcpm"`, `"logFC"`).
- Row annotations stored in `rowData(SE)` and column annotations stored in `colData(SE)`.

## Key Parameters
- **features**: A vector of row/feature names to plot.
- **assayName**: Name of the assay to extract data from (e.g., `"logFC"`).
- **do.scale** (`FALSE`): Logical indicating whether to scale rows.
- **top_annotation**: Column names from `colData` to display as top annotations.
- **left_annotation**: Column names from `rowData` to display as left annotations.
- **breaks** (`TRUE`): Controls symmetric scaling and quantile capping (e.g., `0.985` for 98.5% quantile capping).
- **gaps_at**: Column name from `colData` to introduce gaps between columns.
- **uniqueScale** (`FALSE`): Logical indicating whether to enforce a unique color scale across datasets in `crossHm()`.

## Best Practices
- Store default visualization settings (like default assay and annotations) in the object's metadata under `metadata(SE)$default_view` to simplify repetitive plotting.
- Use quantile capping (e.g., `breaks=0.985`) when plotting fold-changes to prevent extreme outlier values from dominating the color scale.
- Define custom annotation colors in `metadata(SE)$anno_colors` to ensure they are automatically applied across all heatmaps generated from that object.

## Common Pitfalls
- Extreme values compressing the color scale: Outliers in fold-change data can make normal variations invisible. Fix: Set `breaks` to a quantile value less than 1 (e.g., `breaks=0.985`) to cap the color scale.
- Duplicate heatmap or annotation names when combining heatmaps with `+`: Combining raw `sechm` objects can lead to conflicts. Fix: Use `crossHm()` to safely plot multiple `SummarizedExperiment` objects side-by-side.

## Alternatives
- `ComplexHeatmap`: The underlying engine, but requires manual extraction of assays and annotations from `SummarizedExperiment`.
- `pheatmap`: A classic heatmap package, but lacks native integration with `SummarizedExperiment` metadata.

## Citations
- Chen et al., 2017 (vignette reference for example data).

## References
- Homepage: bioconductor.org/packages/sechm
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/sechm/inst/doc/sechm.html
