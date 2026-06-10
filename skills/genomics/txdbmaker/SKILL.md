---
name: bioconductor-txdbmaker
description: A set of tools for making TxDb objects from genomic annotations from various sources (e.g. UCSC, Ensembl, and GFF files). These tools allow the user to download the genomic locations of transcripts, exons, and CDS, for a given assembly, and
when_to_use: Use when: Creating TxDb objects from UCSC Genome Browser transcript tables using makeTxDbFromUCSC.; Retrieving and assembling transcript annotations from BioMart datasets using makeTxDbFromBiomart.; Extracting transcript information directly from GFF3 or GTF files using makeTxDbFromGFF.; Saving and loading created TxDb objects to/from SQLite database files using saveDb and loadDb to avoid repeated download . Not for: For extracting features (like transcripts, exons, and CDS) from an already created TxDb object, use GenomicFeatures instead, which implements the flexible extraction methods.; For creating TxDb objects from unsupported BioMart datasets (not all BioMa
user-invocable: false
---

# txdbmaker

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.8.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics, S4Vectors, Seqinfo, GenomicRanges, GenomicFeatures
- **Imports:** httr, rjson, DBI, RSQLite, IRanges, UCSC.utils, GenomeInfoDb, AnnotationDbi, Biobase, BiocIO, rtracklayer, biomaRt
- **Install:** `BiocManager::install("txdbmaker")`

## When to Use
- Creating `TxDb` objects from UCSC Genome Browser transcript tables using `makeTxDbFromUCSC`.
- Retrieving and assembling transcript annotations from BioMart datasets using `makeTxDbFromBiomart`.
- Extracting transcript information directly from GFF3 or GTF files using `makeTxDbFromGFF`.
- Saving and loading created `TxDb` objects to/from SQLite database files using `saveDb` and `loadDb` to avoid repeated download times.
- Wrapping a generated database directly into an installable annotation package using `makeTxDbPackageFromUCSC` or `makeTxDbPackageFromBiomart`.

## When NOT to Use
- For extracting features (like transcripts, exons, and CDS) from an already created `TxDb` object, use `GenomicFeatures` instead, which implements the flexible extraction methods.
- For creating `TxDb` objects from unsupported BioMart datasets (not all BioMart datasets are currently supported by `makeTxDbFromBiomart`).

## Data Requirements
- **UCSC**: A valid genome build (e.g., "mm9", "hg19") and a supported transcript table (e.g., "knownGene", "refGene").
- **BioMart**: A supported BioMart dataset name (e.g., "mmusculus_gene_ensembl").
- **Files**: Local GFF3 or GTF files containing transcript annotations.

## Key Parameters
- **genome** (default): Specifies the genome build (e.g., "mm9") when downloading tables from UCSC.
- **tablename** (default): Specifies the specific UCSC transcript table to download (e.g., "knownGene").
- **dataset** (default): Specifies the BioMart dataset to retrieve (e.g., "mmusculus_gene_ensembl").
- **circ_seqs** (default): A vector specifying which sequences are circular; defaults to the contents of `DEFAULT_CIRC_SEQS`.
- **file** (default): The file path used to save or load the SQLite database in `saveDb` and `loadDb`.

## Best Practices
- Use the `supportedUCSCtables` utility function to get a list of tables known to work with `makeTxDbFromUCSC` for your specific genome build.
- Save your annotation objects using `saveDb` and label them with an appropriate time stamp to facilitate reproducible research and avoid bandwidth costs.
- Use the helper function `getChromInfoFromBiomart` to check what the different chromosomes are called for a given BioMart source before building the `TxDb`.

## Common Pitfalls
- Re-downloading and assembling databases from UCSC or BioMart every time a script is run. *Fix*: Use `saveDb` to save the object locally and `loadDb` to initialize it from the `.sqlite` file in future sessions.
- Attempting to serialize a `TxDb` object using R's base `save` function. *Fix*: Use `saveDb` instead, because `TxDb` objects are backed by a SQLite database and cannot be serialized normally.

## Alternatives
- **GenomicFeatures**: The companion package where `TxDb` objects are actually implemented and which provides the methods to extract features from them.
- **AnnotationDbi**: For querying standard Bioconductor annotation packages (e.g., OrgDb) rather than building transcript-centric databases.

## Citations
- Marc Carlson, Patrick Aboyoun, Hervé Pagès, Seth Falcon and Martin Morgan. Making TxDb Objects. Package txdbmaker.

## References
- Homepage: bioconductor.org/packages/txdbmaker
- Vignette: vignette_0_4310e349.txt
