---
name: bioconductor-clusterprofiler
description: This package supports functional characteristics of both coding and non-coding genomics data for thousands of species with up-to-date gene annotation. It provides a univeral interface for gene functional annotation from a variety of sources
when_to_use: Use when: Performing Over-Representation Analysis or Gene Set Enrichment Analysis.; Comparing biological themes among gene clusters.; Visualizing functional profiles of genomic coordinates (supported by ChIPseeker), genes, and gene clusters.; Querying Gene Ontology annotations online via AnnotationHub or KEGG Pathway and Module data.. Not for: For purely interactive web-based enrichment without an R environment (use web portals like DAVID directly).; When analyzing species not supported by online databases (unless providing customized user annotations).
user-invocable: false
---

# clusterProfiler

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
- No specific parameters are detailed in the provided vignette text.

## Best Practices
- Utilize the package's built-in visualization functions such as `barplot`, `cnetplot`, `dotplot`, `emapplot`, `gseaplot`, `goplot`, and `upsetplot` to interpret enrichment results.
- When querying Gene Ontology, use AnnotationHub to support many species with online annotation queries.
- Provide a reproducible example when posting bugs to the GitHub issue tracker.

## Common Pitfalls
- Failing to find answers to common problems because the user did not visit the clusterProfiler homepage documentation first.
- Posting questions to the Bioconductor support site without tagging the post with `clusterProfiler`, leading to delayed responses.
- Attempting to analyze unsupported species without supplying a customized ontology or user annotation.

## Alternatives
- `DOSE`: Specifically focused on Disease Ontology and Network of Cancer Gene enrichment.
- `ReactomePA`: Specifically tailored for Reactome Pathway analysis.
- `goseq`: Alternative for GO enrichment that explicitly corrects for RNA-seq transcript length bias.

## Citations
- G Yu, LG Wang, Y Han, QY He. clusterProfiler: an R package for comparing biological themes among gene clusters. OMICS: A Journal of Integrative Biology 2012, 16(5):284-287. doi: 10.1089/omi.2011.0118.

## References
- Homepage: https://bioconductor.org/packages/clusterProfiler
- Vignette: https://yulab-smu.github.io/clusterProfiler-book/
