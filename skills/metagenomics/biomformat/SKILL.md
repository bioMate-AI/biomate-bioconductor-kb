---
name: bioconductor-biomformat
description: This is an R package for interfacing with the BIOM format. This package includes basic tools for reading biom-format files, accessing and subsetting data tables from a biom object (which is more complex than a single table), as well as limi
when_to_use: Use when: Reading BIOM format files (JSON or HDF5) into R using read_biom().; Extracting core observation data (OTU tables) as sparse matrices using biom_data().; Converting BIOM objects to SummarizedExperiment objects using biom_to_SummarizedExperiment().; Constructing a BIOM object from standard R matrices and data frames using make_biom().; Converting BIOM data into a tidy long-format data frame for down. Not for: For statistical analysis of microbiome data, use phyloseq or DESeq2 because biomformat is strictly an I/O and utility package.; For raw sequence processing, use dada2 because biomformat operates on already-constructed contingency tables.
user-invocable: false
---

# biomformat

## When to Use
- Reading BIOM format files (JSON or HDF5) into R using `read_biom()`.
- Extracting core observation data (OTU tables) as sparse matrices using `biom_data()`.
- Converting BIOM objects to `SummarizedExperiment` objects using `biom_to_SummarizedExperiment()`.
- Constructing a BIOM object from standard R matrices and data frames using `make_biom()`.
- Converting BIOM data into a tidy long-format data frame for downstream analysis using `as_tibble.biom()`.

## When NOT to Use
- For statistical analysis of microbiome data, use `phyloseq` or `DESeq2` because `biomformat` is strictly an I/O and utility package.
- For raw sequence processing, use `dada2` because `biomformat` operates on already-constructed contingency tables.

## Data Requirements
- BIOM format files (v1 JSON or v2 HDF5).
- For manual construction via `make_biom()`, a count matrix (features in rows, samples in columns) and optional `data.frame` objects for observation and sample metadata.

## Key Parameters
- **data** (default): The count matrix when using `make_biom()`.
- **observation_metadata** (default): Taxonomy or feature metadata `data.frame` when using `make_biom()`.
- **matrix_element_type** ("int"): The data type of the matrix elements in `make_biom()`.
- **rows** (default): Character vector to subset features directly in `biom_data()`.
- **columns** (default): Character vector to subset samples directly in `biom_data()`.

## Best Practices
- Use `read_biom()` which automatically detects and routes HDF5 files to `read_hdf5_biom()`.
- Use `as_tibble.biom()` to convert data into a tidy long-format for downstream `dplyr` and `purrr` workflows.
- For large datasets (>2GB), use `write_hdf5_biom()` instead of `write_biom()` to avoid JSON serialization limits.

## Common Pitfalls
- Attempting to print a massive BIOM object streams too much data; fix this by relying on the brief summary printed by default or using `biom_data()` to inspect subsets.
- Functions expecting standard matrices fail on sparse matrix classes; fix this by coercing with `as(biom_data(x), "matrix")`.
- Writing very large tables with `write_biom()` fails due to JSON string limits; fix this by using `write_hdf5_biom()` for HDF5 format.

## Alternatives
- `phyloseq`: Has many more utilities for interacting with and analyzing this kind of data.
- `SummarizedExperiment`: The standard Bioconductor container for rectangular feature-by-sample assay data (though `biomformat` interoperates with it).

## Citations
- Paul J. McMurdie and Joseph N Paulson (2015). biomformat: An interface package for the BIOM file format. R/Bioconductor package version 1.34.0.

## References
- Homepage: https://bioconductor.org/packages/biomformat
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/biomformat/inst/doc/biomformat.html
