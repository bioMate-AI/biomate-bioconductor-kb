---
name: bioconductor-rsamtools
description: This package provides an interface to the 'samtools', 'bcftools', and 'tabix' utilities for manipulating SAM (Sequence Alignment / Map), FASTA, binary variant call (BCF) and compressed indexed tab-delimited (tabix) files.
when_to_use: Use when: Low-level Alignment Import: Importing and parsing BAM files directly into R lists or DataFrame objects using scanBam.; Targeted Read Extraction: Extracting specific genomic coordinates and alignment fields (e.g., read sequence, strand, position) using ScanBamParam.; BAM File Management: Managing collections of BAM files and their metadata programmatically using BamViews.; Coverage Calculation: Cal. Not for: For high-level representation of gapped alignments, use GenomicAlignments (specifically readGAlignments) because Rsamtools provides lower-level list-based outputs.; For iterating through BAM files in parallel, use GenomicFiles because it implements h
user-invocable: false
---

# Rsamtools

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 2.28.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** Seqinfo, GenomicRanges, Biostrings
- **Imports:** BiocGenerics, S4Vectors, IRanges, XVector, bitops, BiocParallel
- **System requirements:** GNU make
- **Install:** `BiocManager::install("Rsamtools")`

## When to Use
- **Low-level Alignment Import**: Importing and parsing BAM files directly into R lists or `DataFrame` objects using `scanBam`.
- **Targeted Read Extraction**: Extracting specific genomic coordinates and alignment fields (e.g., read sequence, strand, position) using `ScanBamParam`.
- **BAM File Management**: Managing collections of BAM files and their metadata programmatically using `BamViews`.
- **Coverage Calculation**: Calculating read coverage over specific genomic ranges using `coverage` on imported BAM data.

## When NOT to Use
- For high-level representation of gapped alignments, use `GenomicAlignments` (specifically `readGAlignments`) because `Rsamtools` provides lower-level list-based outputs.
- For iterating through BAM files in parallel, use `GenomicFiles` because it implements higher-level strategies for file iteration.
- For whole-genome manipulation and DNA sequence operations, use `Biostrings` or `BSgenome` instead.

## Data Requirements
- **Input Format**: BAM files (e.g., `.bam`) and their corresponding index files (`.bai`).
- **Genomic Coordinates**: Specified as `GRanges` objects for targeted queries.

## Key Parameters
- **file**: Path to the BAM file to be parsed by `scanBam`.
- **param**: A `ScanBamParam` object determining which genomic coordinates and components to input.
- **which**: A `GRanges` object specifying the genomic ranges to extract.
- **what**: A character vector (e.g., `c("rname", "pos", "qwidth")`) specifying which BAM record fields to retrieve.
- **flag**: A filter created by `scanBamFlag` (e.g., `isUnmappedQuery=FALSE`) to restrict reads.
- **bamRanges**: A `GRanges` object defining the genomic rows for a `BamViews` instance.

## Best Practices
- Always ensure a `.bai` index file is available locally when querying specific ranges with the `which` argument.
- Restrict imported fields using the `what` argument in `ScanBamParam` to minimize memory consumption.
- Process large BAM files in chunks (e.g., by chromosome) using summary functions to avoid memory exhaustion.
- Use `BamViews` to marshal references to multiple BAM files without loading them immediately into memory.

## Common Pitfalls
- **Querying by range without an index**: Fails because providing a `which` argument to `ScanBamParam` requires a BAM index. *Fix*: Ensure the `.bai` file exists or create one using `indexBam`.
- **"EOF marker is absent" warning**: Occurs with some BAM files. *Fix*: This message can safely be ignored as noted in the vignette.
- **Chromosome naming mismatches**: Ensembl vs UCSC naming (e.g., "chr1" vs "1") causes empty queries. *Fix*: Use `seqlevels<-` to map between naming schemes before querying.

## Alternatives
- **GenomicAlignments**: Provides a more useful, higher-level representation of BAM files in R (e.g., `GAlignments` objects).
- **GenomicFiles**: Useful for iterating through BAM and other files, including in parallel.
- **ShortRead**: Better suited for I/O and quality assessment of ungapped short read alignments.

## Citations
- Morgan M, Pagès H, Obenchain V, Hayden N. Rsamtools: Binary alignment (BAM), FASTA, variant call (BCF), and tabix file import. Bioconductor.

## References
- Homepage: https://bioconductor.org/packages/Rsamtools
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Rsamtools/inst/doc/Rsamtools-Overview.pdf
