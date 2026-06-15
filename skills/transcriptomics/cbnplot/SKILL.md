---
name: bioconductor-cbnplot
description: This package provides the visualization of bayesian network inferred from gene expression data. The networks are based on enrichment analysis results inferred from packages including clusterProfiler and ReactomePA. The networks between pathways and genes inside the pathways can be inferred and visualized.
when_to_use: Use when: This package provides the visualization of bayesian network inferred from gene expression data; deg using mappedkeys, enrichKEGG; usecase using bngeneplot; usecase2 using bngeneplot; igraph using evcent; usecase3 using bnpathplot. Not for: Requires R ≥ 4.3.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# CBNplot

## Workflows

### Standard Workflow

Infer and plot a Bayesian network of genes within a specific enriched pathway using expression data.

```r
library(CBNplot)
library(bnlearn)
library(org.Hs.eg.db)

# 1. Load User Inputs & Prepare Data
data(gaussian.test)
kegg <- org.Hs.egPATH2EG
mapped <- mappedkeys(kegg)
genes <- as.list(kegg[mapped])[["00532"]]
counts <- head(gaussian.test, length(genes))
row.names(counts) <- genes

pway <- clusterProfiler::enrichKEGG(gene = genes)
pway <- clusterProfiler::setReadable(pway, org.Hs.eg.db, keyType="ENTREZID")

# 2. Visualize the gene-level Bayesian network for the first pathway
bngeneplot(results = pway, exp = counts, pathNum = 1, expRow="ENTREZID")

# 3. Extract the underlying network structure, strength, and direction
ret <- bngeneplot(results = pway, exp = counts, pathNum = 1, returnNet=TRUE, expRow="ENTREZID")
head(ret$str)

# 4. Convert the averaged network to an igraph object and perform centrality analysis
g <- bnlearn::as.igraph(ret$av)
igraph::evcent(g)$vector

# 5. Customize the gene network visualization
bngeneplotCustom(results = pway, exp = counts, expRow="ENTREZID", pathNum=1, fontFamily="sans", glowEdgeNum=NULL, hub=1)
```
*Inputs/Outputs:* Takes an enrichment analysis result object and a normalized expression data frame as inputs, and outputs Bayesian network plots and network structure data frames.

## When to Use
- To infer and visualize Bayesian networks of genes within a specific enriched pathway using expression data via `bngeneplot`.
- To visualize relationships between multiple pathways as a Bayesian network using `bnpathplot`.
- To customize network visualizations with glow edges or hub highlighting using `bngeneplotCustom` or `bnpathplotCustom`.
- To extract network strength and direction or convert the inferred network to an `igraph` object using `bnlearn::as.igraph` for centrality analysis.

## When NOT to Use
- For general non-pathway-based gene regulatory network inference without prior enrichment results (use packages like `minet` or `GENIE3` instead).
- For static pathway diagrams without expression-based network inference (use `pathview` instead).

## Data Requirements
- Enrichment analysis results (e.g., from `clusterProfiler::enrichKEGG` or `ReactomePA`).
- A normalized expression matrix or data frame (e.g., `counts`) where row names match the gene identifier type (e.g., `ENTREZID`) specified in the enrichment results.

## Key Parameters
- **results**: Enrichment analysis result object (e.g., from `clusterProfiler::enrichKEGG`).
- **exp**: Normalized expression data frame or matrix.
- **pathNum** (1): The pathway number in the enrichment results to plot.
- **expRow** ("ENTREZID"): The column/row identifier type for expression data.
- **returnNet** (FALSE): Logical indicating whether to return the network structure, strength, and direction.
- **nCategory** (5): Number of pathways to include in `bnpathplot`.
- **glowEdgeNum** (NULL): Parameter in custom plots to highlight edges of interest.
- **hub** (1): Parameter in custom plots to highlight hub nodes.

## Best Practices
- Ensure gene identifiers in the expression matrix match the `keyType` of the enrichment results (e.g., convert using `clusterProfiler::setReadable`).
- Use `mappedkeys` to map pathway identifiers to genes when preparing test or custom pathway gene lists.
- Set `returnNet = TRUE` in `bngeneplot` to inspect the underlying network strength and direction before relying solely on the visual plot.

## Common Pitfalls
- Mismatched gene identifier types between expression data and enrichment results. Fix: Use `clusterProfiler::setReadable` to align key types (e.g., to "ENTREZID").
- Providing raw, unnormalized count data to network inference. Fix: Supply normalized expression values (e.g., log-transformed or normalized counts).

## Alternatives
- `pathview` for overlaying expression data onto static KEGG pathway diagrams.
- `enrichplot` for standard enrichment visualizations (e.g., cnetplot, emapplot) without Bayesian network inference.
- `bnlearn` for general Bayesian network inference without direct integration with enrichment results.

## Citations
- Scutari M (2010). Learning Bayesian Networks with the bnlearn R Package. Journal of Statistical Software.
- Yu G, Wang LG, Han Y, He QY (2012). clusterProfiler: an R Package for Comparing Biological Themes Among Gene Clusters. OMICS.

## References
- Homepage: bioconductor.org/packages/cbnplot
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cbnplot/inst/doc/CBNplot.html
