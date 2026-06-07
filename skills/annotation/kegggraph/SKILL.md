---
name: bioconductor-kegggraph
description: KEGGGraph is an interface between KEGG pathway and graph object as well as a collection of tools to analyze, dissect and visualize these graphs. It parses the regularly updated KGML (KEGG XML) files into graph models maintaining all essenti
when_to_use: Use when: KGML Parsing: Parsing local or remote KGML (KEGG XML) files into standard R graphNEL objects using parseKGML2Graph.; Pathway Dissection: Subsetting complex pathways into smaller subgraphs based on node types (using subGraphByNodeType) or specific neighborhoods (using subKEGGgraph).; Graph Merging: Combining multiple related pathways (e.g., signaling pathways) into a single unified network using me. Not for: For dynamic visualization, interactive navigation, and manual editing of KEGG pathway diagrams, use KGML-ED instead.; For performing Signaling Pathway Impact Analysis directly without manual graph manipulation, use SPIA instead.; For modern ggplot2-b
user-invocable: false
---

# KEGGgraph

## When to Use
- **KGML Parsing**: Parsing local or remote KGML (KEGG XML) files into standard R `graphNEL` objects using `parseKGML2Graph`.
- **Pathway Dissection**: Subsetting complex pathways into smaller subgraphs based on node types (using `subGraphByNodeType`) or specific neighborhoods (using `subKEGGgraph`).
- **Graph Merging**: Combining multiple related pathways (e.g., signaling pathways) into a single unified network using `mergeGraphs`.
- **Topology Analysis**: Calculating graph characteristics like in-degrees, out-degrees, or betweenness centrality (via `brandes.betweenness.centrality` from `RBGL`) on biological pathways.

## When NOT to Use
- For dynamic visualization, interactive navigation, and manual editing of KEGG pathway diagrams, use `KGML-ED` instead.
- For performing Signaling Pathway Impact Analysis directly without manual graph manipulation, use `SPIA` instead.
- For modern `ggplot2`-based visualization of KEGG pathways, use `ggkegg` instead because `KEGGgraph` relies on `Rgraphviz` for rendering.

## Data Requirements
- **KGML Files**: Local KGML files or a valid internet connection to fetch them remotely via `retrieveKGML`.
- **Node Identifiers**: Input data must align with KEGG standards (e.g., Entrez Gene IDs) to map correctly to the parsed graph nodes.

## Key Parameters
- **genesOnly** (FALSE): Logical passed to `parseKGML2Graph`; if `TRUE`, non-gene nodes (like compounds or maps) are removed from the graph.
- **expandGenes** (TRUE): Logical passed to `parseKGML2Graph` or `KEGGpathway2Graph`; if `TRUE`, nodes representing multiple homologues are topologically expanded.
- **organism** ("hsa"): Three-letter KEGG organism code used in `retrieveKGML`.
- **destfile**: File path to save the remotely retrieved KGML file when using `retrieveKGML`.

## Best Practices
- **Expand Gene Nodes**: Set `expandGenes=TRUE` when parsing to ensure that nodes representing multiple gene products (homologues) are expanded into individual nodes.
- **Merge Related Pathways**: Use `mergeGraphs` to union related pathways together, which helps resolve disconnected nodes that lack edges in a single specific disease pathway.
- **Translate Identifiers**: Use `translateGeneID2KEGGID` to map Entrez Gene IDs from microarray data to KEGG IDs before performing graph operations.
- **Subset for Clarity**: Use `subKEGGgraph` to divide and conquer large pathways, maintaining KEGG information while subsetting the graph.

## Common Pitfalls
- **Disconnected Nodes**: Disease pathways often contain genes with a degree of 0 because their interaction partners are in other pathways; fix this by using `mergeGraphs` to combine linked pathways.
- **Grouped Homologues**: A single node in KEGG may represent multiple homologues (e.g., MAPK1 and MAPK3); fix this by setting `expandGenes=TRUE` during parsing.
- **Identifier Mismatch**: Microarray data uses Entrez IDs but the graph uses KEGG IDs; fix this by using `translateGeneID2KEGGID` or `translateKEGGID2GeneID`.

## Alternatives
- **SPIA**: A package implementing the Signaling Pathway Impact Analysis algorithm that internally uses pathway topology but requires less manual graph manipulation.
- **KGML-ED**: A standalone tool designed for the dynamic visualization, interactive navigation, and editing of KEGG pathway diagrams.

## Citations
- Zhang, J. D., & Wiemann, S. (2009). KEGGgraph: a graph approach to KEGG PATHWAY in R and Bioconductor. Bioinformatics, 25(11), 1470-1471.

## References
- Homepage: https://bioconductor.org/packages/KEGGgraph
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/KEGGgraph/inst/doc/KEGGgraph.pdf
