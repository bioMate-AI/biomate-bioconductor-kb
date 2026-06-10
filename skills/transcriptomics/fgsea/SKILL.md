---
name: bioconductor-fgsea
description: A tabular file with gene symbols in the first column, and a ranked statistic (e.g. t-statistic or log fold-change) in the second column
when_to_use: Use when: Use standard fgsea when you have a ranked list of genes (e.g., from differential expression analysis) and want to find enriched pathways. Use fora for simple over-representation analysis of gene lists. Use geseca when analyzing gene correlation/co-regulation in expression matrices without explicit contrasts (e.g., time-course, single-cell, spatial transcriptomics).
user-invocable: false
---

# fgsea

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.38.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** Rcpp, data.table, BiocParallel, ggplot2, cowplot, fastmatch, Matrix, scales
- **Install:** `BiocManager::install("fgsea")`

## When to Use

- Fast pathway enrichment analysis on pre-ranked gene lists from differential expression studies
- Analyzing transcriptomic or proteomic data with predefined pathway databases
- Studies requiring permutation-based statistical testing of gene set enrichment
- Researchers needing both tabular results and visualization of top enriched pathways

## When NOT to Use

- Unranked gene lists or raw count data (requires external ranking step)
- Studies without established gene set databases
- Real-time analysis requiring very small p-value thresholds (limited by permutation count)
- Analyses requiring sample-level enrichment scores rather than pathway-level statistics

## Key Parameters

- **`pathways`**: A list of gene sets where each element is a vector of gene identifiers
- **`stats`**: A named numeric vector of gene-level statistics (ranks) where names match the gene identifiers in pathways
- **`minSize`**: Minimum size of a gene set to be considered (default is 15)
- **`maxSize`**: Maximum size of a gene set to be considered (default is 500)
- **`eps`**: The lower bound for p-value estimation (default is 1e-10; set to 0.0 for exact/more accurate p-value estimation)
- **`E`**: Gene expression matrix for GESECA where rows are genes and columns are samples/cells
- **`center`**: Logical value indicating whether to center rows of the expression matrix in GESECA (default is TRUE; set to FALSE if using pre-centered or PCA-reduced matrices)
- **`genes`**: A vector of foreground genes of interest for ORA
- **`universe`**: A vector of background genes (universe) for ORA

## Workflow Variants

### Preranked Gsea

**Intent**: Run fast preranked gene set enrichment analysis on a ranked list of genes.

**Inputs**:
- `naive.vs.th1.rnk (tab-separated file containing gene IDs and ranking statistics)`
- `mouse.reactome.gmt (GMT file containing gene sets/pathways)`

**Steps**:
1. Load gene ranks from file
2. Load pathways from GMT file
3. Run fgsea with specified size limits and p-value resolution
4. Collapse redundant pathways to identify independent main pathways
5. Plot enrichment curves and GSEA tables
6. Map gene IDs to symbols for readability
7. Save results to a text file

```r
ranks <- read.table(rnk.file, header=TRUE, colClasses = c("character", "numeric"))
ranks <- setNames(ranks$t, ranks$ID)
pathways <- gmtPathways(gmt.file)
fgseaRes <- fgsea(pathways = examplePathways, stats = exampleRanks, minSize = 15, maxSize = 500)
fgseaRes <- fgsea(pathways = examplePathways, stats = exampleRanks, eps = 0.0, minSize = 15, maxSize = 500)
plotEnrichment(examplePathways[["5991130_Programmed_Cell_Death"]], exampleRanks) + labs(title="Programmed Cell Death")
collapsedPathways <- collapsePathways(fgseaRes[order(pval)][padj < 0.01], examplePathways, exampleRanks)
mainPathways <- fgseaRes[pathway %in% collapsedPathways$mainPathways][order(-NES), pathway]
plotGseaTable(examplePathways[mainPathways], exampleRanks, fgseaRes, gseaParam = 0.5)
fwrite(fgseaRes, file="fgseaRes.txt", sep="\t", sep2=c("", " ", ""))
fgseaResMain[, leadingEdge := mapIdsList(x=org.Mm.eg.db, keys=leadingEdge, keytype="ENTREZID", column="SYMBOL")]
```


---

### Over Representation Analysis

**Intent**: Perform hypergeometric-based over-representation analysis on a list of genes of interest.

