---
name: bioconductor-cellxgenedp
description: The cellxgene data portal (https://cellxgene.cziscience.com/) provides a graphical user interface to collections of single-cell sequence data processed in standard ways to 'count matrix' summaries. The cellxgenedp package provides an alternative, R-based inteface, allowind data discovery, viewing, and downloading.
when_to_use: Use when: Discovery and retrieval; Case studies; Single-cell RNA-seq analysis (cellxgenedp). Not for: Requires raw count data (not normalized values); Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# cellxgenedp

## Workflows

### Standard Workflow

The cellxgene data portal (https://cellxgene.cziscience.com/) provides a graphical user interface to collections of single-cell sequence data processed in standard ways to 'count matrix' summaries. The cellxgenedp package provides an alternative, R-based inteface, allowind data discovery, viewing, and downloading.

```r
library(cellxgenedp)
library(dplyr)

# 1. Initialize database
cellxgene_db <- db()

# 2. Discover collections, datasets, and authors
cols <- collections(cellxgene_db)
dsets <- datasets(cellxgene_db)
auths <- authors()

# 3. Query datasets by specific author
author_datasets <- left_join(
  authors(),
  datasets(),
  by = "collection_id",
  relationship = "many-to-many"
)

# 4. Filter by disease using facets
covid_datasets <- author_datasets |>
  filter(facets_filter(disease, "label", "COVID-19"))
```
*Inputs/Outputs:* Takes online metadata from the CELLxGENE data portal retrieved via `db()`, and outputs filtered tibbles of collections, datasets, and authors matching specific search criteria.

## When to Use
- To programmatically discover, filter, and retrieve single-cell RNA-seq datasets from the CELLxGENE data portal.
- To query datasets by specific authors or consortia using `authors()` and `datasets()`.
- To identify datasets matching specific ontological terms (e.g., disease, cell type, tissue) using `facets()` and `facets_filter()`.
- To launch an interactive Shiny interface for data discovery and download using `cxg()`.

## When NOT to Use
- For downstream single-cell analysis like clustering, dimensionality reduction, or differential expression (use `scran`, `scater`, or `Seurat` instead).
- For analyzing private, non-public single-cell datasets not hosted on the CELLxGENE portal.

## Data Requirements
- No local input files are required to start; the package retrieves metadata dynamically from the CELLxGENE portal via `db()`.
- Downloaded datasets are typically in H5AD format, which can be loaded into R using `zellkonverter`.

## Key Parameters
- **relationship** ("many-to-many"): Parameter used in `left_join` when merging authors and datasets.
- **facet** ("disease"): Column name passed to `facets()` to retrieve ontology terms and counts.
- **label** ("COVID-19"): Target ontology term label used in `facets_filter()`.

## Best Practices
- Use `db()` to fetch the latest database state from the CELLxGENE portal at the start of your session.
- Use `distinct(authors())` to deduplicate author records before performing downstream joins, as some collections contain duplicate author entries.
- Use `facets(db(), "disease")` or other facet fields to inspect available ontology terms and their exact labels before filtering.

## Common Pitfalls
- Joining authors and datasets directly without handling many-to-many relationships, leading to warnings. Fix: Specify `relationship = "many-to-many"` in `left_join()`.
- Assuming a single disease per dataset. Fix: Remember that the `disease` column is a list-of-lists because a dataset can contain multiple diseases; use `facets_filter()` or `tidyr::unnest_longer()` to handle it.

## Alternatives
- `scRNAseq` for accessing curated public single-cell datasets from Bioconductor.
- `HCAData` for accessing Human Cell Atlas data.

## Citations
- Morgan M (2024). cellxgenedp: Discover and retrieve single-cell data from the CELLxGENE portal. R package version 1.16.0.

## References
- Homepage: bioconductor.org/packages/cellxgenedp
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cellxgenedp/inst/doc/Discovery_and_retrieval.html
