---
name: bioconductor-rtracklayer
description: Extensible framework for interacting with multiple genome browsers (currently UCSC built-in) and manipulating annotation tracks in various formats (currently GFF, BED, bedGraph, BED15, WIG, BigWig and 2bit built-in). The user may export/imp
when_to_use: Use when: Genomic Track Import/Export: Importing and exporting genomic annotation tracks (e.g., BED, GFF, WIG) into R as GRanges objects using import and export.; UCSC Genome Browser Interaction: Interacting programmatically with the UCSC genome browser via browserSession.; Custom Track Uploads: Uploading custom annotation tracks to a genome browser using the track<- function.; UCSC Table Queries: Querying . Not for: For core manipulation of genomic intervals without file I/O, use GenomicRanges instead.; For parsing raw sequencing alignments, use GenomicAlignments or Rsamtools instead, as rtracklayer is designed for annotation tracks.
user-invocable: false
---

# rtracklayer

## When to Use
- **Genomic Track Import/Export**: Importing and exporting genomic annotation tracks (e.g., BED, GFF, WIG) into R as `GRanges` objects using `import` and `export`.
- **UCSC Genome Browser Interaction**: Interacting programmatically with the UCSC genome browser via `browserSession`.
- **Custom Track Uploads**: Uploading custom annotation tracks to a genome browser using the `track<-` function.
- **UCSC Table Queries**: Querying and downloading built-in UCSC tracks (like RepeatMasker) using `ucscTableQuery` and `getTable`.

## When NOT to Use
- For core manipulation of genomic intervals without file I/O, use `GenomicRanges` instead.
- For parsing raw sequencing alignments, use `GenomicAlignments` or `Rsamtools` instead, as `rtracklayer` is designed for annotation tracks.

## Data Requirements
- **Input Formats**: BED, GFF (v1/2/3), WIG, and other browser-supported formats.
- **R Representation**: Genomic coordinates must be 1-based when represented as `GRanges` in R.
- **Genome Build**: Valid genome build identifiers (e.g., "hg18", "hg19") for UCSC integration.

## Key Parameters
- **format**: Explicitly specifies the file format (e.g., "bed", "gff1") for `import` or `export`.
- **name**: Character vector identifying the track within a `browserSession`.
- **range**: A `GRanges` object specifying the genomic segment to view or download.
- **pack**: Instructs the browser to use the "pack" mode for viewing a track.
- **track**: Specifies the name of the track to query in `ucscTableQuery`.
- **table**: Specifies the specific table within a track to retrieve via `ucscTableQuery`.

## Best Practices
- Use `GRangesForUCSCGenome` to formally associate interval data with a UCSC genome build and validate bounds before uploading.
- Subset large `GRanges` tracks before uploading or viewing (e.g., `targetTrack[1:10]`) to avoid overwhelming the browser session.
- Rely on the default "auto" format detection in `export` and `import` which derives the format from the file extension.

## Common Pitfalls
- **Coordinate System Confusion**: R and `GRanges` use 1-based coordinates, while formats like BED use 0-based. *Fix*: `rtracklayer` handles this automatically during `import`/`export`, so avoid manual coordinate shifting.
- **Opening too many browser tabs**: Changing the view state in UCSC opens a new page in the web browser. *Fix*: Consolidate view adjustments or use `browseGenome` to load tracks and set the view in a single call.

## Alternatives
- **GenomicRanges**: For in-memory manipulation of genomic intervals without external browser interaction.
- **BSgenome**: For retrieving and manipulating full genome sequences rather than annotation tracks.

## Citations
- Lawrence M, et al. (2009) "Software for Computing and Annotating Genomic Ranges." PLoS Computational Biology.
- Lawrence M, et al. (2007) "rtracklayer: an R package for interfacing with genome browsers." Bioinformatics.

## References
- Homepage: https://bioconductor.org/packages/rtracklayer
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/rtracklayer/inst/doc/rtracklayer.pdf
