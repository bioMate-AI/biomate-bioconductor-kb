---
name: bioconductor-genomicalignments
description: Provides efficient containers for storing and manipulating short genomic alignments (typically obtained by aligning short reads to a reference genome). This includes read counting, computing the coverage, junction detection, and working wit
when_to_use: Use when: <Use this package when you have aligned short-read sequencing data (BAM format) and need to perform read counting across genomic features (e.g., for RNA-seq differential expression), compute genomic coverage, or analyze splice junction compatibility and skipped exons.>
user-invocable: false
---

# GenomicAlignments

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.48.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics, S4Vectors, IRanges, Seqinfo, GenomicRanges, SummarizedExperiment, Biostrings, Rsamtools
- **Imports:** BiocGenerics, S4Vectors, IRanges, GenomicRanges, Biostrings, Rsamtools, BiocParallel, cigarillo
- **Install:** `BiocManager::install("GenomicAlignments")`

## When to Use

- Counting aligned reads overlapping genomic features (e.g., exons, genes) for differential expression analysis using `summarizeOverlaps`.
- Loading and manipulating paired-end alignments from BAM files using `readGAlignmentPairs`.
- Analyzing splice junctions, insertions, and deletions in RNA-seq reads using the `njunc`, `cigar`, and `cigarOpTable` functions.
- Filtering alignments based on mapping quality, duplicates, or specific genomic regions using `ScanBamParam` and `scanBamFlag`.

## When NOT to Use

- For ultra-fast, memory-efficient read counting on massive datasets, use `Rsubread::featureCounts` because it is written in C and optimized for speed.
- For low-level BAM file indexing or header manipulation without loading alignments, use `Rsamtools` because it provides direct wrappers to samtools functionality.

## Data Requirements

- **Input Format**: Sorted and indexed BAM files.
- **Features**: Genomic features provided as `GRanges` or `GRangesList` objects for overlap counting.
- **Structure**: Alignments are loaded into `GAlignments` (single-end) or `GAlignmentPairs` (paired-end) objects.

## Key Parameters

- **`<use.names`**: TRUE
- **`in readGAlignments/readGAlignmentPairs, loads query template names (QNAME) from the BAM file to name the returned object.
  param`**: ScanBamParam(...)
- **`filters reads (e.g., by flags, duplicates, or quality controls) and specifies fields to load (like "seq" for read sequences).
  mode`**: "Union"
- **`in summarizeOverlaps, determines the overlap resolution mode (alternatives include "IntersectionStrict" and "IntersectionNotEmpty").
  ignore.strand`**: TRUE
- **`in findOverlaps, controls whether strand information is ignored when finding overlaps between alignments and genomic features.
  flip.query.if.wrong.strand`**: TRUE
- in encodeOverlaps, automatically handles strand-specific overlap encoding when query and subject strands differ.>

## Workflow Variants

### Read Counting Summarize Overlaps

**Intent**: Count aligned reads overlapping genomic features to prepare a count matrix for differential expression analysis.

**Inputs**:
- `fls (character vector of paths to BAM files)`
- `features (GRanges or GRangesList object representing genomic features like exons or genes)`

**Steps**:
1. Define paths to BAM files and genomic features.
2. Run summarizeOverlaps to count reads overlapping features.
3. Coerce the resulting SummarizedExperiment object into DESeq2 or edgeR datasets for downstream differential analysis.

```r
library(GenomicAlignments)
library(DESeq2)
library(edgeR)

fls <- list.files(system.file("extdata", package="GenomicAlignments"),
    recursive=TRUE, pattern="*bam$", full=TRUE)

features <- GRanges(
    seqnames = c(rep("chr2L", 4), rep("chr2R", 5), rep("chr3L", 2)),
    ranges = IRanges(c(1000, 3000, 4000, 7000, 2000, 3000, 3600, 4000, 
        7500, 5000, 5400), width=c(rep(500, 3), 600, 900, 500, 300, 900, 
        300, 500, 500)), "-",
    group_id=c(rep("A", 4), rep("B", 5), rep("C", 2)))

olap <- summarizeOverlaps(features, fls)
deseq <- DESeqDataSet(olap, design= ~ 1)
edger <- DGEList(assay(olap), group=rownames(colData(olap)))
```


