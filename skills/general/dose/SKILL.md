---
name: bioconductor-dose
description: This package implements five methods proposed by Resnik, Schlicker, Jiang, Lin and Wang respectively for measuring semantic similarities among DO terms and gene products. Enrichment analyses including hypergeometric model and gene set enric
when_to_use: "Use when: Disease Ontology Analysis: Performing Disease Ontology Semantic and Enrichment analysis as described by the package authors.. Not for: For formatting R markdown documents, use knitr because DOSE is strictly for Disease Ontology analysis."
user-invocable: false
---

# DOSE

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.6.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** AnnotationDbi, enrichit, ggplot2, GOSemSim, reshape2, yulab.utils
- **Install:** `BiocManager::install("DOSE")`

## When to Use
- **Disease Ontology Analysis**: Performing Disease Ontology Semantic and Enrichment analysis as described by the package authors.

## When NOT to Use
- For formatting R markdown documents, use `knitr` because DOSE is strictly for Disease Ontology analysis.

## Data Requirements
- Requires loading the package into the R session via `library(DOSE)`.

## Key Parameters
- **pkg**: Used in the `Biocpkg` function example to format package links.
- **tidy**: Used in `knitr::opts_chunk$set` to control code formatting.

## Best Practices
- Load the package using `library(DOSE)`.
- Cite the primary publication (Yu et al. 2015) when using DOSE in published research.

## Common Pitfalls
- **Missing Citation**: Forgetting to cite the package in publications; fix by including the citation to Bioinformatics 2015.

## Alternatives
- **knitr**: For document generation and vignette formatting, as it handles markdown chunk options rather than biological enrichment.

## Citations
- G Yu, LG Wang, GR Yan, QY He. DOSE: an R/Bioconductor package for Disease Ontology Semantic and Enrichment analysis. Bioinformatics 2015, 31(4):608-609.

## References
- Homepage: https://bioconductor.org/packages/DOSE
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/DOSE/inst/doc/DOSE.html

<!-- biomate-cta -->
---

## Run this on BioMate

This skill is the **knowledge layer** — when, why, and how to use `dose`. To **run this analysis on your own data** with managed compute, automated QC, and reproducible outputs, use **[BioMate](https://www.biomate.ai?ref=kb&pkg=dose)** — free to start.

▶ **[Open `dose` on BioMate →](https://www.biomate.ai?ref=kb&pkg=dose)**
