---
name: bioconductor-spotclean
description: SpotClean is a computational method to adjust for spot swapping in spatial transcriptomics data. Recent spatial transcriptomics experiments utilize slides containing thousands of spots with spot-specific barcodes that bind mRNA. Ideally, unique molecular identifiers at a spot measure spot-specific expression, but this is often not the case due to bleed from nearby spots, an artifact we refer to as spot swapping. SpotClean is able to estimate the contamination rate in observed data and decontamin
when_to_use: Use when: SpotClean; Single-cell RNA-seq analysis (SpotClean). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# SpotClean

## Workflows

### Standard Workflow

Load raw 10x Visium Space Ranger output, perform decontamination, visualize results, and convert to a Seurat object.

```r
library(SpotClean)
library(S4Vectors)

# 1. Load raw data and slide information
data(mbrain_raw)
spatial_dir <- system.file(file.path("extdata", "V1_Adult_Mouse_Brain_spatial"), package = "SpotClean")
mbrain_slide_info <- read10xSlide(
  tissue_csv_file = file.path(spatial_dir, "tissue_positions_list.csv"),
  tissue_img_file = file.path(spatial_dir, "tissue_lowres_image.png"),
  scale_factor_file = file.path(spatial_dir, "scalefactors_json.json")
)

# 2. Create the slide object
slide_obj <- createSlide(count_mat = mbrain_raw, slide_info = mbrain_slide_info)

# 3. Visualize raw data
visualizeSlide(slide_obj = slide_obj)
visualizeHeatmap(slide_obj, "Mbp")

# 4. Decontaminate raw data
decont_obj <- spotclean(slide_obj, maxit = 10, candidate_radius = 20)

# 5. Visualize decontaminated gene and contamination rate
visualizeHeatmap(decont_obj, "Mbp")
visualizeHeatmap(
  decont_obj, 
  metadata(decont_obj)$contamination_rate,
  logged = FALSE, 
  legend_title = "contamination rate",
  legend_range = c(0, 1)
)

# 6. Convert to Seurat object
seurat_obj <- convertToSeurat(decont_obj, image_dir = spatial_dir)
```
Input: Raw count matrix and 10x Visium slide metadata. Output: A decontaminated Seurat object ready for downstream analysis.

### Spatial Experiment Workflow

Decontaminate spatial transcriptomics data stored in a SpatialExperiment object.

```r
library(SpotClean)
library(SpatialExperiment)

# Assuming slide_obj is a SpatialExperiment loaded with read10xVisium(..., data = "raw")
# slide_obj <- read10xVisium(samples = "/path/to/spaceranger/output/", data = "raw")
# decont_obj <- spotclean(slide_obj)
```
Input: A `SpatialExperiment` object containing raw spatial transcriptomics data. Output: A decontaminated `SpatialExperiment` object.

## When to Use
- Adjusting for spot swapping (mRNA bleed) in 10x Visium spatial transcriptomics data using `spotclean()`.
- Estimating the ambient RNA contamination lower bound in spatial transcriptomics or droplet-based single-cell data using `arcScore()`.
- Visualizing spatial spot labels and gene expression heatmaps in 2-D slide space using `visualizeLabel()` and `visualizeHeatmap()`.
- Converting decontaminated slide objects into Seurat spatial objects using `convertToSeurat()`.

## When NOT to Use
- When almost all spots on the slide are covered by tissue (less than 25% background spots), as `spotclean()` relies on background spots to estimate contamination.
- For normalizing sequencing depth directly, as `spotclean()` reassigns UMIs and changes estimated sequencing depth, which may conflict with standard depth normalization.
- For analyzing extremely lowly-expressed genes with high sparsity, where there is insufficient information to confidently reassign UMIs.

## Data Requirements
- Raw gene-by-spot count matrix (e.g., loaded via `read10xRaw()`).
- Slide metadata including spot positions, scale factors, and low-resolution tissue images (e.g., loaded via `read10xSlide()`).
- Alternatively, a `SpatialExperiment` object constructed with `data = "raw"`.

## Key Parameters
- **count_mat**: The raw gene-by-spot count matrix passed to `createSlide()`.
- **slide_info**: Slide metadata list passed to `createSlide()`.
- **maxit** (`30`): Maximum number of iterations for the decontamination optimization in `spotclean()`.
- **candidate_radius**: Candidate contamination search radius evaluated by `spotclean()`.
- **image_dir**: Directory containing spatial images passed to `convertToSeurat()`.
- **logged** (`TRUE`): Logical flag in `visualizeHeatmap()` to apply log-scaling to the heatmap values.

## Best Practices
- Ensure that the input dataset has at least 25% of spots unoccupied by tissue to allow robust contamination estimation from background spots.
- Always use raw (unfiltered) count matrices as input to `spotclean()`, specifying `data = "raw"` if loading via `read10xVisium()`.
- Visualize raw gene expression using `visualizeHeatmap()` before and after running `spotclean()` to verify the reduction of background noise.

## Common Pitfalls
- *Insufficient background spots*: Running `spotclean()` on slides with nearly 100% tissue coverage leads to unreliable contamination estimates; ensure at least 25% of spots are background.
- *Applying to pre-filtered/normalized data*: Using normalized or tissue-selected counts instead of raw counts; fix by loading raw data with `read10xRaw()` or `read10xVisium(..., data = "raw")`.

## Alternatives
- `Seurat`: For general spatial transcriptomics downstream analysis and clustering.
- `scater`: For single-cell and spatial QC and visualization.
- `scran`: For variance modeling and normalization of single-cell/spatial data.

## Citations
- Ni, Z., Prasad, A., Chen, S. et al. SpotClean adjusts for spot swapping in spatial transcriptomics data. Nat Commun 13, 2971 (2022). https://doi.org/10.1038/s41467-022-30587-y

## References
- Homepage: bioconductor.org/packages/spotclean
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/spotclean/inst/doc/SpotClean.html
