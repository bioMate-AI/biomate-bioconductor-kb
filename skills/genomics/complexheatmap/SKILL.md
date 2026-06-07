---
name: bioconductor-complexheatmap
description: Complex heatmaps are efficient to visualize associations between different sources of data sets and reveal potential patterns. Here the ComplexHeatmap package provides a highly flexible way to arrange multiple heatmaps and supports various
when_to_use: Use when: Visualizing global patterns in matrices with a huge number of rows or columns.; Arranging and concatenating multiple heatmaps vertically (using %v%) or horizontally (using +).; Adding complex annotations (e.g., points, barplots) alongside heatmaps or dendrograms using anno_points(), anno_barplot(), and HeatmapAnnotation().; Splitting heatmaps into sub-panels based on k-means clustering or hierarch. Not for: For simple, single heatmaps without annotations where base R heatmap() is sufficient.; When you need a purely client-side interactive web heatmap without an R backend (though InteractiveComplexHeatmap can be used within Shiny).
user-invocable: false
---

# ComplexHeatmap

## When to Use
- Visualizing global patterns in matrices with a huge number of rows or columns.
- Arranging and concatenating multiple heatmaps vertically (using `%v%`) or horizontally (using `+`).
- Adding complex annotations (e.g., points, barplots) alongside heatmaps or dendrograms using `anno_points()`, `anno_barplot()`, and `HeatmapAnnotation()`.
- Splitting heatmaps into sub-panels based on k-means clustering or hierarchical clustering groups.

## When NOT to Use
- For simple, single heatmaps without annotations where base R `heatmap()` is sufficient.
- When you need a purely client-side interactive web heatmap without an R backend (though `InteractiveComplexHeatmap` can be used within Shiny).

## Data Requirements
- A numeric matrix for the main heatmap body.
- Can accept a zero-row or zero-column matrix if you only want to draw dendrograms plus a list of annotations.

## Key Parameters
- **padding**: Used in `draw()` to manually increase the blank areas around the final plot to prevent text from being cut.
- **newpage**: Set to `FALSE` in `draw()` when using `grid.layout()` to manage the layout of multiple panels.
- **row_split**: Splits rows into groups (e.g., passing an integer or a grouping variable from `cutree`).
- **row_km** / **column_km**: Applies k-means clustering to partition rows or columns.
- **row_km_repeats** / **column_km_repeats**: Runs k-means multiple times to get a final consensus clustering.
- **cluster_rows**: Controls row clustering; can accept custom functions like `cluster_within_group()`.
- **right_annotation**: Adds row annotations to the right side of the heatmap using `rowAnnotation()`.
- **heatmap_legend_param**: Controls the style of legends within the `Heatmap()` function.

## Best Practices
- Explicitly use the `draw()` function if no plot appears after running `Heatmap()`.
- For matrices with a huge number of rows or columns, randomly sample them into a reasonably small number to efficiently visualize global patterns.
- Always add `set.seed(...)` before making a heatmap that uses k-means clustering to ensure the random start points yield reproducible results.
- Use `grid.grabExpr(draw(ht))` to capture the heatmap output and later draw it as a single graphic element using `grid.draw()`.

## Common Pitfalls
- **Text cut off by plotting region**: The layout may draw text outside the plotting area. *Fix*: Set the `padding` argument in the `draw()` function to increase blank space.
- **Inconsistent k-means clustering**: Running the script multiple times yields different clusters due to random initialization. *Fix*: Set `row_km_repeats` / `column_km_repeats` to run k-means multiple times for consensus, or use `set.seed()`.
- **Missing axes on dendrograms**: Dendrograms do not have axes by default. *Fix*: Use `decorate_row_dend()` or `decorate_column_dend()` along with `grid.xaxis()` or `grid.yaxis()` to manually add them.
- **Annotation sizing issues**: Simple annotations don't scale correctly. *Fix*: Control simple annotation sizes with `anno_simple_size`, and set `height`/`width` directly inside complex `anno_*()` functions.

## Alternatives
- **pheatmap**: A simpler package for basic annotated heatmaps (ComplexHeatmap can translate pheatmap calls).
- **InteractiveComplexHeatmap**: An extension package specifically for making ComplexHeatmap objects interactive in Shiny.
- **gplots**: Provides `heatmap.2()` for basic heatmaps with a color key and dendrograms.

## Citations
- Gu, Z., Eils, R., & Schlesner, M. (2016). Complex heatmaps reveal patterns and correlations in multidimensional genomic data. Bioinformatics, 32(18), 2847-2849.

## References
- Homepage: https://bioconductor.org/packages/ComplexHeatmap
- Vignette: http://jokergoo.github.io/ComplexHeatmap-reference/book/
