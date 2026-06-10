---
name: bioconductor-clusterprofiler
description: This package supports functional characteristics of both coding and non-coding genomics data for thousands of species with up-to-date gene annotation. It provides a univeral interface for gene functional annotation from a variety of sources
when_to_use: Use when: Appropriate when analyzing genomic coordinates, gene lists, or gene clusters to identify enriched biological themes, pathways, or diseases, and when comparing functional profiles across multiple experimental conditions or gene clusters.
user-invocable: false
---

# clusterProfiler

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.20.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** aisdk, AnnotationDbi, dplyr, enrichit, enrichplot, ggplot2, GO.db, GOSemSim, gson, httr, igraph, jsonlite, magrittr, plyr, qvalue, rlang, tidyr, yulab.utils
- **Install:** `BiocManager::install("clusterProfiler")`

## When to Use

- Performing Over-Representation Analysis or Gene Set Enrichment Analysis.
- Comparing biological themes among gene clusters.
- Visualizing functional profiles of genomic coordinates (supported by ChIPseeker), genes, and gene clusters.
- Querying Gene Ontology annotations online via AnnotationHub or KEGG Pathway and Module data.

## When NOT to Use

- For purely interactive web-based enrichment without an R environment (use web portals like DAVID directly).
- When analyzing species not supported by online databases (unless providing customized user annotations).

## Data Requirements

- Genomic coordinates, gene lists, or gene clusters.
- Annotations from supported ontologies/pathways (e.g., Disease Ontology, DisGeNET, Gene Ontology, KEGG, Reactome, Molecular Signatures Database) or customized user ontologies.

## Key Parameters

- None specified in the provided documentation text.

## Workflow Variants

### Over Representation Analysis

**Intent**: Identify over-represented biological terms and pathways in a list of genes of interest.

**Inputs**:
- `gene_list.txt (a list of gene identifiers, such as Entrez IDs or symbols)`

**Steps**:
1. Import the gene list
2. Perform enrichment analysis using functions like enrichGO, enrichKEGG, enricher, enrichMKEGG, enrichWP, or enrichDAVID
3. Map gene IDs to readable symbols using setReadable
4. Simplify GO terms to reduce redundancy using simplify
5. Visualize results using barplot, dotplot, cnetplot, emapplot, or goplot.



---

### Gene Set Enrichment Analysis

**Intent**: Perform gene set enrichment analysis on a ranked list of genes to identify coordinated pathway changes.

**Inputs**:
- `ranked_gene_list.txt (a list of genes ranked by a numeric score, such as fold change)`

**Steps**:
1. Prepare the ranked gene list
2. Run GSEA using functions like gseGO, gseKEGG, gseMKEGG, gseWP, or GSEA
3. Visualize enrichment scores and distributions using gseaplot or ridgeplot.



---

### Biological Theme Comparison

**Intent**: Compare functional profiles and enriched pathways across multiple gene clusters.

**Inputs**:
- `gene_clusters.csv (a table mapping genes to their respective clusters or experimental conditions)`

**Steps**:
1. Prepare multiple gene clusters
2. Compare clusters using the compareCluster function
3. Visualize comparison results using dotplot, cnetplot, or emapplot.



## Best Practices

- Utilize the package's built-in visualization functions such as `barplot`, `cnetplot`, `dotplot`, `emapplot`, `gseaplot`, `goplot`, and `upsetplot` to interpret enrichment results.
- When querying Gene Ontology, use AnnotationHub to support many species with online annotation queries.
- Provide a reproducible example when posting bugs to the GitHub issue tracker.

## Common Pitfalls

- None specified in the provided documentation text.

## Alternatives

- DOSE (preferred for Disease Ontology, Network of Cancer Gene, and DisGeNET analyses)
- ReactomePA (preferred for Reactome Pathway analysis)
- RDAVIDWebService (preferred for DAVID functional annotation)
- ChIPseeker (preferred for functional profiles of genomic coordinates)

## Citations

- G Yu, LG Wang, Y Han, QY He. clusterProfiler: an R package for comparing biological themes among gene clusters. OMICS: A Journal of Integrative Biology 2012, 16(5):284-287. doi: 10.1089/omi.2011.0118.

## References

- Homepage: https://bioconductor.org/packages/clusterProfiler
- Vignette: https://yulab-smu.github.io/clusterProfiler-book/
