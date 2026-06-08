---
name: bioconductor-complexheatmap
description: Complex heatmaps are efficient to visualize associations between different sources of data sets and reveal potential patterns. Here the ComplexHeatmap package provides a highly flexible way to arrange multiple heatmaps and supports various
when_to_use: Use when: When visualizing high-dimensional genomic datasets (such as RNA-seq, microarrays, or multi-omics) where associations between different data sources (like clinical annotations, pathway scores, and expression levels) need to be aligned and visualized simultaneously.
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

- **`cluster_rows/cluster_columns`**: Can take a hierarchical clustering object, a function, or a pre-clustered group-level dendrogram using cluster_within_group() to simplify large matrices
- **`row_split/column_split`**: Splits the heatmap rows/columns into slices, which is highly recommended when using group-level clustering or k-means
- **`row_km/column_km`**: Performs k-means clustering on rows/columns; requires set.seed() or row_km_repeats/column_km_repeats for reproducibility
- **`row_km_repeats/column_km_repeats`**: Runs k-means multiple times to obtain a consensus clustering
- **`padding`**: Adjusts the blank area around the final plot in draw() to prevent text clipping
- **`newpage`**: Set to FALSE in draw() when managing layouts manually with grid viewports
- **`axis_param`**: Controls annotation axes inside anno_*() functions
- **`heatmap_legend_param/annotation_legend_param`**: Controls legend styles using parameters from the Legend() function

## Workflow Variants

### Group Level Clustering

**Intent**: Group rows into several clusters and make a group-level dendrogram to simplify visualization of large matrices.

**Inputs**:
- `matrix (numeric matrix of genomic data, e.g., gene expression)`

**Steps**:
1. Perform hierarchical clustering on the matrix
2. Cut the dendrogram into a specified number of groups
3. Generate a heatmap using cluster_within_group and split rows

```r
m = matrix(rnorm(1000*10), nr = 1000)
hc = hclust(dist(m))
group = cutree(hc, k = 6)
Heatmap(m, cluster_rows = cluster_within_group(t(m), group), 
	row_split = 6, border = TRUE) # it would be better if also set row_split
```


---

### Custom Dendrogram Axes

**Intent**: Draw a heatmap and manually add customized axes to the row and column dendrograms.

**Inputs**:
- `matrix (numeric matrix of genomic data)`

**Steps**:
1. Define a heatmap with custom row and column dendrogram dimensions
2. Draw the heatmap with padding to prevent text clipping
3. Use decorate_column_dend and decorate_row_dend to add custom axes

```r
m = matrix(rnorm(100), 10)

ht = Heatmap(m, name = "foo", 
	row_dend_width = unit(4, "cm"),
	column_dend_height = unit(4, "cm")
)
draw(ht, padding = unit(c(15, 2, 2, 2), "mm"))
decorate_column_dend("foo", {
	grid.yaxis()
})
decorate_row_dend("foo", {
	vp = current.viewport()
	xscale = vp$xscale
	grid.xaxis(at = xscale[2] - 0:5, label = 0:5)
})
```


---

### Annotations Only

**Intent**: Visualize dendrograms and multiple annotations without displaying a main heatmap body.

**Inputs**:
- `matrix (numeric matrix used to compute the dendrogram)`

**Steps**:
1. Compute hierarchical clustering on the input matrix
2. Create a zero-column matrix to act as the heatmap body
3. Draw the heatmap with the zero-column matrix, the computed dendrogram, and row annotations

```r
hc = hclust(dist(matrix(rnorm(100), 10)))
Heatmap(matrix(nc = 0, nr = 10), cluster_rows = hc, 
	right_annotation = rowAnnotation(
		foo = anno_points(1:10),
		sth = 1:10,
		bar = anno_barplot(1:10)),
	row_split = 2)
```


## Best Practices

- Explicitly use the `draw()` function if no plot appears after running `Heatmap()`.
- For matrices with a huge number of rows or columns, randomly sample them into a reasonably small number to efficiently visualize global patterns.
- Always add `set.seed(...)` before making a heatmap that uses k-means clustering to ensure the random start points yield reproducible results.
- Use `grid.grabExpr(draw(ht))` to capture the heatmap output and later draw it as a single graphic element using `grid.draw()`.

## Common Pitfalls

- No plot output can occur if draw() is not called explicitly in non-interactive scripts or complex layouts
- Text clipping at the plotting region boundaries can occur, which is solved by setting padding in draw()
- Unstable k-means clustering results across runs can occur if row_km or column_km are used without setting a random seed (set.seed()) or using row_km_repeats/column_km_repeats
- Incorrect annotation sizing can occur if width/height of complex annotations (anno_*()) are set in the main HeatmapAnnotation instead of inside the specific anno_*() function.

## Alternatives

- **pheatmap**: A simpler heatmap package; ComplexHeatmap provides translation support (e.g., compare_pheatmap) for users migrating from pheatmap
- **InteractiveComplexHeatmap**: Used to create interactive heatmaps instead of static ones

## Citations

- Gu, Z., Eils, R., & Schlesner, M. (2016). Complex heatmaps reveal patterns and correlations in multidimensional genomic data. Bioinformatics, 32(18), 2847-2849.

## References

- Homepage: https://bioconductor.org/packages/ComplexHeatmap
- Vignette: http://jokergoo.github.io/ComplexHeatmap-reference/book/
