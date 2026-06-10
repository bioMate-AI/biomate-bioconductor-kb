---
name: bioconductor-graphite
description: Graph objects from pathway topology derived from KEGG, Panther, PathBank, PharmGKB, Reactome SMPDB and WikiPathways databases.
when_to_use: Use when: Retrieving pathway topologies as directed/undirected graph objects from major databases (KEGG, Reactome, WikiPathways, Panther, PathBank, PharmGKB) using the pathways function.; Converting pathway identifiers (e.g., from UNIPROT to SYMBOL or ENTREZID) to match experimental data using convertIdentifiers.; Preparing and running topology-aware pathway enrichment analyses like SPIA (prepareSPIA, runSP. Not for: For simple over-representation analysis (ORA) or gene set enrichment analysis (GSEA) that ignores pathway topology, use clusterProfiler or fgsea instead because they do not require graph construction.; For de novo gene co-expression network construct
user-invocable: false
---

# graphite

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.58.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** AnnotationDbi, graph, httr, rappdirs, rlang, lifecycle, purrr, dir.expiry
- **Install:** `BiocManager::install("graphite")`

## When to Use
- Retrieving pathway topologies as directed/undirected graph objects from major databases (KEGG, Reactome, WikiPathways, Panther, PathBank, PharmGKB) using the `pathways` function.
- Converting pathway identifiers (e.g., from UNIPROT to SYMBOL or ENTREZID) to match experimental data using `convertIdentifiers`.
- Preparing and running topology-aware pathway enrichment analyses like SPIA (`prepareSPIA`, `runSPIA`), topologyGSA (`runTopologyGSA`), or clipper (`runClipper`).
- Exporting pathway network structures to Cytoscape for visualization using `cytoscapePlot`.

## When NOT to Use
- For simple over-representation analysis (ORA) or gene set enrichment analysis (GSEA) that ignores pathway topology, use `clusterProfiler` or `fgsea` instead because they do not require graph construction.
- For de novo gene co-expression network construction, use `WGCNA` instead because graphite retrieves curated, database-defined pathway topologies rather than inferring networks from data.

## Data Requirements
- **Input format**: Gene identifiers (e.g., Entrez IDs, Ensembl IDs, or UniProt accessions) or metabolite identifiers (e.g., CHEBI).
- **For enrichment**: A vector of differentially expressed genes/metabolites with their log-fold changes (e.g., `DE_Colorectal`) and a background list of all genes.
- **Database versioning**: Requires active internet access for initial database downloads via `pathways`, though pathways can be cached locally.

## Key Parameters
- **species**: Character; the target organism (e.g., "hsapiens", "mmusculus") used in `pathways`.
- **database**: Character; the pathway database to query (e.g., "kegg", "reactome", "wikipathways") used in `pathways`.
- **which**: Character; specifies whether to retrieve "proteins", "metabolites", or "mixed" networks in functions like `nodes`, `edges`, and `pathwayGraph`.

## Best Practices
- Always convert input gene or metabolite identifiers to match your experimental data (e.g., "SYMBOL" or "ENTREZID") using `convertIdentifiers` before running topological analyses.
- Use the `pathwayGraph` function to convert pathway topologies into standard `graphNEL` objects to leverage external network visualization and graph operations.
- When analyzing both transcriptomic and metabolomic data, use `which = "mixed"` to retrieve pathways containing both proteins and metabolites without edge propagation.
- Check available databases for your species of interest using the `pathwayDatabases` function.

## Common Pitfalls
- **Identifier mismatch**: Passing gene symbols to a database structured around UNIPROT IDs will result in zero mapped nodes; fix this by translating identifiers using `convertIdentifiers` prior to analysis.
- **Ignoring metabolites in metabolomics**: Using the default `which` parameter will remove metabolite nodes and propagate edges through them; fix this by setting `which = "metabolites"` or `which = "mixed"` for metabolomics data.
- **Losing edge attributes**: Treating directed biological interactions as simple undirected graphs can dilute statistical power; fix this by preserving edge attributes (e.g., "Binding", "Control") visible via `edgeData`.

## Alternatives
- **SPIA**: Specifically designed for Signaling Pathway Impact Analysis, which is natively supported by graphite-derived topologies via `prepareSPIA`.
- **clipper**: A package for topological analysis that can be used to study metabolomics data, natively integrated via `runClipper`.
- **topologyGSA**: A package for topological gene set analysis, natively integrated via `runTopologyGSA`.

## Citations
- Sales G, Calura E, Romualdi C (2012). "graphite: a Bioconductor package for pathway topology alignments and network-based analyses." BMC Bioinformatics.

## References
- Homepage: https://bioconductor.org/packages/graphite
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/graphite/inst/doc/graphite.pdf
