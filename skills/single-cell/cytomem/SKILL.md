---
name: bioconductor-cytomem
description: MEM, Marker Enrichment Modeling, automatically generates and displays quantitative labels for cell populations that have been identified from single-cell data. The input for MEM is a dataset that has pre-clustered or pre-gated populations with cells in rows and features in columns. Labels convey a list of measured features and the features' levels of relative enrichment on each population. MEM can be applied to a wide variety of data types and can compare between MEM labels from flow cytometry,
when_to_use: Use when: Intro_to_Marker_Enrichment_Modeling_Analysis; Single-cell RNA-seq analysis (cytoMEM); Proteomics quantification (cytoMEM); Flow cytometry analysis (cytoMEM). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# cytoMEM

## Workflows

### Standard Workflow

Perform Marker Enrichment Modeling (MEM) analysis on single-cell data to generate quantitative population labels, visualize them via heatmaps, and calculate similarity scores between populations.

```r
library(cytoMEM)
data(PBMC)

# Run MEM analysis on the PBMC dataset
MEM_values <- MEM(
  PBMC,
  transform = TRUE,
  cofactor = 15,
  choose.markers = FALSE,
  markers = "all",
  choose.ref = FALSE,
  zero.ref = FALSE,
  rename.markers = FALSE,
  new.marker.names = "none",
  IQR.thresh = NULL
)

# Generate population labels and heatmaps
build_heatmaps(
  MEM_values,
  cluster.MEM = "both",
  cluster.medians = "none",
  cluster.IQRs = "none",
  display.thresh = 1,
  output.files = FALSE,
  labels = FALSE,
  only.MEMheatmap = FALSE
)

# Calculate similarity (RMSD) scores between populations
MEM_RMSD(
  MEM_values[[5]][[1]],
  format = NULL,
  output.matrix = FALSE
)
```
*Input/Output Note*: Inputs a matrix or data frame of single-cell expression data with a cluster ID column; outputs MEM scores, enrichment labels, heatmaps, and population similarity matrices.

## When to Use
- To automatically generate quantitative, human-readable enrichment labels for pre-clustered or pre-gated cell populations from single-cell data (e.g., mass cytometry or flow cytometry) using `MEM()`.
- To visualize marker enrichment and population medians across clusters using `build_heatmaps()`.
- To compare the similarity of MEM labels across different populations or datasets using root-mean-square deviation (RMSD) via `MEM_RMSD()`.

## When NOT to Use
- For clustering raw single-cell data from scratch; use packages like `Seurat` or `scran` because `cytoMEM` requires pre-clustered or pre-gated populations.
- For differential expression analysis of single-cell RNA-seq data; use `edgeR` or `DESeq2` because `cytoMEM` is designed to generate descriptive enrichment labels rather than statistical hypothesis testing.
- For raw flow cytometry compensation or gating; use `flowCore` because `cytoMEM` expects pre-processed, gated, or clustered expression matrices.

## Data Requirements
- **Input format**: Matrix, data frame, or file paths (`.txt`, `.csv`, `.fcs`).
- **Structure**: Cells in rows, markers/features in columns. The last column must be the cluster ID (unless `file.is.clust = TRUE`).
- **Normalization/Transformation**: Optionally transformed using hyperbolic arcsine (`transform = TRUE` with a specified `cofactor`, e.g., `cofactor = 15` for mass cytometry).

## Key Parameters
- **transform** (`FALSE`): Logical indicating whether to apply a hyperbolic arcsine transformation to the data.
- **cofactor** (`15`): The cofactor used in the hyperbolic arcsine transformation.
- **choose.markers** (`FALSE`): Logical indicating whether to select markers interactively via the console.
- **markers** (`"all"`): Character string specifying which markers to include in the analysis.
- **choose.ref** (`FALSE`): Logical indicating whether to choose an alternative reference population.
- **zero.ref** (`FALSE`): Logical indicating whether to use a zero (synthetic negative) reference.
- **IQR.thresh** (`NULL`): Threshold for interquartile range to avoid artificial inflation of MEM values (defaults internally to `0.5`).
- **display.thresh** (`0`): Numeric value (0-10) specifying the minimum MEM score required for a marker to be displayed.

## Best Practices
- Apply channel-specific transformations prior to running `MEM()` and set `transform = FALSE` if different cofactors are required for different fluorescence channels.
- Keep the default `IQR.thresh` of `0.5` unless you have a deep understanding of the dataset and the implications of changing it.
- Set `labels = TRUE` in `build_heatmaps()` to display the full MEM labels directly on the generated heatmap.
- Save the heatmap as a PDF file (`output.files = TRUE`) to prevent row names (MEM labels) from being cut off due to R window dimensions.

## Common Pitfalls
- **Row names cut off in heatmaps**: Occurs due to R window dimensions. Fix: Set `output.files = TRUE` to save the heatmap as a PDF and open it in a PDF viewer, or read the full labels from the generated `enrichment score-rownames.txt` file.
- **Artificial inflation of MEM values**: Occurs when a population has a very small IQR due to background-level expression. Fix: Ensure `IQR.thresh` is set to at least `0.5` (the default) to threshold low IQR values.
- **Mismatched columns across multiple files**: Occurs when reading multiple files with different formats. Fix: Ensure all files have identical columns (features) and are of the same file type.

## Alternatives
- `Seurat`: For comprehensive single-cell RNA-seq clustering and marker identification using differential expression.
- `scater`: For single-cell quality control and visualization of expression patterns.
- `scran`: For formal statistical testing of marker genes using differential expression.
- `flowCore`: For low-level flow cytometry data import, compensation, and transformation.

## Citations
- Diggins, K. et al. (2017), Nature Methods.

## References
- Homepage: bioconductor.org/packages/cytoMEM
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cytoMEM/inst/doc/Intro_to_Marker_Enrichment_Modeling_Analysis.html
