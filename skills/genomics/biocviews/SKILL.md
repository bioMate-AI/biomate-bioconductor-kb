---
name: bioconductor-biocviews
description: Infrastructure to support 'views' used to classify Bioconductor packages. 'biocViews' are directed acyclic graphs of terms from a controlled vocabulary. There are three major classifications, corresponding to 'software', 'annotation', and '
when_to_use: Use when: Generating repository HTML and control files (PACKAGES, VIEWS) for a CRAN-style layout using genReposControlFiles and writeRepositoryHtml.; Extracting package vignettes from source packages to a local directory using extractVignettes.; Querying a repository to generate a list of BiocViews objects for specific top-level terms (e.g., "Software") using getBiocSubViews.; Querying available vocabulary . Not for: For general package development tasks like linting or unit testing; use BiocCheck or devtools instead because biocViews focuses on repository HTML and vocabulary generation.; For searching Bioconductor packages interactively in a user-friendly GUI; u
user-invocable: false
---

# biocViews

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.80.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** Biobase, graph, RBGL, XML, RCurl, RUnit, BiocManager
- **Install:** `BiocManager::install("biocViews")`

## When to Use
- Generating repository HTML and control files (PACKAGES, VIEWS) for a CRAN-style layout using `genReposControlFiles` and `writeRepositoryHtml`.
- Extracting package vignettes from source packages to a local directory using `extractVignettes`.
- Querying a repository to generate a list of `BiocViews` objects for specific top-level terms (e.g., "Software") using `getBiocSubViews`.
- Querying available vocabulary subterms from a `graphNEL` object using `getSubTerms`.

## When NOT to Use
- For general package development tasks like linting or unit testing; use `BiocCheck` or `devtools` instead because `biocViews` focuses on repository HTML and vocabulary generation.
- For searching Bioconductor packages interactively in a user-friendly GUI; use the Bioconductor website search or `BiocPkgTools` instead because `biocViews` generates static HTML views.

## Data Requirements
- A CRAN-style repository directory containing source packages (`src/contrib`) and binary packages (`bin/windows/contrib`, `bin/macosx/contrib`).
- A vocabulary of terms defined in a dot format file (e.g., `biocViewsVocab.dot`) which is converted to a `graphNEL` object.

## Key Parameters
- **reposRoot**: The top-level directory path for the repository.
- **contribPaths**: A named character vector specifying paths to source and binary packages.
- **reposUrl**: The URL or file path of the repository to query.
- **topTerm**: The top-level vocabulary node to query (e.g., "Software").
- **term**: The base term for which all subterms should be returned in `getSubTerms`.
- **dir**: Output directory path for generated HTML views in `writeBiocViews`.

## Best Practices
- Establish a standard CRAN-style layout with `src/contrib` and `bin` directories before running `genReposControlFiles`.
- Extract vignettes using `extractVignettes` before generating the repository HTML.
- Use `getBiocSubViews` with a valid `graphNEL` vocabulary object (like `biocViewsVocab`) to categorize packages.
- Generate the final HTML views using `writeBiocViews` pointing to a dedicated output directory.

## Common Pitfalls
- **Missing repository structure**: Running `genReposControlFiles` without the correct `contribPaths` names. Fix: Ensure the `contribPaths` vector has exact names like "source", "win.binary", and "mac.binary".
- **Vocabulary terms with spaces**: Adding terms to the dot file with spaces, which breaks the graph. Fix: Ensure terms use underscores instead of spaces.
- **Missing tools for vocabulary update**: Failing to convert the dot file to GXL. Fix: Ensure `dot2gxl` from graphviz is installed and on your PATH.

## Alternatives
- **BiocPkgTools**: For advanced, user-facing exploration and network analysis of Bioconductor packages and their metadata.
- **BiocCheck**: For verifying package compliance with Bioconductor standards, including biocViews validation.
- **pkgdown**: For generating documentation websites for individual R packages rather than entire repositories.

## Citations
- Gentleman, R. et al. (2024). biocViews: Categorized views of R package repositories. R package version 1.74.0.

## References
- Homepage: bioconductor.org/packages/biocViews
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/biocViews/inst/doc/biocViews-HOWTO.pdf
