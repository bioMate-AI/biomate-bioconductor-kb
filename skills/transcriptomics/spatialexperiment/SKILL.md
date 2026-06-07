---
name: bioconductor-spatialexperiment
description: Defines an S4 class for storing data from spatial -omics experiments. The class extends SingleCellExperiment to support storage and retrieval of additional information from spot-based and molecule-based platforms, including spatial coordina
when_to_use: Use when: Spot-Based Spatial Transcriptomics: Representing and manipulating data from spot-based spatial transcriptomics platforms (e.g., 10x Genomics Visium) containing gene expression, spatial coordinates, and histology images using SpatialExperiment() and imgData().; Molecule-Resolved Spatial Data: Storing and querying molecule-resolved spatial data (e.g., seqFISH) where exact X-Y coordinates of individu. Not for: For standard single-cell RNA-seq data lacking spatial coordinates, use SingleCellExperiment instead because the spatial-specific slots like spatialCoords and imgData will remain empty and add unnecessary overhead.; For pure image processing without t
user-invocable: false
---

# SpatialExperiment

## When to Use
- **Spot-Based Spatial Transcriptomics**: Representing and manipulating data from spot-based spatial transcriptomics platforms (e.g., 10x Genomics Visium) containing gene expression, spatial coordinates, and histology images using `SpatialExperiment()` and `imgData()`.
- **Molecule-Resolved Spatial Data**: Storing and querying molecule-resolved spatial data (e.g., seqFISH) where exact X-Y coordinates of individual transcripts are recorded, using `splitAsBumpyMatrix()` and the `molecules()` accessor.
- **Image Transformations**: Applying basic image transformations like rotation and mirroring to spatial images using `rotateImg()` and `mirrorImg()`.

## When NOT to Use
- For **standard single-cell RNA-seq data** lacking spatial coordinates, use `SingleCellExperiment` instead because the spatial-specific slots like `spatialCoords` and `imgData` will remain empty and add unnecessary overhead.
- For **pure image processing** without transcriptomics, use other imaging tools because `SpatialExperiment` is designed to link `assays` (like `counts`) with spatial metadata.

## Data Requirements
- **Assays**: A count matrix (e.g., `counts`) representing gene expression across spatial locations.
- **Spatial Coordinates**: A numeric matrix or `DataFrame` of coordinates (e.g., `x` and `y`) for each spot or cell.
- **Image Data (Optional)**: Images stored as `SpatialImage` objects within an `imgData` `DataFrame`.

## Key Parameters
- **assays** (required): A list of matrices containing expression data (e.g., `counts`).
- **spatialCoords** (optional): A numeric matrix containing spatial coordinates.
- **spatialCoordsNames** (optional): A character vector specifying which `colData` fields correspond to spatial coordinates.
- **imgData** (optional): A `DataFrame` containing image metadata and `SpatialImage` objects.
- **colData** (optional): A `DataFrame` containing spot- or cell-level metadata.
- **sample_id** (default `"sample_01"`): A character string specifying the sample identifier.

## Best Practices
- Use `spatialCoords()` and `imgData()` accessor functions instead of directly manipulating internal slots to maintain object integrity.
- For 10x Genomics Visium data, use `TENxVisiumList()` and `import()` from the `VisiumIO` package to automatically load outputs from Space Ranger.
- Make sample identifiers unique prior to combining objects with `cbind()` to avoid automatic index appending.

## Common Pitfalls
- **Duplicated sample IDs during replacement**: Attempting to replace `sample_id`s with non-unique values returns an error; fix this by ensuring replacement IDs map uniquely to existing ones.
- **Loss of sample IDs**: Attempting to remove `sample_id` by setting it to `NULL` fails because it is a protected field; fix this by retaining the `sample_id` or replacing it with valid unique strings.
- **Conflicting spatial coordinates**: Supplying both `spatialCoords` and `spatialCoordsNames` causes `spatialCoordsNames` to be ignored; fix this by setting either to `NULL` to suppress the warning message.

## Alternatives
- **SingleCellExperiment**: The parent class, which can store coordinates in `colData` but lacks dedicated `spatialCoords` and `imgData` slots.
- **Seurat**: Another framework for single-cell and spatial data analysis.
- **Giotto**: An independent R package for spatial transcriptomics.

## Citations
- Righelli, D., et al. (2022). SpatialExperiment: infrastructure for spatially resolved transcriptomics data in Bioconductor. *Bioinformatics*, 38(11), 3128-3130.

## References
- Homepage: bioconductor.org/packages/SpatialExperiment
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/SpatialExperiment/inst/doc/SpatialExperiment.html
