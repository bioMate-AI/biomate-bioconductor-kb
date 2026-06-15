---
name: bioconductor-asurat
description: ASURAT is a software for single-cell data analysis. Using ASURAT, one can simultaneously perform unsupervised clustering and biological interpretation in terms of cell type, disease, biological process, and signaling pathway activity. Inputting a single-cell RNA-seq data and knowledge-based databases, such as Cell Ontology, Gene Ontology, KEGG, etc., ASURAT transforms gene expression tables into original multivariate tables, termed sign-by-sample matrices (SSMs).
when_to_use: Use when: ASURAT is a software for single-cell data analysis; Single-cell RNA-seq analysis (ASURAT). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# ASURAT

## Workflows

### Standard Workflow

Perform single-cell RNA-seq preprocessing, functional sign creation from databases, sign-by-sample matrix generation, clustering, and multifaceted visualization.

```r
library(ASURAT)
library(SingleCellExperiment)

# 1. Add metadata and perform quality control filtering
pbmc <- add_metadata(sce = pbmc, mitochondria_symbol = "^MT-")
pbmc <- remove_variables(sce = pbmc, min_nsamples = 10)
pbmc <- remove_samples(sce = pbmc, min_nReads = 5000, max_nReads = 20000, min_nGenes = 100, max_nGenes = 1e+10, min_percMT = 0, max_percMT = 10)
pbmc <- remove_variables_second(sce = pbmc, min_meannReads = 0.05)

# 2. Create and select signs from databases
pbmc <- remove_signs(sce = pbmc, min_ngenes = 2, max_ngenes = 1000)
pbmc <- cluster_genesets(sce = pbmc, cormat = cormat, th_posi = 0.30, th_nega = -0.30)
pbmc <- create_signs(sce = pbmc, min_cnt_strg = 2, min_cnt_vari = 2)

# 3. Generate sign-by-sample matrix (SSM)
pbmc <- makeSignMatrix(sce = pbmc, weight_strg = 0.5, weight_vari = 0.5)

# 4. Identify significant signs
pbmc <- compute_sepI_all(sce = pbmc, labels = labels, nrand_samples = 200)
```

*Input:* A raw count `SingleCellExperiment` object and knowledge-based databases. *Output:* A `SingleCellExperiment` object containing a sign-by-sample matrix (SSM) with computed separation indices.

## When to Use
- To simultaneously perform unsupervised clustering and biological interpretation of single-cell RNA-seq data using functional gene sets from databases like Cell Ontology, Gene Ontology, or KEGG.
- To transform normalized-and-centered gene expression matrices into sign-by-sample matrices (SSMs) using `makeSignMatrix`.
- To identify significant biological markers (signs) for cell clusters using non-parametric separation indices computed via `compute_sepI_all`.
- To visualize multifaceted single-cell datasets across multiple sign-by-sample matrices and gene expression levels simultaneously using `plot_multiheatmaps`.

## When NOT to Use
- For standard gene-level-only clustering without functional database integration, use `scran` or `Seurat` because ASURAT is specifically designed for sign-based (gene set) multivariate analysis.
- For datasets lacking reliable functional annotations or established gene sets, use standard unsupervised clustering because ASURAT relies on knowledge-based databases to define signs.

## Data Requirements
- **Input format:** `SingleCellExperiment` object containing raw counts in `assays(sce)$counts`.
- **Structure:** Row names must be gene symbols (e.g., `Symbol_TENx`) and column names must be cell barcodes.
- **Normalization state:** Requires log-normalized and centered expression data (stored in `assay(sce, "centered")`) to compute gene expression correlation matrices.

## Key Parameters
- **mitochondria_symbol** ("^MT-"): Regular expression to identify mitochondrial genes for quality control.
- **min_nsamples** (10): Minimum number of non-zero expressing cells required to keep a gene.
- **min_meannReads** (0.05): Minimum mean read count across samples required to keep a gene.
- **min_ngenes** (2): Minimal number of genes in a functional gene set to be kept.
- **max_ngenes** (1000): Maximal number of genes in a functional gene set to be kept.
- **th_posi** (0.30): Positive correlation coefficient threshold for clustering gene sets.
- **th_nega** (-0.30): Negative correlation coefficient threshold for clustering gene sets.
- **weight_strg** (0.5): Weight parameter for strongly correlated gene sets (SCG) in SSM creation.

## Best Practices
- Add metadata to both rows and columns using `add_metadata` before performing quality control filtering.
- Perform log-normalization and center the data by subtracting the mean expression levels across cells before computing correlation matrices.
- Filter out redundant signs using semantic similarity matrices with `remove_signs_redundant` to simplify the downstream analysis.
- Use `compute_sepI_all` to find cluster-specific signs instead of standard parametric tests, as row vectors of SSMs are centered.

## Common Pitfalls
- Using slot name "log-normalized" for `altExp(sce)`: This can cause errors when converting to Seurat objects using `as.Seurat`. Fix by using standard slot names like "logcounts".
- Setting excessive cutoff values in `remove_samples`: This can produce biased results. Carefully inspect the distribution of `nReads` and `nGenes` before setting thresholds.

## Alternatives
- `Seurat` for standard graph-based clustering and cell cycle scoring.
- `scater` for standard single-cell preprocessing and visualization.
- `ComplexHeatmap` for general high-dimensional heatmap plotting.

## Citations
- Iida K (2026), "ASURAT: Functional sign-based single-cell analysis".

## References
- Homepage: bioconductor.org/packages/asurat
- Vignette: bioconductor.org/packages/release/bioc/vignettes/asurat/inst/doc/asurat.html
