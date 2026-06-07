---
name: bioconductor-topgo
description: topGO package provides tools for testing GO terms while accounting for the topology of the GO graph. Different test statistics and different methods for eliminating local similarities and dependencies between GO terms can be implemented and
when_to_use: Use when: Performing Gene Ontology (GO) enrichment analysis using the runTest function on gene lists derived from differential expression.; Accounting for the hierarchical structure and dependencies of the GO DAG using algorithms like elim, weight, or weight01.; Testing enrichment using continuous statistical tests (e.g., Kolmogorov-Smirnov via statistic = "ks") on gene scores rather than just binary gene l. Not for: For pathway databases other than Gene Ontology (e.g., KEGG, Reactome) (use clusterProfiler because topGO is strictly designed for GO graph topologies).; For fast, simple over-representation analysis without graph-topology correction (use gprofiler2 o
user-invocable: false
---

# topGO

## When to Use
- Performing Gene Ontology (GO) enrichment analysis using the `runTest` function on gene lists derived from differential expression.
- Accounting for the hierarchical structure and dependencies of the GO DAG using algorithms like `elim`, `weight`, or `weight01`.
- Testing enrichment using continuous statistical tests (e.g., Kolmogorov-Smirnov via `statistic = "ks"`) on gene scores rather than just binary gene lists.
- Visualizing the subgraph induced by the most significant GO terms using `showSigOfNodes`.

## When NOT to Use
- For pathway databases other than Gene Ontology (e.g., KEGG, Reactome) (use `clusterProfiler` because `topGO` is strictly designed for GO graph topologies).
- For fast, simple over-representation analysis without graph-topology correction (use `gprofiler2` or `enrichR` because `topGO` builds complex local graph structures which takes more time).

## Data Requirements
- A named vector of gene identifiers with associated scores (e.g., p-values) or a binary factor (0/1) indicating interesting genes.
- A mapping between gene identifiers and GO terms (e.g., via a Bioconductor annotation package like `hgu95av2.db`, or custom mappings read by `readMappings`).

## Key Parameters
- **ontology** ("BP"): Character string specifying the ontology of interest; must be "BP", "MF", or "CC".
- **allGenes** (none): Named vector of type numeric or factor defining the gene universe and their scores/status.
- **geneSelectionFun** (none): Function to specify which genes are interesting based on the gene scores (e.g., `topDiffGenes`).
- **nodeSize** (10): Integer used to prune the GO hierarchy from terms which have fewer than this many annotated genes.
- **annot** (annFUN.db): Function which maps gene identifiers to GO terms (e.g., `annFUN.db`, `annFUN.gene2GO`, `annFUN.org`).
- **algorithm** ("weight01"): Method for dealing with the GO graph structure in `runTest` (e.g., "classic", "elim", "weight", "parentchild").
- **statistic** ("fisher"): The test statistic to use in `runTest` (e.g., "fisher", "ks", "t").

## Best Practices
- Filter out genes with low expression or small variability using `genefilter` before defining the gene universe to improve computational efficiency.
- Compare results from multiple algorithms (e.g., `classic` vs `elim`) using `GenTable` to see how topology correction affects the significance of parent/child terms.
- Use `inverseList` to easily transform custom mappings from gene-to-GOs to GO-to-genes when preparing custom annotations.
- Use `score` to extract p-values from a `topGOresult` object for custom plotting or comparisons.

## Common Pitfalls
- **Providing custom annotations with excessive redundancy**: Slows down the analysis significantly. Fix: Provide only the most specific GO annotations in the custom mapping file; `topGO` handles the ancestor propagation.
- **Assuming all input genes are used**: Not all genes in the provided `allGenes` list can be annotated to GO. Fix: Check the `topGOdata` summary to see the actual number of "feasible genes" used in the analysis.
- **Using incompatible algorithms and statistics**: Some statistical tests do not work with every method (e.g., `ks` with `parentchild`). Fix: Consult the compatibility matrix and use supported combinations like `elim` with `ks` or `classic` with `fisher`.

## Alternatives
- **clusterProfiler**: For versatile enrichment analysis supporting multiple databases (GO, KEGG, MSigDB) and rich visualizations.
- **goseq**: For GO enrichment of RNA-seq data while correcting for gene length bias.
- **enrichR**: For fast, web-based enrichment analysis across dozens of gene set libraries.

## Citations
- Alexa A, Rahnenführer J, Lengauer T (2006). "Improved scoring of functional groups from gene expression data by decorrelating GO graph structure." Bioinformatics.
- Grossmann et al. (2007). "Improved detection of overrepresentation of Gene-Ontology annotations with parent child intersection." Bioinformatics.

## References
- Homepage: https://bioconductor.org/packages/topGO
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/topGO/inst/doc/topGO.pdf
