---
name: bioconductor-ebimage
description: EBImage provides general purpose functionality for image processing and analysis. In the context of (high-throughput) microscopy-based cellular assays, EBImage offers tools to segment cells and extract quantitative cellular descriptors. Thi
when_to_use: Use when: General Image Manipulation: Reading, writing, and displaying multi-dimensional images (JPEG, PNG, TIFF) using readImage, writeImage, and display.; Spatial Transformations: Applying geometric transformations such as translate, rotate, resize, flip, flop, and affine to image arrays.; Image Filtering: Removing noise or detecting edges using linear filters (filter2, gblur) or non-linear filters (media. Not for: Interactive Whole-Slide Analysis: For interactive, manual annotation of large whole-slide tissue images, use QuPath instead because EBImage is designed for programmatic, batch-oriented processing.; Advanced 3D/4D Rendering: For complex 3D volumetric 
user-invocable: false
---

# EBImage

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.54.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** BiocGenerics, abind, tiff, jpeg, png, locfit, fftwtools, htmltools, htmlwidgets, RCurl
- **Install:** `BiocManager::install("EBImage")`

## When to Use
- **General Image Manipulation**: Reading, writing, and displaying multi-dimensional images (JPEG, PNG, TIFF) using `readImage`, `writeImage`, and `display`.
- **Spatial Transformations**: Applying geometric transformations such as `translate`, `rotate`, `resize`, `flip`, `flop`, and `affine` to image arrays.
- **Image Filtering**: Removing noise or detecting edges using linear filters (`filter2`, `gblur`) or non-linear filters (`medianFilter`).
- **Cell Segmentation**: Segmenting non-touching objects with `bwlabel` or separating touching cells using `distmap`, `watershed`, and `propagate` (Voronoi tessellation).

## When NOT to Use
- **Interactive Whole-Slide Analysis**: For interactive, manual annotation of large whole-slide tissue images, use `QuPath` instead because EBImage is designed for programmatic, batch-oriented processing.
- **Advanced 3D/4D Rendering**: For complex 3D volumetric rendering, use `ImageJ/Fiji` instead because EBImage's visualization (`display`) is primarily 2D (browser or raster).
- **Deep Learning Segmentation**: For out-of-the-box deep learning-based segmentation, use Python packages like `cellpose` because EBImage relies on classical intensity-based and morphological segmentation algorithms.

## Data Requirements
- **Input Format**: Image files (JPEG, PNG, TIFF) or numeric arrays.
- **Structure**: `Image` class objects extending the R base class `array`. Supports multi-dimensional data (e.g., color channels, z-positions, time points).
- **Normalization State**: Pixel intensities are typically represented as numeric values ranging from 0 to 1.

## Key Parameters
- **method** ("browser"): Specifies how the image is visualized in `display` (either "browser" for a JavaScript viewer or "raster" for R's built-in plotting).
- **colorMode** (Grayscale): Determines how the third and higher dimensions of the image array are rendered (Grayscale or Color).
- **sigma** (5): Defines the width of the Gaussian filter in `makeBrush` or `gblur`.
- **offset** (0.05): The threshold offset used in adaptive thresholding (`thresh`) to separate foreground from background.
- **lambda** (100): Controls the relative weighting between sideways and vertical movement in Voronoi tessellation via `propagate`.
- **w** (15): The width of the rectangular box used for adaptive thresholding in `thresh`.

## Best Practices
- **Raster Display**: Use `display` with `method="raster"` to combine image data with R's built-in plotting facilities (e.g., adding text labels).
- **Noise Reduction**: Apply a low-pass filter like `gblur` before thresholding to smooth out high-frequency noise and prevent over-segmentation.
- **Watershed Seeding**: Use `distmap` to generate a distance map from a binary image before applying the `watershed` transformation to separate touching objects.
- **Visualization of Segmentation**: Use `colorLabels` to visualize segmentation results by color-coding objects with a random permutation of unique colors.

## Common Pitfalls
- **Touching Cells Merged**: Cells close to each other are merged into a single object after thresholding. *Fix*: Use the `watershed` algorithm on the distance map (`distmap`) to separate them.
- **Color Channels Displayed as Grayscale**: Color images display as separate grayscale frames. *Fix*: Change the `colorMode` of the image to `Color` using `colorMode()`.
- **Small Holes in Foreground**: Thresholding leaves small holes inside foreground objects. *Fix*: Apply the `fillHull` function or morphological `closing` to fill small holes.

## Alternatives
- **magick**: Better for general-purpose, non-biological image manipulation and format conversion, but lacks biological segmentation tools like `watershed`.
- **imager**: An R package based on CImg, excellent for general image processing but has fewer biology-specific features compared to EBImage.
- **RBioFormats**: Use this if you need to read proprietary microscopy image data and metadata not natively supported by `readImage`.

## Citations
- Pau, G., Fuchs, F., Steffy, O., Boutros, M., & Huber, W. (2010). EBImage—an R package for image processing with applications on cellular assays. *Bioinformatics*, 26(7), 979-981.

## References
- Homepage: https://bioconductor.org/packages/EBImage
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/EBImage/inst/doc/EBImage-introduction.html
