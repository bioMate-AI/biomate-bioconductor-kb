---
name: bioconductor-epialleler
description: Epialleles are specific DNA methylation patterns that are mitotically and/or meiotically inherited. This package calls and reports cytosine methylation as well as frequencies of hypermethylated epialleles at the level of genomic regions or individual cytosines in next-generation sequencing data using binary alignment map (BAM) files as an input. Among other things, this package can also extract and visualise methylation patterns and assess allele specificity of methylation.
when_to_use: Use when: Epialleles are specific DNA methylation patterns that are mitotically and/or meiotically inherited. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# epialleler

## Workflows

### Standard Workflow

```r
library(epialleler)
capture.bam <- system.file("extdata", "capture.bam", package="epialleler")
capture.bed <- system.file("extdata", "capture.bed", package="epialleler")
bam.data <- preprocessBam(capture.bam, targets=capture.bed)
cg.vef.report <- generateCytosineReport(bam.data)
```
*Note*: Inputs are a short-read BAM file and a target BED file; output is a data.table containing the cytosine VEF report.

### Long Read Methylation Analysis

```r
library(epialleler)
longread.bam <- system.file("extdata", "longread.bam", package="epialleler")
longread.data <- preprocessBam(longread.bam, min.mapq=30, min.baseq=20, min.prob=178)
cg.report <- generateCytosineReport(longread.data, threshold.reads=FALSE)
```
*Note*: Input is a long-read BAM file; output is a conventional cytosine report.

### Methylation Bimodality Ecdf

```r
library(epialleler)
# Assess potential bimodality of methylation for genomic regions of interest
# generateBedEcdf(bam, bed)
```
*Note*: Inputs are a BAM file and a BED file of genomic regions; output is an assessment of methylation bimodality.

### Methylation Calling Unannotated Bams

```r
library(epialleler)
input.bam <- system.file("extdata", "test", "bwameth-se-unsort-yd.bam", package="epialleler")
output.bam <- tempfile(pattern="output-", fileext=".bam")
genome <- preprocessGenome(system.file("extdata", "test", "reference.fasta.gz", package="epialleler"))
callMethylation(input.bam, output.bam, genome)
```
*Note*: Inputs are an unannotated BAM file and a preprocessed reference genome; output is a new BAM file containing XG/XM tags.

### Sequence Variant Association

```r
library(epialleler)
# Test the association of methylation with single-nucleotide variations within epialleles
# generateVcfReport(bam, vcf)
```
*Note*: Inputs are a BAM file and a VCF file; output is a VCF report testing SNV-epiallele association.

### Long Read Methylation Reporting

```r
library(epialleler)
longread.bam <- system.file("extdata", "longread.bam", package="epialleler")
longread.data <- preprocessBam(longread.bam, min.mapq=30, min.baseq=20, min.prob=178)
cg.report <- generateCytosineReport(longread.data, threshold.reads=FALSE)
```
*Note*: Input is a long-read BAM file; output is a conventional cytosine report.

### Methylation Pattern And Ecdf Visualization

```r
library(epialleler)
# Explore DNA methylation patterns of genomic regions of interest
# patterns <- extractPatterns(bam, bed)
# plotPatterns(patterns)
```
*Note*: Inputs are a BAM file and a BED file; output is a visualization of methylation patterns.

### Short Read Methylation Calling

```r
library(epialleler)
input.bam <- system.file("extdata", "test", "bwameth-se-unsort-yd.bam", package="epialleler")
output.bam <- tempfile(pattern="output-", fileext=".bam")
genome <- preprocessGenome(system.file("extdata", "test", "reference.fasta.gz", package="epialleler"))
callMethylation(input.bam, output.bam, genome)
```
*Note*: Inputs are an unannotated BAM file and a preprocessed reference genome; output is a new BAM file containing XG/XM tags.

### Snv Epiallele Association

```r
library(epialleler)
# Test the association of methylation with single-nucleotide variations within epialleles
# generateVcfReport(bam, vcf)
```
*Note*: Inputs are a BAM file and a VCF file; output is a VCF report testing SNV-epiallele association.

## When to Use
- To call and report cytosine methylation levels (beta values) and variant epiallele frequencies (VEF) of hypermethylated alleles from BAM files.
- To analyze DNA methylation patterns at the level of individual cytosines (`generateCytosineReport`) or genomic regions (`generateBedReport`, `generateAmpliconReport`, `generateCaptureReport`).
- To call methylation on unannotated short-read BAM files lacking XG/XM tags using `callMethylation` and a preprocessed reference genome (`preprocessGenome`).

## When NOT to Use
- For long-read sequencing where thresholding is not recommended; use `generateMhlReport` to calculate Linearised Methylated Haplotype Load (lMHL) instead of VEF.
- For multi-threaded BAM reading/writing if HTSlib is not configured; though `nthreads` can speed up decompression.

## Data Requirements
- **BAM files**: Short-read BAMs must contain XG and XM tags (or be processed with `callMethylation`). Long-read BAMs must contain MM and ML tags.
- **BED files**: Genomic coordinates for targeted regions (amplicon or capture).
- **FASTA files**: Reference genome sequence (only required for short-read methylation calling via `preprocessGenome`).

## Key Parameters
- **bam**: Path to the input BAM file or preprocessed BAM data.
- **threshold.reads** (TRUE): Whether to produce a thresholded (VEF) report. Set to `FALSE` for conventional cytosine reports.
- **filter.reads** (TRUE): Whether to drop reads with too few in-context cytosines or high out-of-context methylation.
- **min.mapq** (0): Minimum mapping quality threshold for reads.
- **min.baseq** (0): Minimum base quality threshold.
- **min.prob** (0): Minimum probability threshold for long-read modifications.
- **nthreads** (1): Number of decompression threads to speed up BAM/FASTA reading.

## Best Practices
- Preprocess large BAM files once using `preprocessBam` and pass the resulting object to downstream reporting functions to save time.
- For paired-end short-read data, ensure the BAM file is sorted by QNAME (unsorted) so that `preprocessBam` can merge overlapping read pairs correctly.
- Keep `filter.reads=TRUE` for short-read bisulfite or enzymatic sequencing to remove reads from incompletely converted DNA molecules.

## Common Pitfalls
- Running `preprocessBam` on a location-sorted paired-end BAM: Sort by QNAME first using `samtools sort -n`.
- Missing XG/XM tags in short-read BAMs: Run `callMethylation` with a preprocessed reference genome first.

## Alternatives
- `Bismark` or `Modkit` for general methylation extraction.

## References
- Homepage: bioconductor.org/packages/epialleler
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/epialleler/inst/doc/epialleler.html
