---
name: bioconductor-simpleseg
description: Image segmentation is the process of identifying the borders of individual objects (in this case cells) within an image. This allows for the features of cells such as marker expression and morphology to be extracted, stored and analysed. simpleSeg provides functionality for user friendly, watershed based segmentation on multiplexed cellular images in R based on the intensity of user specified protein marker channels. simpleSeg can also be used for the normalization of single cell data obtained f
when_to_use: Use when: "Introduction to simpleSeg"; Single-cell RNA-seq analysis (simpleSeg); Data normalization and preprocessing (simpleSeg). Not for: Requires R ≥ 3.5.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# simpleSeg

## Workflows

### Standard Workflow

Segment multiplexed images to identify cell boundaries, extract single-cell features, and normalize marker intensities.

```r
library(simpleSeg)
library(cytomapper)
library(EBImage)

# Load example data path
pathToImages <- system.file("extdata", package = "simpleSeg")
imageDirs <- dir(pathToImages, "Point", full.names = TRUE)
names(imageDirs) <- dir(pathToImages, "Point", full.names = FALSE)
files <- lapply(imageDirs, list.files, pattern = "tif", full.names = TRUE)
images <- lapply(files, EBImage::readImage, as.is = TRUE)
images <- cytomapper::CytoImageList(images)
mcols(images)$imageID <- names(images)

# Segment images
masks <- simpleSeg::simpleSeg(images, nucleus = "HH3", transform = "sqrt")

# Summarise cell features
cellSCE <- cytomapper::measureObjects(masks, images, img_id = "imageID")

# Normalize cells
cellSCE <- normalizeCells(
  cellSCE,
  assayIn = "counts",
  assayOut = "norm",
  imageID = "imageID",
  transformation = "sqrt",
  method = c("trim99", "minMax")
)
```
*Input: Multiplexed TIFF images (as CytoImageList); Output: Segmented masks (CytoImageList) and normalized single-cell feature matrices (SingleCellExperiment).*

## When to Use
- Segmenting multiplexed cellular images (e.g., MIBI-TOF) using a watershed-based approach with `simpleSeg::simpleSeg()`.
- Extracting single-cell marker intensities and morphological features into a `SingleCellExperiment` using `cytomapper::measureObjects()`.
- Normalizing and transforming extracted single-cell marker intensities using `normalizeCells()`.

## When NOT to Use
- For segmenting non-imaging single-cell data (like standard scRNA-seq), use `scran` or `Seurat` because simpleSeg is specifically designed for multiplexed imaging data.
- For highly complex deep-learning-based cell segmentation, use external tools like Cellpose or Mesmer because simpleSeg relies on classical watershed algorithms.

## Data Requirements
- Multiplexed cellular images loaded as an `Image`, list of `Image`s, or `CytoImageList` (from `cytomapper`).
- Images should contain a nuclear marker channel (e.g., "HH3") for watershed seeding.

## Key Parameters
- **nucleus**: The name or index of the channel to use as the nuclear marker.
- **transform** (NULL): Image transformation to apply before segmentation (e.g., "sqrt").
- **cores** (1): Number of cores to use for parallel processing.
- **watershed** ("combine"): Method for watershedding ("distance", "intensity", or "combine").
- **cellBody** ("dilation"): Method for cell body identification ("dilation", "discModel", "marker", or "None").
- **assayIn** ("counts"): Input assay name in `normalizeCells()`.
- **assayOut** ("norm"): Output assay name in `normalizeCells()`.

## Best Practices
- Visualise segmentation performance using `EBImage::display(colorLabels(masks[[1]]))` or `cytomapper::plotPixels()` to verify cell boundaries.
- Apply a transformation like `"sqrt"` to the nuclear channel to improve watershed segmentation on highly skewed intensity distributions.
- Perform quality control on normalization by plotting marker density distributions (e.g., using `ggplot2` and `geom_density()`) before and after running `normalizeCells()`.

## Common Pitfalls
- Highly skewed marker intensities: Raw intensities can be extremely skewed, making clustering difficult; fix this by applying `normalizeCells()` with `method = c("trim99", "minMax")`.
- Incorrect nuclear channel name: Specifying a nuclear marker that does not exist in the image channels will cause `simpleSeg` to fail; verify channel names in the `CytoImageList` first.

## Alternatives
- `EBImage`: For low-level, highly flexible image processing and manual watershedding.
- `cytomapper`: For pixel-level visualization and measuring objects.
- `Seurat`: For downstream clustering and classification of the extracted single-cell features.

## Citations
- Nicholls et al. (2026), simpleSeg package vignette.
- Risom et al. (2022), Cell (for the example DCIS MIBI-TOF dataset).

## References
- Homepage: bioconductor.org/packages/simpleSeg
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/simpleSeg/inst/doc/simpleSeg.html