**Inputs**:
- `gene_list.txt (list of foreground genes of interest, e.g., top differentially expressed genes)`
- `background_universe.txt (list of all robustly detected genes in the experiment)`
- `mouse.reactome.gmt (GMT file containing gene sets/pathways)`

**Steps**:
1. Define foreground and background gene sets
2. Run ORA using the fora function
3. Inspect and filter enriched pathways

```r
fg <-  names(head(exampleRanks[order(exampleRanks, decreasing=TRUE)],500))
bg <- names(exampleRanks)
foraRes <- fora(genes=fg, universe=bg, pathways=examplePathways)
head(foraRes)
```


---

### Gene Set Coregulation Analysis

**Intent**: Identify gene sets with high gene correlation in expression matrices without explicit contrasts (e.g., time-course, single-cell, or spatial data).

**Inputs**:
- `expression_matrix.csv (normalized gene expression matrix) or seurat_object.rds (processed Seurat object containing normalized single-cell or spatial transcriptomics data)`
- `pathways_list.rds (list of gene sets/pathways)`

**Steps**:
1. Prepare expression matrix or perform PCA reduction on Seurat object
2. Run GESECA to calculate co-regulation scores and p-values
3. Plot coregulation profiles across conditions, UMAP/t-SNE reductions, or spatial coordinates
4. Generate summary tables of top pathways

```r
gesecaRes <- geseca(pathways, exprs(es), minSize = 15, maxSize = 500)
plotCoregulationProfile(pathway=pathways[["HALLMARK_E2F_TARGETS"]], E=exprs(es), titles = es$title, conditions=es$`time point:ch1`)
plotGesecaTable(gesecaRes |> head(10), pathways, E=exprs(es), titles = es$title)
E <- t(base::scale(t(exprs(es)), scale=FALSE))
pcaRev <- prcomp(E, center=FALSE)
Ered <- pcaRev$x[, 1:10]
gesecaResRed <- geseca(pathways, Ered, minSize = 15, maxSize = 500, center=FALSE)
obj <- SCTransform(obj, verbose = FALSE, variable.features.n = 10000)
obj <- RunPCA(obj, assay = "SCT", verbose = FALSE, rev.pca = TRUE, reduction.name = "pca.rev", reduction.key="PCR_", npcs = 50)
E <- obj@reductions$pca.rev@feature.loadings
gesecaRes <- geseca(pathways, E, minSize = 5, maxSize = 500, center = FALSE, eps=1e-100)
ps <- plotCoregulationProfileReduction(pathways[topPathways], obj, title=titles, reduction="tsne")
ps <- plotCoregulationProfileSpatial(pathways[topPathways], obj, title=titles, pt.size.factor=2.5)
imagePlots <- plotCoregulationProfileImage(gsets[topPathways], object = xobj, dark.background = FALSE, title = titles, size=0.8)
```


## Common Pitfalls

- Default eps is 1e-10, which bounds the p-values; must set eps = 0.0 for highly accurate, extremely small p-values. Gene identifier types must match exactly between the pathways list and the gene stats/expression matrix row names. When using PCA-reduced matrices in geseca, automatic centering must be disabled (center = FALSE) if centering was already performed prior to PCA.

## Alternatives

- **Standard GSEA**: fgsea is a much faster alternative to standard GSEA, allowing for more permutations and finer-grained p-values
- **fora**: Preferred over GSEA when only a list of differentially expressed genes (foreground) and a background universe are available rather than a fully ranked list of genes
- **geseca**: Preferred over standard GSEA when there is no obvious contrast or sample annotation to rank genes (e.g., multi-conditional, single-cell, or spatial transcriptomics data)

## Citations

- Korotkevich G, Sukhov V, Budin N, Shpak B, Kupiec M, Sergushichev A. (2021). Fast gene set enrichment analysis. bioRxiv. doi:10.1101/060012

## References

- Homepage: needs_verification
- Documentation: tool documentation (provided in rawText)
- {'title': 'fgsea Bioconductor package', 'url': 'needs_verification', 'search_query': 'fgsea Bioconductor package publication DOI'}
- {'title': 'MSigDB collections', 'url': 'http://www.broadinstitute.org/gsea/msigdb', 'search_query': None}
- {'title': 'GMT format specification', 'url': 'http://www.broadinstitute.org/gsea/msigdb', 'search_query': None}
