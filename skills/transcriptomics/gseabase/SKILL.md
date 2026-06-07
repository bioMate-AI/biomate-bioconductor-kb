---
name: bioconductor-gseabase
description: This package provides classes and methods to support Gene Set Enrichment Analysis (GSEA).
when_to_use: Use when: Gene Set Management: Storing and manipulating gene sets and collections using robust S4 classes like GeneSet() and GeneSetCollection().; Importing Standard Formats: Reading gene sets encoded in XML following the schema and conventions of the Broad Institute using getBroadSets().; Identifier Mapping: Programmatically mapping gene identifiers within gene sets (e.g., Symbol to Entrez) using mapIdenti. Not for: For performing the actual statistical enrichment test (e.g., GSEA, ORA); use the fgsea or limma packages instead because GSEABase is purely for data structure management.; For fast, tidyverse-compatible data frame manipulation of gene sets; use the m
user-invocable: false
---

# GSEABase

## When to Use
- **Gene Set Management**: Storing and manipulating gene sets and collections using robust S4 classes like `GeneSet()` and `GeneSetCollection()`.
- **Importing Standard Formats**: Reading gene sets encoded in XML following the schema and conventions of the Broad Institute using `getBroadSets()`.
- **Identifier Mapping**: Programmatically mapping gene identifiers within gene sets (e.g., Symbol to Entrez) using `mapIdentifiers()` and Bioconductor annotation packages.
- **Dynamic Collection Building**: Building custom gene set collections dynamically from GO or KEGG databases using `GOCollection()`.

## When NOT to Use
- For performing the actual statistical enrichment test (e.g., GSEA, ORA); use the fgsea or limma packages instead because GSEABase is purely for data structure management.
- For fast, tidyverse-compatible data frame manipulation of gene sets; use the msigdbr package instead because GSEABase relies heavily on strict S4 object classes.

## Data Requirements
- **Input formats**: Broad `.xml` files, `ExpressionSet` objects, or standard R vectors of gene identifiers.
- **Identifiers**: Gene IDs (Entrez, Symbol, Annotation) must be consistent across a single `GeneSet`.
- **Annotations**: Requires corresponding organism-specific annotation packages (e.g., `hgu95av2.db`, `org.Hs.eg.db`) if identifier mapping or GO extraction is needed.

## Key Parameters
- **setName**: A character string specifying the name of the gene set.
- **geneIdType** (`NullIdentifier()`): Specifies the gene identifier type (e.g., `EntrezIdentifier()`, `SymbolIdentifier()`, `AnnotationIdentifier()`) to ensure safe mapping.
- **collectionType** (`NullCollection()`): Defines the source/metadata of the gene set (e.g., `GOCollection()`, `BroadCollection()`).
- **urls**: The file path, URL, or connection to the `.xml` file when importing Broad sets.
- **evidenceCode**: Used within `GOCollection()` to filter pathways satisfying specific GO evidence constraints (e.g., `"IMP"`, `"IDA"`).
- **phenotype**: A character string describing the phenotype under consideration when creating a `GeneColorSet()`.

## Best Practices
- Always explicitly define the `geneIdType` (e.g., `EntrezIdentifier()`) when creating a `GeneSet()` to prevent downstream mapping errors.
- Leverage `mapIdentifiers()` in conjunction with an annotation package to harmonize gene IDs in the `GeneSetCollection()` before intersecting with your expression data.
- Use `details()` to inspect the metadata, creation date, and source of a `GeneSet` for careful curation.
- Validate gene sets against your expression matrix by directly subsetting the `ExpressionSet` using the `GeneSet` object.

## Common Pitfalls
- **Empty intersections during subsetting**: Caused by the gene set using Symbols while the expression data uses Annotation IDs. *Fix*: Use `mapIdentifiers()` to convert the `GeneSet` to match the data's ID type before subsetting.
- **Memory bloat with GO collections**: Caused by creating sets for every single GO term indiscriminately. *Fix*: Filter GO terms by providing arguments such as `evidenceCode` to `GOCollection()` to restrict the pathways.
- **Loss of directionality in sets**: Standard gene sets do not capture whether a gene is upregulated or downregulated. *Fix*: Use `GeneColorSet()` to indicate how features of genes and phenotypes are associated.

## Alternatives
- **msigdbr**: Provides MSigDB gene sets directly as tidy data frames rather than S4 objects, ideal for tidyverse workflows.
- **fgsea**: Uses simple named lists of character vectors for gene sets, bypassing the need for complex S4 classes entirely.

## Citations
- Morgan M, Falcon S, Gentleman R (2023). "GSEABase: Gene set enrichment data structures and methods." Bioconductor.

## References
- Homepage: https://bioconductor.org/packages/GSEABase
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/GSEABase
