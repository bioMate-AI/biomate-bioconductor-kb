---
name: bioconductor-gosemsim
description: The semantic comparisons of Gene Ontology (GO) annotations provide quantitative ways to compute similarities between genes and gene groups, and have became important basis for many bioinformatics analysis approaches. GOSemSim is an R packag
when_to_use: Use when: Measuring semantic similarity among GO terms.; Computing functional similarity among gene products.; Performing GO semantic similarity analyses within stem cell transcriptional networks or other biomedical contexts.. Not for: For general biomedical knowledge mining tasks that do not involve Gene Ontology semantic similarity, refer to broader biomedical knowledge mining resources.; When performing analyses that do not require quantitative semantic comparisons of GO annotat
user-invocable: false
---

# GOSemSim

`GOSemSim` is an R package designed for semantic similarity analysis among Gene Ontology (GO) terms and gene products.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.38.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** AnnotationDbi, DBI, digest, GO.db, rlang, yulab.utils
- **Install:** `BiocManager::install("GOSemSim")`

## When to Use
- Measuring semantic similarity among GO terms.
- Computing functional similarity among gene products.
- Performing GO semantic similarity analyses within stem cell transcriptional networks or other biomedical contexts.

## When NOT to Use
- For general biomedical knowledge mining tasks that do not involve Gene Ontology semantic similarity, refer to broader biomedical knowledge mining resources.
- When performing analyses that do not require quantitative semantic comparisons of GO annotations.

## Data Requirements
- Gene Ontology (GO) annotations.
- Gene and gene product datasets requiring functional similarity comparison.

## Key Parameters
- No specific R function parameters are detailed in the provided short vignette text. Please refer to the external full documentation for parameter specifications.

## Best Practices
- Refer to the comprehensive online book (https://yulab-smu.top/biomedical-knowledge-mining-book/) for the full vignette, detailed workflows, and tutorials.
- When seeking assistance, post questions to the Bioconductor support site and tag the post with `GOSemSim`.
- Cite the appropriate primary publications when using `GOSemSim` in published research.

## Common Pitfalls
- Searching for detailed code examples in the package's built-in short vignette; fix this by visiting the external online biomedical knowledge mining book for the complete documentation.
- Failing to tag support questions properly; fix this by tagging posts with `GOSemSim` on the Bioconductor support site.

## Alternatives
- Other Bioconductor packages designed for functional annotation and enrichment analysis (though `GOSemSim` is specifically focused on semantic similarity).

## Citations
- Yu G. Gene Ontology Semantic Similarity Analysis Using GOSemSim. In: Kidder B. (eds) Stem Cell Transcriptional Networks. Methods in Molecular Biology, 2020, 2117:207-215. Humana, New York, NY.
- Yu G, Li F, Qin Y, Bo X, Wu Y and Wang S. GOSemSim: an R package for measuring semantic similarity among GO terms and gene products. Bioinformatics, 2010, 26(7):976-978.

## References
- Homepage: https://bioconductor.org/packages/gosemsim
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/GOSemSim/inst/doc/GOSemSim.html
