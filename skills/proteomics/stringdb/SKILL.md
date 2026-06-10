---
name: bioconductor-stringdb
description: tags: [bioconductor, r, proteomics, vignette-grounded]
when_to_use: Use when: Mapping a list of differentially expressed genes to STRING database identifiers using the map method.; Computing functional enrichment (e.g., Gene Ontology, KEGG) for a set of proteins using get_enrichment.; Visualizing protein-protein interaction networks with custom node colors based on log fold-change using add_diff_exp_color and plot_network.; Retrieving specific interaction partners and exper. Not for: For offline network analysis with custom, non-STRING interaction networks, use igraph instead because STRINGdb is designed to query the online STRING database.; For primary differential expression analysis of microarray data, use limma instead becaus
user-invocable: false
---

# STRINGdb

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.24.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** png, sqldf, plyr, igraph, httr, RColorBrewer, gplots, hash, plotrix
- **System requirements:** URL
- **Install:** `BiocManager::install("STRINGdb")`

## When to Use
- Mapping a list of differentially expressed genes to STRING database identifiers using the `map` method.
- Computing functional enrichment (e.g., Gene Ontology, KEGG) for a set of proteins using `get_enrichment`.
- Visualizing protein-protein interaction networks with custom node colors based on log fold-change using `add_diff_exp_color` and `plot_network`.
- Retrieving specific interaction partners and experimental evidence scores for proteins of interest using `get_interaction_partners`.
- Extracting network clusters/communities from a mapped dataset using `get_clusters`.

## When NOT to Use
- For offline network analysis with custom, non-STRING interaction networks, use `igraph` instead because STRINGdb is designed to query the online STRING database.
- For primary differential expression analysis of microarray data, use `limma` instead because STRINGdb requires pre-analyzed differential expression results (e.g., p-values and log fold changes).

## Data Requirements
- A data frame containing gene identifiers (e.g., HUGO names, Entrez GeneID, ENSEMBL proteins) and optional numeric columns like `pvalue` or `logFC`.
- NCBI taxonomy identifiers for the organism of interest (e.g., 9606 for Human, 10090 for Mouse).

## Key Parameters
- **version** ("12.0"): The STRING database version to query.
- **species** (9606): NCBI taxonomy identifier of the organism.
- **score_threshold** (400): Minimum combined confidence score for interactions to be loaded.
- **input_directory** (""): Local directory path to cache downloaded STRING database files for off-line use.
- **network_type** ("full"): Type of network to retrieve (e.g., "full" for functional or "physical" for physical subnetworks).
- **removeUnmappedRows** (TRUE): Whether to remove rows corresponding to unmapped genes during the `map` step.
- **category** ("Component"): The enrichment category to display when calling `get_enrichment_figure`.
- **target_species_id** (10090): The NCBI taxonomy identifier of the target species when retrieving homologs via `get_homologs_besthits`.

## Best Practices
- Always specify a local `input_directory` when initializing the `STRINGdb` object to cache database files and enable off-line use.
- Remove unassigned genomic positions (e.g., LOC genes) from your data frame before calling `map` to improve the mapping percentage.
- Call `set_background` with your full list of mapped identifiers before running `get_enrichment` to ensure p-values are correctly calibrated against your specific experiment.
- Use `post_payload` to upload custom color mapping (like up/down-regulation halos) to the STRING server before visualizing with `plot_network`.

## Common Pitfalls
- **Wrong enrichment p-values**: Running enrichment statistics without setting the background. Fix: Call `set_background` with the full set of measurable proteins in your experiment before testing.
- **Low mapping rate**: Passing unassigned or unsupported identifiers (like LOC genes). Fix: Filter out non-gene probes before mapping, or set `removeUnmappedRows = FALSE` to manually inspect unmapped rows.
- **Network timeouts/slow execution**: Re-downloading database files every session. Fix: Provide a persistent path to `input_directory` in the constructor to cache files locally.

## Alternatives
- **igraph**: For general-purpose complex network research and custom graph clustering algorithms.
- **limma**: For performing the initial differential expression analysis to generate the p-values and fold changes required by STRINGdb.

## Citations
- Szklarczyk D, et al. (2021). The STRING database in 2021: association networks and functional enrichment analysis for genome-wide gene lists. *Nucleic Acids Research*.

## References
- Homepage: bioconductor.org/packages/STRINGdb
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/STRINGdb/inst/doc/STRINGdb.pdf
