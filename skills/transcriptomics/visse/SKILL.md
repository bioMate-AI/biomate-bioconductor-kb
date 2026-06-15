---
name: bioconductor-visse
description: This package enables the interpretation and analysis of results from a gene set enrichment analysis using network-based and text-mining approaches. Most enrichment analyses result in large lists of significant gene sets that are difficult to interpret. Tools in this package help build a similarity-based network of significant gene sets from a gene set enrichment analysis that can then be investigated for their biological function using text-mining approaches.
when_to_use: Use when: This package enables the interpretation and analysis of results from a gene set enrichment analysis using network-based and text-mining approaches. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# vissE

## Workflows

### Standard Workflow

Summarize and interpret a list of significant gene sets from an enrichment analysis using network clustering, text-mining, and gene/PPI visualization.

```r
library(msigdb)
library(GSEABase)
library(vissE)
library(igraph)
library(ggplot2)
library(patchwork)

# 1. READ USER INPUT FILES (Simulated here)
msigdb_hs = getMsigdb()
msigdb_hs = subsetCollection(msigdb_hs, c('h', 'c2', 'c5'))
set.seed(360)
geneset_res = sample(sapply(msigdb_hs, setName), 2500)
geneset_gsc = msigdb_hs[geneset_res]

# 2. COMPUTE GENE-SET OVERLAP & NETWORK
gs_ovlap = computeMsigOverlap(geneset_gsc, thresh = 0.25)
gs_ovnet = computeMsigNetwork(gs_ovlap, msigdb_hs)

# 3. IDENTIFY CLUSTERS
geneset_stats = rnorm(2500)
names(geneset_stats) = geneset_res
grps = findMsigClusters(gs_ovnet, genesetStat = geneset_stats, alg = cluster_walktrap, minSize = 5)

# 4. CHARACTERIZE CLUSTERS (TEXT-MINING)
p1 = plotMsigWordcloud(msigdb_hs, grps[1:6], type = 'Name')

# 5. VISUALIZE GENE-LEVEL STATISTICS
genes = unique(unlist(geneIds(geneset_gsc)))
gene_stats = rnorm(length(genes))
names(gene_stats) = genes
p3 = plotGeneStats(gene_stats, msigdb_hs, grps[1:6]) + geom_hline(yintercept = 0, colour = 2, lty = 2)

# 6. VISUALIZE PROTEIN-PROTEIN INTERACTIONS
ppi = getIMEX('hs', inferred = TRUE)
p4 = plotMsigPPI(ppi, msigdb_hs, grps[1:6], geneStat = gene_stats, threshStatistic = 0.2, threshConfidence = 0.2)

# 7. COMBINE VISUALIZATIONS
p2 = plotMsigNetwork(gs_ovnet, markGroups = grps[1:6], genesetStat = geneset_stats)
p1 + p2 + p3 + p4 + plot_layout(2, 2)
```
*Input: A GeneSetCollection object containing significant gene sets. Output: A combined paneled plot summarizing the gene-set clusters, text-mining word clouds, gene statistics, and protein-protein interactions.*

## When to Use
- To summarize large lists of significant gene sets from enrichment analyses (e.g., from `limma::fry`, `singscore`, or `GSEA`) using network-based clustering.
- To perform text-mining on gene-set names or short descriptions using frequency analysis (adjusted with inverse document frequency) to identify recurring biological themes.
- To visualize gene-level statistics (using `plotGeneStats`) and protein-protein interactions (using `plotMsigPPI`) within identified gene-set clusters.

## When NOT to Use
- For performing the initial differential expression or gene-set enrichment calculation itself; use packages like `limma` or `singscore` first.
- When you do not have gene-set definitions or a `GeneSetCollection` object; `vissE` requires these to compute overlaps.

## Data Requirements
- A `GeneSetCollection` object (e.g., from `GSEABase` or `msigdb`) representing the significant gene sets.
- A named numeric vector of gene-set statistics (e.g., p-values or FDRs) where names match the gene-set names.
- A named numeric vector of gene-level statistics (e.g., log fold-changes) where names match gene identifiers (e.g., Gene Symbols).

## Key Parameters
- **thresh** (0.25): Threshold for Jaccard index or overlap coefficient in `computeMsigOverlap`.
- **alg** (`cluster_walktrap`): Graph clustering algorithm from `igraph` used in `findMsigClusters`.
- **minSize** (5): Minimum cluster size to retain in `findMsigClusters`.
- **type** ('Name'): Type of text-mining source ('Name' or 'Short') in `plotMsigWordcloud`.
- **threshStatistic** (0.2): Minimum gene-level statistic threshold for filtering nodes in `plotMsigPPI`.
- **threshConfidence** (0.2): Minimum confidence score for filtering PPI edges in `plotMsigPPI`.

## Best Practices
- Filter MSigDB collections to recommended subsets (e.g., 'h', 'c2', 'c5') using `subsetCollection` to reduce noise.
- Set a random seed using `set.seed` before plotting networks (`plotMsigNetwork`) or PPIs to ensure reproducible layouts.
- Combine multiple visualization panels (word clouds, networks, gene stats, and PPIs) using `patchwork` (`+` and `plot_layout`) for collective interpretation.

## Common Pitfalls
- Unmatched gene identifiers: Ensure the gene IDs in your gene-level statistics vector match the ID type (e.g., Symbol vs Ensembl) used in the `GeneSetCollection`.
- Extremely dense networks: If the overlap network is too crowded, increase the `thresh` parameter in `computeMsigOverlap` to filter out weak overlaps.

## Alternatives
- `enrichplot` for alternative visualization of enrichment results.
- `clusterProfiler` for functional profiling and gene set enrichment analysis.

## Citations
- Bhuva DD (2026). vissE: Visualising Set Enrichment Analysis Results. R package.

## References
- Homepage: bioconductor.org/packages/vissE
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/vissE/inst/doc/vissE.html
