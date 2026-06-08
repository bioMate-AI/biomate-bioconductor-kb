---
name: bioconductor-keggrest
description: A package that provides a client interface to the Kyoto Encyclopedia of Genes and Genomes (KEGG) REST API. Only for academic use by academic users belonging to academic institutions (see <https://www.kegg.jp/kegg/rest/>). Note that KEGGREST
when_to_use: Use when: Exploring available KEGG databases and organisms using listDatabases() and keggList().; Retrieving specific KEGG entries, including amino acid (aaseq) or nucleotide (ntseq) sequences as AAStringSet or DNAStringSet objects using keggGet().; Downloading KEGG pathway maps as PNG images using keggGet() with the "image" option.; Searching for genes or compounds by keywords, chemical formulas, or exact . Not for: For commercial applications, use ReactomePA instead because the KEGG API is strictly restricted to academic use by academic institutions.; For offline or high-throughput batch queries of thousands of genes, use local annotation packages like org.Hs.e
user-invocable: false
---

# KEGGREST

## When to Use
- Exploring available KEGG databases and organisms using `listDatabases()` and `keggList()`.
- Retrieving specific KEGG entries, including amino acid (`aaseq`) or nucleotide (`ntseq`) sequences as `AAStringSet` or `DNAStringSet` objects using `keggGet()`.
- Downloading KEGG pathway maps as PNG images using `keggGet()` with the `"image"` option.
- Searching for genes or compounds by keywords, chemical formulas, or exact mass using `keggFind()`.
- Converting between KEGG identifiers and external database IDs (e.g., NCBI Gene ID) using `keggConv()`.

## When NOT to Use
- For commercial applications, use `ReactomePA` instead because the KEGG API is strictly restricted to academic use by academic institutions.
- For offline or high-throughput batch queries of thousands of genes, use local annotation packages like `org.Hs.eg.db` instead to avoid server-side limitations.
- For complex pathway network topology analyses, use `KEGGgraph` or `ROntoTools` instead.

## Data Requirements
- **Valid Identifiers**: Input queries must be valid KEGG identifiers (e.g., `"hsa:10458"`, `"path:hsa00010"`, `"cpd:C00493"`) or supported external identifiers.
- **Internet Connection**: An active internet connection is required to query the live KEGG REST API.

## Key Parameters
- **database**: The target KEGG database to query (e.g., `"pathway"`, `"organism"`, `"compound"`, `"genes"`).
- **query**: The search term, identifier, or vector of identifiers to retrieve (e.g., `"hsa:10458"`).
- **option**: Specific query options for `keggGet()` (e.g., `"aaseq"`, `"ntseq"`, `"image"`) or `keggFind()` (e.g., `"formula"`, `"exact_mass"`, `"mol_weight"`).

## Best Practices
- Verify the target organism's official KEGG code (e.g., `"hsa"` for human, `"eco"` for E. coli) using `keggList("organism")` before running queries.
- Limit `keggGet()` queries to a maximum of 10 identifiers at once, as the server restricts larger batches.
- Use `keggLink()` to find relationships across databases, such as retrieving all pathways associated with specific genes.

## Common Pitfalls
- **Truncated results from keggGet()**: Occurs when supplying more than 10 inputs to `keggGet()`; fix this by batching requests into chunks of 10 or fewer.
- **Invalid organism code**: Using common names instead of the official 3-4 letter KEGG code returns empty results; fix this by looking up the code with `keggList("organism")`.
- **Commercial use violation**: Occurs when using the package for non-academic purposes; fix this by switching to open-source databases like Reactome.

## Alternatives
- `ReactomePA`: For pathway analysis using the open-source, commercially unrestricted Reactome database.
- `clusterProfiler`: For comprehensive enrichment analysis integrating KEGG and GO annotations locally.
- `AnnotationDbi`: For local, offline mapping of gene IDs without relying on web APIs.

## Citations
- Tenenbaum D (2024). KEGGREST: Client-side REST access to the Kyoto Encyclopedia of Genes and Genomes (KEGG). R package version 1.46.0.
- Kanehisa M, Goto S (2000). KEGG: kyoto encyclopedia of genes and genomes. Nucleic Acids Research, 28(1), 27-30.

## References
- Homepage: https://bioconductor.org/packages/KEGGREST
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/KEGGREST/inst/doc/KEGGREST-vignette.html
