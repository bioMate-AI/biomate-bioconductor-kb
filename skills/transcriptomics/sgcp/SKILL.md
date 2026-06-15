---
name: bioconductor-sgcp
description: SGC is a semi-supervised pipeline for gene clustering in gene co-expression networks. SGC consists of multiple novel steps that enable the computation of highly enriched modules in an unsupervised manner. But unlike all existing frameworks, it further incorporates a novel step that leverages Gene Ontology information in a semi-supervised clustering method that further improves the quality of the computed modules.
when_to_use: Use when: SGC is a semi-supervised pipeline for gene clustering in gene co-expression networks; SGCP package manual. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# SGCP

## Workflows

### Standard Workflow

Construct gene co-expression networks, perform clustering, and apply semi-supervised classification using Gene Ontology information.

```r
library(SGCP)
library(SummarizedExperiment)
library(org.Hs.eg.db)

# Load example dataset
data(cheng)
expData <- assay(cheng)
geneID <- rowData(cheng)$ENTREZID
annotation_db <- "org.Hs.eg.db"

# Option 1: Automatic Run using ezSGCP
# (Precomputed data loaded here to avoid long execution times)
data(sgcp)
summary(sgcp, show.data=TRUE)

# Plot PCA and silhouette index
SGCP_ezPLOT(sgcp = sgcp, expreData = expData, silhouette_index = TRUE, keep = FALSE)

# Option 2: Step-by-Step Run
# 1. Network Construction
resAdja <- adjacencyMatrix(expData = expData, hm = NULL)

# 2. Network Clustering (using precomputed resClus for speed)
data(resClus)
summary(resClus)

# Plot PCA of expression data
pl <- SGCP_plot_pca(m = expData, clusLabs = NULL, tit = "PCA plot", ps = .5)
print(pl)
```

**Note on inputs/outputs:**
* **Input:** A gene expression matrix, a vector of gene Entrez IDs, and an organism-specific annotation database.
* **Output:** A list containing initial clusters, semi-labeled genes, semi-supervised classification results, and final biologically enriched gene modules.

## When to Use
* **Gene Co-expression Networks:** Constructing gene co-expression networks and organizing genes into modules using `adjacencyMatrix()` and `clustering()`.
* **GO Integration:** Integrating Gene Ontology (GO) enrichment analysis into the clustering pipeline using `geneOntology()`.
* **Semi-supervised Classification:** Applying semi-supervised classification (e.g., KNN or logistic regression) to refine gene modules using `semiSupervised()`.
* **Network Visualization:** Visualizing gene expression PCA plots and network adjacency heatmaps using `SGCP_plot_pca()` and `SGCP_plot_heatMap()`.

## When NOT to Use
* **Raw Sequence Alignment:** For raw sequence alignment or differential expression analysis, use packages like `DESeq2` or `edgeR` because `SGCP` requires preprocessed, normalized expression data with non-zero variance.
* **Unsupervised Clustering Without GO:** For purely unsupervised clustering without any biological annotation or GO integration, use standard R clustering functions (e.g., `kmeans` or `hclust`) because `SGCP` is specifically designed to leverage GO information.

## Data Requirements
* **Expression Data (`expData`):** A matrix or data frame of size $m \times n$ (genes by samples) of normalized DNA-microarray or RNA-seq data. Genes must have expression values across all samples (no missing values) and non-zero variance.
* **Gene Identifiers (`geneID`):** A vector of size $m$ containing unique gene identifiers (e.g., Entrez IDs) compatible with the annotation database.
* **Annotation Database (`annotation_db`):** A genome-wide annotation package name (e.g., `"org.Hs.eg.db"`).

## Key Parameters
* **calibration** (`FALSE`): Boolean in `adjacencyMatrix()` to perform network calibration.
* **norm** (`TRUE`): Boolean in `adjacencyMatrix()` to divide each gene vector by its L2 norm.
* **tom** (`TRUE`): Boolean in `adjacencyMatrix()` to add Topological Overlap Matrix to the network.
* **kopt** (`NULL`): Integer in `clustering()` specifying the user-defined optimal number of clusters.
* **method** (`NULL`): Method for determining the number of clusters in `clustering()`; options include "relativeGap", "secondOrderGap", and "additiveGap".
* **direction** (`c("over", "under")`): Test direction for GO enrichment in `geneOntology()`.
* **ontology** (`c("BP", "CC", "MF")`): GO ontologies to test in `geneOntology()`.
* **model** ("knn"): Classification model in `semiSupervised()`; options include "knn" and "lr".

## Best Practices
* Ensure all preprocessing, normalization, and batch effect corrections are completed on the expression matrix before inputting to `SGCP`.
* Filter out genes with zero variance or missing values across samples prior to running `adjacencyMatrix()`.
* Evaluate and compare the three cluster-number determination methods ("relativeGap", "secondOrderGap", "additiveGap") using GO validation.
* Enable the silhouette index calculation (`sil = TRUE`) in `clustering()` to evaluate the quality of the initial clusters.

## Common Pitfalls
* **Mismatched Gene Identifiers:** Mismatch between gene identifiers in `geneID` and the standard expected by `GOstats` / `annotation_db`. *Fix:* Ensure `geneID` contains valid Entrez IDs (or TAIR IDs for Arabidopsis) that match the selected `annotation_db`.
* **Long Computation Times:** Long computation times during the GO validation or clustering steps. *Fix:* Use precomputed results where possible, or reduce the number of genes to those with the highest variance.
* **Zero Variance Genes:** Error due to genes with zero variance across samples. *Fix:* Filter the input expression matrix to remove zero-variance genes before running the pipeline.

## Alternatives
* **WGCNA** for standard unsupervised gene co-expression network analysis.
* **GOstats** for standalone hypergeometric testing of Gene Ontology terms.
* **SummarizedExperiment** for general containerization of biological assays and genomic features.

## Citations
* Cheng, J. et al. (Ischemic cardiomyopathy dataset reference).

## References
* Homepage: https://bioconductor.org/packages/sgcp
* Vignette: https://bioconductor.org/packages/release/bioc/vignettes/sgcp/inst/doc/SGCP.html
