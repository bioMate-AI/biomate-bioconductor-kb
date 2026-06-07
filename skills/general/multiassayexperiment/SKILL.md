---
name: bioconductor-multiassayexperiment
description: Harmonize data management of multiple experimental assays performed on an overlapping set of specimens.  It provides a familiar Bioconductor user experience by extending concepts from SummarizedExperiment, supporting an open-ended mix of st
when_to_use: Use when: Integrating multi-omics experiments (e.g., DNA mutations, RNA abundance) measured on the same biological specimens into a single object.; Managing complex experimental designs where a single patient maps to multiple assays, missing assays, or technical replicates using a sampleMap.; Subsetting multiple experimental assays simultaneously by patient IDs, genomic ranges, or column metadata using [, i. Not for: For sets of assays with the exact same information across all rows (e.g., identical genes or genomic ranges), use SummarizedExperiment instead.
user-invocable: false
---

# MultiAssayExperiment

## When to Use
- Integrating multi-omics experiments (e.g., DNA mutations, RNA abundance) measured on the same biological specimens into a single object.
- Managing complex experimental designs where a single patient maps to multiple assays, missing assays, or technical replicates using a `sampleMap`.
- Subsetting multiple experimental assays simultaneously by patient IDs, genomic ranges, or column metadata using `[`, `intersectColumns`, or `intersectRows`.
- Reshaping multi-assay data into long or wide formats for downstream analysis using `longFormat` or `wideFormat`.

## When NOT to Use
- For sets of assays with the exact same information across all rows (e.g., identical genes or genomic ranges), use `SummarizedExperiment` instead.

## Data Requirements
- **experiments**: A named `list` or `ExperimentList` containing assay datasets (e.g., `matrix`, `SummarizedExperiment`, `RangedSummarizedExperiment`, `RaggedExperiment`).
- **colData**: A `DataFrame` containing primary patient/specimen metadata, where rownames are patient identifiers.
- **sampleMap**: A three-column `DataFrame` (`assay`, `primary`, `colname`) that unambiguously maps experimental observations to rows in `colData`.

## Key Parameters
- **experiments**: A named list of experimental data objects provided to the `MultiAssayExperiment` constructor.
- **colData**: A `DataFrame` of primary metadata describing the biological units (e.g., patients).
- **sampleMap**: A `DataFrame` relating the primary data to the experimental assays.
- **metadata**: A list of study-wide metadata (e.g., citation information) attached to the object.

## Best Practices
- Run the `prepMultiAssay` helper function before constructing the object to diagnose and resolve inconsistent names between the `ExperimentList`, `colData`, and `sampleMap`.
- Use the `listToMap` convenience function to easily convert a list of platform-specific data frames into a valid `sampleMap`.
- Store study-wide metadata, such as citation information, using the `metadata` slot at the `MultiAssayExperiment` level.
- Ensure all elements in the `ExperimentList` are named; unnamed elements will prompt an error during construction.

## Common Pitfalls
- **Unnamed ExperimentList**: Passing an unnamed list of experiments to the constructor or `prepMultiAssay` causes an error. *Fix*: Assign names to the list elements (e.g., `names(objlist) <- c("Affy", "Methyl")`) before construction.
- **Dropped Samples**: Assay samples (colnames) that cannot be mapped to a corresponding row in `colData` via the `sampleMap` are silently dropped. *Fix*: Check the `$drops` element returned by `prepMultiAssay` to identify and fix unmatched identifiers.
- **Mismatched sampleMap Columns**: Providing a `sampleMap` without the exact column names `assay`, `primary`, and `colname`. *Fix*: Ensure the `sampleMap` strictly adheres to this three-column naming convention.

## Alternatives
- **SummarizedExperiment**: Recommended for single-assay datasets or multiple assays that share the exact same row features (e.g., identical genomic ranges).

## Citations
- Ramos, M., et al. (2017). Software for the Integration of Multi-Omics Experiments in Bioconductor. Cancer Research.

## References
- Homepage: https://bioconductor.org/packages/MultiAssayExperiment
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MultiAssayExperiment/inst/doc/MultiAssayExperiment.html
