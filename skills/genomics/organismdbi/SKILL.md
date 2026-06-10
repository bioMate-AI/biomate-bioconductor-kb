---
name: bioconductor-organismdbi
description: The package enables a simple unified interface to several annotation packages each of which has its own schema by taking advantage of the fact that each of these packages implements a select methods.
when_to_use: Use when: Unified Annotation Queries: Querying multiple annotation resources (e.g., TxDb and OrgDb) simultaneously through a single unified interface using select.; Custom Meta-Package Building: Building custom OrganismDbi meta-packages (like Homo.sapiens) that link genome-centric and gene-centric databases using makeOrganismPackage.; Feature Extraction: Extracting genomic features (transcripts, exons, cds). Not for: Non-Model Organisms: When working with non-model organisms that do not have pre-built OrgDb or TxDb packages available to link together.; Cyclic Graph Relationships: When the relationships between your annotation packages present more than one pathwa
user-invocable: false
---

# OrganismDbi

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.54.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics, AnnotationDbi, Seqinfo, GenomicFeatures
- **Imports:** DBI, BiocManager, Biobase, graph, RBGL, S4Vectors, IRanges, GenomicRanges
- **System requirements:** URL
- **Install:** `BiocManager::install("OrganismDbi")`

## When to Use
- **Unified Annotation Queries**: Querying multiple annotation resources (e.g., `TxDb` and `OrgDb`) simultaneously through a single unified interface using `select`.
- **Custom Meta-Package Building**: Building custom `OrganismDbi` meta-packages (like `Homo.sapiens`) that link genome-centric and gene-centric databases using `makeOrganismPackage`.
- **Feature Extraction**: Extracting genomic features (transcripts, exons, cds) mapped directly to gene symbols or other identifiers using `transcripts`, `exons`, or `cds`.
- **Grouped Feature Extraction**: Grouping genomic features by a specific identifier (e.g., by gene) using `transcriptsBy`, `exonsBy`, or `cdsBy`.

## When NOT to Use
- **Non-Model Organisms**: When working with non-model organisms that do not have pre-built `OrgDb` or `TxDb` packages available to link together.
- **Cyclic Graph Relationships**: When the relationships between your annotation packages present more than one pathway between any two nodes/objects (the package cannot handle cycles in the graph).

## Data Requirements
- **Annotation Packages**: Installed Bioconductor annotation packages (e.g., `org.Hs.eg.db`, `TxDb.Hsapiens.UCSC.hg19.knownGene`, `GO.db`).
- **Graph Data**: A list of short two-element character vectors representing foreign key relationships (e.g., `graphData`) when building custom packages.

## Key Parameters
- **keys**: The character vector of keys to search for in `select` or `keys`.
- **keytype**: The type of input keys (e.g., `"ENTREZID"`) provided to `select` or `keys`.
- **columns**: The columns of information to retrieve (e.g., `c("TXNAME", "SYMBOL")`) in `select`, `transcripts`, or `transcriptsBy`.
- **by**: The grouping factor (e.g., `"gene"`) used in `transcriptsBy`.
- **pkgname**: The name of the custom package to create (e.g., `"Homo.sapiens"`) in `makeOrganismPackage`.
- **graphData**: The list expressing how different packages relate to each other via foreign keys in `makeOrganismPackage`.

## Best Practices
- **Inspect Fields**: Use `keytypes()` and `columns()` to inspect valid query fields before executing a search.
- **Use Select**: Prefer using the unified `select()` method to retrieve multi-database annotations in a single tabular format.
- **GRanges Integration**: When extracting genomic ranges, use functions like `transcripts(Homo.sapiens, columns=...)` to get `GRanges` objects pre-annotated with gene metadata.
- **Consistent Builds**: Take extra care to ensure that the different packages used in `makeOrganismPackage` are from the same build (e.g., hg19).

## Common Pitfalls
- **Conflicting Package Schemas**: Mixing incompatible `TxDb` and `OrgDb` versions. *Fix*: Ensure the underlying `TxDb` and `OrgDb` packages correspond to the same genome assembly and annotation release.
- **Non-Unique Columns**: Having more than one example of each field across supporting packages. *Fix*: Ensure all values returned by `columns` are unique across ALL of the supporting packages before using `makeOrganismPackage`.
- **Graph Cycles**: Providing a `graphData` list with multiple pathways between nodes. *Fix*: Choose exactly one foreign key relationship to connect any two packages in your graph.

## Alternatives
- **AnnotationDbi**: The base package for querying individual `OrgDb` databases.
- **GenomicFeatures**: Specifically for managing and querying `TxDb` transcript databases.

## Citations
- Carlson M, Atiku Mustapha A (2026). OrganismDbi: A meta framework for Annotation Packages.

## References
- Homepage: https://bioconductor.org/packages/OrganismDbi
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/OrganismDbi/inst/doc/OrganismDbi.pdf
