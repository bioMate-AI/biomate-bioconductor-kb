---
name: bioconductor-treekor
description: treekoR is a novel framework that aims to utilise the hierarchical nature of single cell cytometry data to find robust and interpretable associations between cell subsets and patient clinical end points. These associations are aimed to recapitulate the nested proportions prevalent in workflows inovlving manual gating, which are often overlooked in workflows using automatic clustering to identify cell populations. We developed treekoR to: Derive a hierarchical tree structure of cell clusters; qua
when_to_use: Use when: vignette; Differential expression analysis (treekoR); Single-cell RNA-seq analysis (treekoR); Flow cytometry analysis (treekoR). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# treekoR

## Workflows

### Standard Workflow

Identify robust associations between hierarchical cell subsets and clinical outcomes from single-cell cytometry data.

```r
library(treekoR)
library(SingleCellExperiment)

# Load data
data(COVIDSampleData)
sce <- DeBiasi_COVID_CD8_samp

exprs <- t(assay(sce, "exprs"))
clusters <- colData(sce)$cluster_id
classes <- colData(sce)$condition
samples <- colData(sce)$sample_id

# 1. Construct the hierarchical tree of clusters using getClusterTree (hopach)
clust_tree <- getClusterTree(exprs, clusters, hierarchy_method="hopach")

# 2. Perform significance testing of cell subpopulations using testTree
tested_tree <- testTree(phylo=clust_tree$clust_tree, clusters=clusters, samples=samples, classes=classes, pos_class_name=NULL)

# 3. Extract significance results using getTreeResults
res_df <- getTreeResults(tested_tree)

# 4. Visualize results interactively using plotInteractiveHeatmap
plotInteractiveHeatmap(tested_tree, clust_med_df = clust_tree$median_freq, clusters=clusters)

# 5. Construct tree with average linkage, test, and plot
clust_tree_avg <- getClusterTree(exprs, clusters, hierarchy_method="average")
tested_tree_avg <- testTree(clust_tree_avg$clust_tree, clusters=clusters, samples=samples, classes=classes, pos_class_name=NULL)
plotInteractiveHeatmap(tested_tree_avg, clust_med_df = clust_tree_avg$median_freq, clusters=clusters)

# 6. Construct tree with hopach, test with edgeR, and plot
tested_tree_edgeR <- testTree(clust_tree$clust_tree, clusters=clusters, samples=samples, classes=classes, sig_test="edgeR", pos_class_name="COV")
plotInteractiveHeatmap(tested_tree_edgeR, clust_med_df = clust_tree$median_freq, clusters=clusters)

# 7. Extract cell proportions (%total and %parent) using getCellProp
prop_df <- getCellProp(phylo=clust_tree$clust_tree, clusters=clusters, samples=samples, classes=classes)

# 8. Extract marker geometric means per cell type using getCellGMeans
means_df <- getCellGMeans(clust_tree$clust_tree, exprs=exprs, clusters=clusters, samples=samples, classes=classes)
```
*Inputs are single-cell expression matrix, cluster IDs, sample IDs, and clinical classes; outputs are tested tree objects, proportion data frames, and interactive heatmaps.*

## When to Use
- When analyzing single-cell cytometry or flow cytometry data with hierarchical cell populations.
- To find robust associations between cell subset proportions (both %total and %parent) and patient clinical outcomes.
- To extract marker geometric means per cell type across samples for downstream machine learning or visualization.

## When NOT to Use
- For standard single-cell RNA-seq differential gene expression analysis within a single cell type; use `DESeq2`, `edgeR`, or `limma` instead.
- When cell populations do not exhibit a hierarchical or nested lineage structure.

## Data Requirements
- **exprs**: Single-cell expression matrix ($n \times p$) where $p$ is the number of markers and $n$ is the number of cells.
- **clusters**: A vector of length $n$ representing the cell type or cluster of each cell (character or numeric).
- **classes**: A vector of length $n$ containing the patient outcome/class each cell belongs to.
- **samples**: A vector of length $n$ identifying the patient/sample each cell belongs to.

## Key Parameters
- **hierarchy_method** ("hopach"): Method to construct the hierarchical tree. Options include `"hopach"` or any `hclust` method (e.g., `"average"`, `"complete"`, `"ward.D"`).
- **sig_test** ("ttest"): Significance test to use. Options include `"ttest"`, `"GLMM"`, or `"edgeR"`.
- **pos_class_name** (NULL): Name of the positive class of interest for testing (e.g., `"COV"`).

## Best Practices
- Use HOPACH (`hierarchy_method="hopach"`) as the default method to automatically determine the tree structure of cell clusters.
- Measure both `%parent` (proportion relative to immediate parent node) and `%total` (proportion relative to all cells) to capture nested proportions.
- Use `plotInteractiveHeatmap` to simultaneously visualize the hierarchical tree (colored by test statistics) and the median marker expression heatmap.

## Common Pitfalls
- **Ignoring hierarchical structure**: Only analyzing `%total` proportions, which overlooks nested subpopulation changes. *Fix*: Use `testTree` to calculate and test both `%total` and `%parent` proportions.
- **Incorrect positive class specification**: Specifying a non-existent class name in `pos_class_name` when using `sig_test="edgeR"`. *Fix*: Ensure `pos_class_name` matches one of the unique values in the `classes` vector (e.g., `"COV"`).

## Alternatives
- `diffcyt`: For high-dimensional cytometry differential analysis using GLMM or edgeR without hierarchical tree structures.
- `Citrus`: For supervised identification of stratifying cell populations.
- `scda`: For general single-cell differential abundance analysis.

## Citations
- De Biasi, S. et al. 2020. "Marked T cell activation, senescence, exhaustion and skewing in patients with COVID-19." Nature Communications.

## References
- Homepage: bioconductor.org/packages/treekoR
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/treekoR/inst/doc/treekoR.html
