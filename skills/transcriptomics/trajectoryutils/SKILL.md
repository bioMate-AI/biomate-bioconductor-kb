---
name: bioconductor-trajectoryutils
description: Implements low-level utilities for single-cell trajectory analysis, primarily intended for re-use inside higher-level packages. Include a function to create a cluster-level minimum spanning tree and data structures to hold pseudotime infere
when_to_use: Use when: Developing custom single-cell trajectory inference workflows or extending existing packages.; Constructing cluster-level minimum spanning trees (MST) from low-dimensional single-cell embeddings using createClusterMST().; Standardizing pseudotime inference results and path structures using the PseudotimeOrdering class.; Guessing possible root nodes for trajectory paths using guessMSTRoots().. Not for: For end-to-end, user-friendly trajectory analysis with built-in visualization, use slingshot or TSCAN instead because TrajectoryUtils provides low-level developer utilities rather than high-level inference.; For standard clustering or dimensionality 
user-invocable: false
---

# TrajectoryUtils

## When to Use
- Developing custom single-cell trajectory inference workflows or extending existing packages.
- Constructing cluster-level minimum spanning trees (MST) from low-dimensional single-cell embeddings using `createClusterMST()`.
- Standardizing pseudotime inference results and path structures using the `PseudotimeOrdering` class.
- Guessing possible root nodes for trajectory paths using `guessMSTRoots()`.

## When NOT to Use
- For end-to-end, user-friendly trajectory analysis with built-in visualization, use `slingshot` or `TSCAN` instead because `TrajectoryUtils` provides low-level developer utilities rather than high-level inference.
- For standard clustering or dimensionality reduction, use standard single-cell workflows instead.

## Data Requirements
- **Input format**: A numeric matrix of low-dimensional coordinates (e.g., PCA) and a vector of cluster assignments.
- **Structure**: Rows in the coordinate matrix represent cells, and columns represent dimensions.
- **Normalization state**: Input coordinates must be derived from normalized and dimensionally reduced expression data.

## Key Parameters
- **outgroup** (FALSE): Logical in `createClusterMST()` to add an outgroup to break apart distant clusters.
- **dist.method** (None): Method for distance calculation in `createClusterMST()` (e.g., `"mnn"` or `"slingshot"`).
- **use.median** (FALSE): Logical in `createClusterMST()` to compute centroids by taking the median instead of the mean.
- **method** (None): Strategy used in `guessMSTRoots()` to guess the root node (e.g., `"maxstep"` or `"minstep"`).
- **roots** (None): The starting node(s)/cluster(s) specified in `defineMSTPaths()`.
- **times** (None): Timing information (e.g., from RNA velocity) used in `defineMSTPaths()` to define paths based on local minima/maxima.

## Best Practices
- Use `dist.method="slingshot"` in `createClusterMST()` to account for the shape and spread of clusters via Mahalanobis distance.
- Use `use.median=TRUE` when constructing the MST to protect against clusters with many outliers.
- Store metadata on cells and paths systematically using `cellData()` and `pathData()` within a `PseudotimeOrdering` object.
- Use `splitByBranches()` for a root-free method of defining paths through the MST to interpret sections in a modular manner.

## Common Pitfalls
- **Spurious links**: Spurious links forming between unrelated parts of the dataset during MST construction; fix this by setting `outgroup=TRUE` in `createClusterMST()`.
- **Penalizing adjacent clusters**: Penalizing the formation of edges between adjacent heterogeneous clusters; fix this by using `dist.method="mnn"` to base distances on mutually nearest neighbors.
- **Multiple pseudotime values**: Requiring a single set of pseudotime values for downstream visualization when multiple paths exist; fix this by using `averagePseudotime()` to compute a single average per cell.

## Alternatives
- **slingshot**: A high-level package for trajectory inference that uses `TrajectoryUtils` under the hood but provides a complete user-facing workflow.
- **TSCAN**: Another high-level trajectory package based on MSTs, which also relies on these utilities for path finding.

## Citations
- Aaron Lun (2020). Trajectory utilities for package developers.

## References
- Homepage: https://bioconductor.org/packages/TrajectoryUtils
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/TrajectoryUtils/inst/doc/TrajectoryUtils.html
