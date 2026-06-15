---
name: bioconductor-cellbarcode
description: The package CellBarcode performs Cellular DNA Barcode analysis. It can handle all kinds of DNA barcodes, as long as the barcode is within a single sequencing read and has a pattern that can be matched by a regular expression. \code{CellBarcode} can handle barcodes with flexible lengths, with or without UMI (unique molecular identifier). This tool also can be used for pre-processing some amplicon data such as CRISPR gRNA screening, immune repertoire sequencing, and metagenome data.
when_to_use: Use when: 10X_Barcode; UMI_Barcode; Quality control and preprocessing (CellBarcode). Not for: Requires R ≥ 4.1.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# CellBarcode

## Workflows

### Standard Workflow

Perform quality control, filter, extract, cure, and quantify lineage barcodes and UMIs from raw FASTQ files.

```r
library(CellBarcode)

# 1. Load User Inputs
example_data <- system.file("extdata", "mef_test_data", package = "CellBarcode")
fq_files <- dir(example_data, "fastq.gz", full=TRUE)
sample_name <- paste0("sample_", seq_along(fq_files))

# 2. Quality Control
qc_noFilter <- bc_seq_qc(fq_files)
bc_plot_seqQc(qc_noFilter)

# 3. Filtering
fq_filter <- bc_seq_filter(fq_files, min_average_quality = 30, min_read_length = 60, sample_name = sample_name)

# 4. Extraction
pattern <- "([ACGT]{12})CTCGAGGTCATCGAAGTATC([ACGT]+)CCGTAGCAAGCTCGAGAGTAGACCTACT"
bc_obj <- bc_extract(fq_filter, pattern = pattern, pattern_type = c("UMI" = 1, "barcode" = 2), sample_name = sample_name)

# 5. Curing and Quantification
bc_sub <- bc_cure_umi(bc_obj, depth = 2)
bc_sub <- bc_cure_depth(bc_sub, depth = 2)

# 6. Export
df_counts <- bc_2df(bc_sub)
mat_counts <- bc_2matrix(bc_sub)
```
*Inputs/Outputs:* Takes raw FASTQ files and a regular expression pattern as inputs, and outputs a `BarcodeObj` containing cleaned barcode and UMI counts, exportable to a data frame (`bc_2df`) or matrix (`bc_2matrix`).

### Scrnaseq Sam Lineage Barcoding

Extract lineage barcodes, cell barcodes, and UMIs from 10X Genomics single-cell RNA-seq SAM files.

```r
library(CellBarcode)

# 1. Load User Inputs
sam_file <- system.file("extdata", "scRNASeq_10X.sam", package = "CellBarcode")

# 2. Extract Lineage Barcode
d <- bc_extract_sc_sam(
  sam = sam_file,
  pattern = "AGATCAG(.*)TGTGGTA",
  cell_barcode_tag = "CR",
  umi_tag = "UR"
)
```
*Inputs/Outputs:* Takes a SAM file derived from 10X Genomics CellRanger output and a regular expression pattern as inputs, and outputs a data frame containing `cell_barcode`, `umi`, `barcode_seq`, and `count`.

## When to Use
- To perform cellular DNA barcode analysis and lineage tracing from raw FASTQ files using `bc_extract`.
- To extract lineage barcodes, cell barcodes, and UMIs from single-cell RNA-seq SAM/BAM files using `bc_extract_sc_sam`.
- To filter sequences by quality and length using `bc_seq_filter` and perform quality control visualization using `bc_plot_seqQc`.
- To perform error correction on barcodes and UMIs using `bc_cure_umi` and `bc_cure_depth`.

## When NOT to Use
- For standard transcriptomic alignment or gene expression quantification (use `Rsubread` or `Salmon` instead).
- For single-cell RNA-seq clustering and cell-type annotation (use `Seurat` or `scran` instead).

## Data Requirements
- Raw sequencing data in FASTQ format, or aligned single-cell RNA-seq data in SAM/BAM format (from CellRanger).
- A regular expression pattern defining the constant regions and the variable barcode/UMI regions (e.g., `"([ACGT]{12})CTCGAGGTCATCGAAGTATC([ACGT]+)CCGTAGCAAGCTCGAGAGTAGACCTACT"`).

## Key Parameters
- **pattern**: A regular expression matching the barcode structure, with brackets `()` capturing the target sequences.
- **pattern_type**: A named vector (e.g., `c("UMI" = 1, "barcode" = 2)`) mapping captured groups to sequence types.
- **min_average_quality** (30): Minimum average base quality across a read in `bc_seq_filter`.
- **min_read_length** (60): Minimum read length in bases in `bc_seq_filter`.
- **depth** (2): Minimum read/UMI depth threshold for filtering in `bc_cure_umi` and `bc_cure_depth`.
- **cell_barcode_tag** ("CR"): The SAM file tag for 10X cell barcodes in `bc_extract_sc_sam`.
- **umi_tag** ("UR"): The SAM file tag for 10X UMIs in `bc_extract_sc_sam`.

## Best Practices
- Run `bc_seq_qc` and `bc_plot_seqQc` before extraction to identify constant and random regions of the sequencing reads.
- Filter low-quality reads using `bc_seq_filter` to reduce noise and false-positive barcodes.
- Apply `bc_cure_umi` followed by `bc_cure_depth` to perform sequence error correction and remove low-abundance barcode artifacts.

## Common Pitfalls
- Incorrect regular expression pattern resulting in zero extracted barcodes. Fix: Verify the constant flanking sequences using `bc_plot_seqQc` base ratio plots.
- High memory usage with large SAM/BAM files. Fix: Pre-filter the BAM file to include only unmapped reads (e.g., using `samtools view -f 4`) before running `bc_extract_sc_sam`.

## Alternatives
- `ShortRead` for general FASTQ manipulation and quality control without specialized barcode/UMI extraction.
- `scuttle` for single-cell preprocessing and QC without lineage barcode extraction.

## Citations
- Sun W, Lyne AM (2024). CellBarcode: an R/Bioconductor package for cellular DNA barcode analysis. Nature Computational Science.

## References
- Homepage: bioconductor.org/packages/cellbarcode
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cellbarcode/inst/doc/CellBarcode.html