---

### Splice Junction Overlap Encoding

**Intent**: Analyze aligned reads to determine their compatibility with known transcript splice junctions and identify skipped exons.

**Inputs**:
- `untreated3_chr4() (path to a BAM file)`
- `TxDb.Dmelanogaster.UCSC.dm3.ensGene (a transcript database object)`

**Steps**:
1. Load paired-end alignments from a BAM file using readGAlignmentPairs.
2. Filter for proper alignment pairs using isProperPair.
3. Extract exons grouped by transcript from the transcript database.
4. Find overlaps between alignments and transcripts using findOverlaps.
5. Generate overlap encodings using encodeOverlaps.
6. Identify and extract splice-compatible overlaps or skipped exon ranks.

```r
library(pasillaBamSubset)
library(GenomicAlignments)
flag0 <- scanBamFlag(isDuplicate=FALSE, isNotPassingQualityControls=FALSE)
param0 <- ScanBamParam(flag=flag0)
U3.galp <- readGAlignmentPairs(untreated3_chr4(), use.names=TRUE, param=param0)
U3.GALP <- U3.galp[isProperPair(U3.galp)]
library(TxDb.Dmelanogaster.UCSC.dm3.ensGene)
txdb <- TxDb.Dmelanogaster.UCSC.dm3.ensGene
exbytx <- exonsBy(txdb, by="tx", use.names=TRUE)
U3.OV00 <- findOverlaps(U3.GALP, exbytx, ignore.strand=TRUE)
U3.grl <- grglist(U3.GALP)
U3.ovenc <- encodeOverlaps(U3.grl, exbytx, hits=U3.OV00, flip.query.if.wrong.strand=TRUE)
U3.unique_encodings <- levels(U3.ovenc)
U3.ovenc_table <- table(encoding(U3.ovenc))
sort(U3.ovenc_table[isCompatibleWithSplicing(U3.unique_encodings)])
U3.OV00_is_comp <- isCompatibleWithSplicing(U3.ovenc)
U3.compOV00 <- U3.OV00[U3.OV00_is_comp]
```


## Best Practices

- Use `ScanBamParam` with `scanBamFlag` to filter out PCR duplicates and reads failing quality controls before loading alignments into memory.
- When working with paired-end data, use `readGAlignmentPairs` and filter for proper pairs using `isProperPair` to ensure high-quality alignments.
- Use `summarizeOverlaps` with a `GRangesList` (e.g., exons grouped by transcript or gene) to correctly count reads spanning multiple exons of the same feature.

## Common Pitfalls

- <cigarOpTable() is formally deprecated in GenomicAlignments >= 1.45.5 and should be replaced with tabulate_cigar_ops() from the cigarillo package.
  The BAM format reverse-complements read sequences when they align to the minus strand; you must manually reverse-complement them again to restore the original query sequences.
  Query names (QNAMEs) are not guaranteed to be unique if the aligner reports multiple alignments per read.
  The criteria for setting the "proper pair" flag (isProperPair) is determined entirely by the aligner used, not by GenomicAlignments.>

## Alternatives

- <VariantTools or VariantAnnotation
- use these packages for a complete variant calling and annotation toolbox, as GenomicAlignments only provides low- to mid-level nucleotide tools.
  cigarillo::tabulate_cigar_ops()
- use this function instead of the formally deprecated GenomicAlignments::cigarOpTable() to summarize CIGAR operations.>

## Citations

- Lawrence, M., Huber, W., Pagès, H., Aboyoun, P., Carlson, M., Gentleman, R., ... & Carey, V. J. (2013). Software for computing and annotating genomic ranges. *PLoS Computational Biology*, 9(8), e1003118.

## References

- Homepage: https://bioconductor.org/packages/GenomicAlignments
- Vignette: vignette_0_5516405c.txt
