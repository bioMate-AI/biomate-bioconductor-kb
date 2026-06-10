---
name: bioconductor-treesummarizedexperiment
description: TreeSummarizedExperiment has extended SingleCellExperiment to include hierarchical information on the rows or columns of the rectangular data.
when_to_use: Use when: Storing rectangular experimental data alongside hierarchical tree structures using the TreeSummarizedExperiment class.; Aggregating data to different taxonomic levels (e.g., phylum or class) using aggTSE.; Subsetting data by specific tree nodes or leaves using subsetByNode.; Storing reference sequence data per feature using the referenceSeq slot.. Not for: For standard single-cell RNA-seq without hierarchical relationships, use SingleCellExperiment because the tree-related slots and overhead are unnecessary.; For purely manipulating or visualizing phylogenetic trees without rectangular assay data, use 
user-invocable: false
---

# TreeSummarizedExperiment

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.20.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** SingleCellExperiment, S4Vectors, Biostrings
- **Imports:** BiocGenerics, ape, rlang, dplyr, SummarizedExperiment, BiocParallel, IRanges, treeio
- **System requirements:** URL
- **Install:** `BiocManager::install("TreeSummarizedExperiment")`

## When to Use
- Storing rectangular experimental data alongside hierarchical tree structures using the `TreeSummarizedExperiment` class.
- Aggregating data to different taxonomic levels (e.g., phylum or class) using `aggTSE`.
- Subsetting data by specific tree nodes or leaves using `subsetByNode`.
- Storing reference sequence data per feature using the `referenceSeq` slot.

## When NOT to Use
- For standard single-cell RNA-seq without hierarchical relationships, use `SingleCellExperiment` because the tree-related slots and overhead are unnecessary.
- For purely manipulating or visualizing phylogenetic trees without rectangular assay data, use `ape` or `ggtree` directly because they are specialized for tree operations.

## Data Requirements
- An `assays` matrix representing observed data (e.g., counts) with rows as entities and columns as samples.
- `rowData` and `colData` data frames for feature and sample annotations.
- Hierarchical structures provided as `phylo` objects for `rowTree` and/or `colTree`.
- Link information mapping assay rows/columns to tree nodes via `rowNodeLab` or `colNodeLab`.
- Optional reference sequences as `DNAStringSet` or `DNAStringSetList`.

## Key Parameters
- **rowTree**: A `phylo` object representing the hierarchical structure on the rows of the assays.
- **rowNodeLab**: A character vector linking the rows of the assays to the node labels of the `rowTree`.
- **colLevel**: The desired aggregation level for columns in `aggTSE`, specified via node label or node number.
- **rowFun**: The aggregate function (e.g., `sum`) applied to the row dimension in `aggTSE`.
- **only.leaf** (TRUE): Logical in `findDescendant` to specify if only leaf descendants should be returned.
- **rowFirst** (FALSE): Determines the aggregation order in `aggTSE` when aggregating both dimensions.
- **colDataCols**: Specifies which columns of `colData` to keep in the final output of `aggTSE`.

## Best Practices
- Use `toTree` to convert a taxonomic `data.frame` into a `phylo` object before adding it to the object.
- Use `changeTree` to replace an existing tree and update the mapping if nodes are labeled differently.
- Use `aggTSE` with `colDataCols` to speed up aggregation by dropping irrelevant column data.
- Avoid modifying `rowLinks` or `colLinks` manually to prevent breaking the link between assays and trees.

## Common Pitfalls
- **Missing node labels**: Row or column names in the assay do not match the node labels of the tree, causing them to be removed with warnings. Fix: Provide the correct mapping via `rowNodeLab` or `colNodeLab` during construction.
- **Broken links after pruning**: Subsetting a tree with `ape::keep.tip` changes node numbers and breaks links. Fix: Use `trackNode` to track alias labels and update the `LinkDataFrame` accordingly.
- **Failed tree replacement**: Replacing a tree directly with `rowTree<-` fails if names cannot be matched. Fix: Use `changeTree` with `rowNodeLab` when labels differ between the object and the new tree.

## Alternatives
- **SingleCellExperiment**: For storing single-cell data without hierarchical tree structures.
- **ape**: For general phylogenetic tree manipulation without associated rectangular assay data.
- **ggtree**: For visualizing phylogenetic trees, which `TreeSummarizedExperiment` relies on for plotting rather than implementing itself.

## Citations
- Huang R, et al. (2021). TreeSummarizedExperiment: a S4 class for data with tree structures. *F1000Research*.
- Lun and Risso (2020). SingleCellExperiment.

## References
- Homepage: https://bioconductor.org/packages/TreeSummarizedExperiment
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/TreeSummarizedExperiment/inst/doc/Introduction_to_treeSE.html
