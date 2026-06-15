---
name: bioconductor-escher
description: The creation of effective visualizations is a fundamental component of data analysis. In biomedical research, new challenges are emerging to visualize multi-dimensional data in a 2D space, but current data visualization tools have limited capabilities. To address this problem, we leverage Gestalt principles to improve the design and interpretability of multi-dimensional data in 2D data visualizations, layering aesthetics to display multiple variables. The proposed visualization can be applied to
when_to_use: Use when: The creation of effective visualizations is a fundamental component of data analysis; install bioc using install; install github using install_github, install; data.import using Visium_humanDLPFC; create plot using make_escheR; creat fill using add_fill. Not for: Requires R ≥ 4.3
user-invocable: false
---

# escheR

## Workflows

### Standard Workflow

Visualize multi-dimensional spatial transcriptomics data from a SpatialExperiment or SingleCellExperiment object by adding layered fill, ground, and symbol aesthetics.

```r
library(escheR)
library(STexampleData)

# 1. Read the input SpatialExperiment object
spe <- Visium_humanDLPFC()
spe <- spe[, spe$in_tissue == 1]
spe <- spe[, !is.na(spe$ground_truth)]

# 2. Create plot and add layered aesthetics
p <- make_escheR(spe) |>
  add_fill(var = "cell_count") |>
  add_ground(var = "ground_truth") |>
  add_symbol(var = "ground_truth", size = 0.2)

# 3. Save the generated plots to the working directory
ggplot2::ggsave(filename = "standard_plot.pdf", plot = p)
```
Input: A `SpatialExperiment` object `spe`. Output: A saved PDF plot showing layered spatial aesthetics.

### Binned Spatial Visualization

Visualize high-density spatial transcriptomics data using point binning to avoid overplotting.

```r
library(escheR)
library(STexampleData)

# 1. Read the user input file
spe <- Visium_humanDLPFC()
spe <- spe[, spe$in_tissue == 1]
spe <- spe[, !is.na(spe$ground_truth)]

# 2. Ensure the SpatialExperiment object has the required columns and factor types
spe$counts_MOBP <- counts(spe)[which(rowData(spe)$gene_name == "MOBP"), ]
spe$ground_truth <- factor(spe$ground_truth)

# 3. Create binned plot and save to a PDF file
p <- make_escheR(spe, dimred = "PCA") |>
  add_ground_bin(var = "ground_truth") |>
  add_fill_bin(var = "counts_MOBP") +
  scale_fill_gradient(low = "white", high = "black", name = "MOBP Count") +
  scale_color_discrete(name = "Spatial Domains")

ggplot2::ggsave(filename = "binned_plot.pdf", plot = p)
```
Input: A `SpatialExperiment` object `spe` with PCA reduced dimensions. Output: A saved PDF plot with binned spatial points.

### Dataframe Visualization

Visualize multi-dimensional data from a generic R data.frame (e.g., exported from Seurat) using custom x and y coordinates.

```r
library(escheR)

# Create a generic data.frame with coordinates and metadata
df <- data.frame(
  x = c(1, 2, 3),
  y = c(4, 5, 6),
  groups = c("A", "B", "A")
)

# Call generic function for make_escheR.data.frame
p <- make_escheR(object = df, .x = df$x, .y = df$y) |>
  add_fill(var = "groups")
```
Input: A standard R `data.frame` with coordinate columns. Output: A ggplot object.

## When to Use
- Visualizing multi-dimensional spatial transcriptomics data (e.g., from 10x Visium, seqFISH, or Slide-seq V2) by layering aesthetics.
- Plotting dimensionality reduced embeddings (e.g., PCA) from a `SpatialExperiment` or `SingleCellExperiment` using `make_escheR(spe, dimred = "PCA")`.
- Visualizing high-density spatial data using point binning with `add_ground_bin()` and `add_fill_bin()`.
- Visualizing spatial or embedding data from a generic R `data.frame` using `make_escheR(object, .x, .y)`.

## When NOT to Use
- For complex multi-sample joint analysis or alignment, use packages like `Seurat` or `Giotto` because `escheR` operates on single samples by design.
- For advanced cell-cell communication or spatial ligand-receptor analysis, use specialized packages as `escheR` is strictly a visualization tool.

## Data Requirements
- Input can be a `SpatialExperiment`, `SingleCellExperiment`, or a base R `data.frame`.
- For `SpatialExperiment`, spatial coordinates must be present (e.g., accessed via `spatialCoords(spe)`).
- For `data.frame` input, explicit numeric vectors for x and y coordinates must be provided to `.x` and `.y`.

## Key Parameters
- **object**: The input data object (`SpatialExperiment`, `SingleCellExperiment`, or `data.frame`).
- **dimred** (NULL): Name of the reduced dimension slot to use for coordinates instead of spatial coordinates.
- **.x**: Numeric vector of x coordinates (for `data.frame` input).
- **.y**: Numeric vector of y coordinates (for `data.frame` input).
- **var**: Character string specifying the column name in `colData` or `data.frame` to map to an aesthetic layer.
- **stroke** (0.5): Border stroke size for the ground layer.
- **size** (0.2): Size of the symbols in the symbol layer.

## Best Practices
- Always apply `add_fill()` as the first layer before other `add_*` functions to achieve the best visual effect due to the layering mechanism.
- When using binning to avoid overplotting, apply `add_fill_bin()` after `add_ground_bin()` for a better visualization outcome.
- Trim down `colData(spe)` before piping into `make_escheR()` to reduce computation time, especially when it contains a large number of irrelevant columns.
- Use minimally overlapping color palettes (e.g., a white-to-black gradient for continuous gene expression and qualitative colors for spatial domains) to avoid visual confusion.

## Common Pitfalls
- *Overlapping color spaces*: Using default viridis for both fill and ground makes them indistinguishable; fix by using a white-to-black gradient for continuous variables via `scale_fill_gradient(low = "white", high = "black")`.
- *Large number of categories*: Visualizing too many categorical levels creates clutter; fix by subsetting levels (setting unwanted to `NA`) or using `add_symbol()` to annotate specific levels.
- *Binning membership mixing*: Point binning can lead to intermixing of cluster memberships; interpret carefully as the majority membership is selected as the bin label.

## Alternatives
- `Seurat` for comprehensive single-cell and spatial transcriptomics workflows.
- `scater` for single-cell visualization and quality control.
- `scran` for single-cell data analysis and variance modeling.

## Citations
- Boyi Guo and Stephanie C. Hicks (2024). escheR: unified multi-dimensional spatial visualizations. Bioinformatics Advances.

## References
- Homepage: bioconductor.org/packages/escheR
- Vignette: bioconductor.org/packages/release/bioc/vignettes/escheR/inst/doc/escheR.html
