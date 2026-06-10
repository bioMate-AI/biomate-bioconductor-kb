---
name: bioconductor-treeio
description: 'treeio' is an R package to make it easier to import and store phylogenetic tree with associated data; and to link external data from different sources to phylogeny. It also supports exporting phylogenetic tree with heterogeneous associated
when_to_use: Use when: Phylogenetic Tree Input and Output: Managing phylogenetic tree data using the package's core base classes.; Vignette Redirection: Accessing the full documentation and tutorials by navigating to the external treedata-book resource linked in the package stub.. Not for: Detailed In-Package Tutorials: For comprehensive workflows, use the external treedata-book website because the built-in vignette is only a stub.; Tree Reconstruction: For inferring phylogenetic trees from sequence alignments, use external tools becau
user-invocable: false
---

# treeio

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.36.1 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** ape, dplyr, jsonlite, magrittr, rlang, tibble, tidytree, yulab.utils
- **Install:** `BiocManager::install("treeio")`

## When to Use
- **Phylogenetic Tree Input and Output**: Managing phylogenetic tree data using the package's core base classes.
- **Vignette Redirection**: Accessing the full documentation and tutorials by navigating to the external `treedata-book` resource linked in the package stub.

## When NOT to Use
- **Detailed In-Package Tutorials**: For comprehensive workflows, use the external `treedata-book` website because the built-in vignette is only a stub.
- **Tree Reconstruction**: For inferring phylogenetic trees from sequence alignments, use external tools because `treeio` focuses strictly on base classes for input and output.

## Data Requirements
- **Tree Files**: Phylogenetic tree files compatible with the package's base classes for input and output.

## Key Parameters
- **tidy** (FALSE): `knitr::opts_chunk$set` option used to control code formatting in the vignette.
- **message** (FALSE): `knitr::opts_chunk$set` option used to suppress messages during document compilation.

## Best Practices
- **Consult External Documentation**: Go to `https://yulab-smu.top/treedata-book/` for the full vignette and comprehensive workflow instructions.
- **Clean Report Compilation**: Set `tidy = FALSE` and `message = FALSE` in `knitr::opts_chunk$set` when compiling reports to avoid clutter.
- **Utilize Base Classes**: Rely on the base classes provided by the package for consistent phylogenetic tree input and output.

## Common Pitfalls
- **Missing Documentation**: Looking for detailed tutorials in the standard vignette fails because it is only a stub. Fix: Go to the external `treedata-book` link provided in the vignette text.
- **Unwanted Compilation Messages**: R outputs verbose messages during document rendering. Fix: Use `message = FALSE` in the `knitr::opts_chunk$set` options.

## Alternatives
- **ape**: Provides basic phylogenetic tree structures, but `treeio` offers specialized base classes for input and output.
- **phylobase**: Another package for tree classes, but `treeio` is specifically designed for integration with the `treedata-book` ecosystem.
- **tidytree**: Works alongside `treeio` for tidy data manipulation rather than just input/output.

## Citations
- Guangchuang Yu (2026). "treeio: Base Classes and Functions for Phylogenetic Tree Input and Output".

## References
- Homepage: bioconductor.org/packages/treeio
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/treeio/inst/doc/treeio.html
