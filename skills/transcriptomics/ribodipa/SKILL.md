---
name: bioconductor-ribodipa
description: This package performs differential pattern analysis for Ribo-seq data. It identifies genes with significantly different patterns in the ribosome footprint between two conditions. RiboDiPA contains five major components including bam file processing, P-site mapping, data binning, differential pattern analysis and footprint visualization.
when_to_use: Use when: RiboDiPA; Differential expression analysis (RiboDiPA); Data normalization and preprocessing (RiboDiPA); Quality control and preprocessing (RiboDiPA). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# RiboDiPA

## Workflows

### Standard Workflow

Run the entire RiboDiPA pipeline using the single wrapper function with default parameters.

```r
library(RiboDiPA)

# Setup class label
classlabel <- data.frame(
  condition = c("mutant", "mutant", "wildtype", "wildtype"),
  comparison = c(2, 2, 1, 1)
)
rownames(classlabel) <- c("mutant1", "mutant2", "wildtype1", "wildtype2")

# Run wrapper
result.wrp <- RiboDiPA(
  bam_path[1:4], 
  bam_path[5], 
  classlabel, 
  cores = 2
)
```
*Note: Inputs are a vector of BAM file paths, a GTF file path, and a class label data frame; the output is a list containing gene-level test results and intermediate data.*

### Step By Step Pipeline

This package performs differential pattern analysis for Ribo-seq data. It identifies genes with sign

**Steps:**
1. Input File Verification and Setup
2. Save Results and Generate Plots

```r
library(RiboDiPA)

# 1. Input File Verification and Setup (P-site mapping & Data binning)
data.psite <- psiteMapping(
  bam_file_list = bam_path[1:4],
  gtf_file = bam_path[5],
  psite.mapping = "auto",
  cores = 2
)

data.binned <- dataBinning(
  data = data.psite$coverage,
  bin.width = 0,
  zero.omit = FALSE,
  bin.from.5UTR = TRUE,
  cores = 2
)

# 2. Save Results and Generate Plots (Differential pattern analysis & Plotting)
result.pst <- diffPatternTest(
  data = data.binned,
  classlabel = classlabel,
  method = c('gtxr', 'qvalue')
)

plotTrack(data = data.psite, genes.list = c("YDR050C"), replicates = NULL, exons = FALSE)
```
*Note: Inputs are BAM files, GTF file, and class label; the output is gene-level and bin-level differential pattern test results and footprint plots.*

### Exon Level Pipeline

Perform differential pattern analysis using annotated exons as the bins for statistical testing.

```r
library(RiboDiPA)

# P-site mapping
data.psite <- psiteMapping(
  bam_file_list = bam_path[1:4],
  gtf_file = bam_path[5],
  psite.mapping = "auto",
  cores = 2
)

# Exon-level binning and testing
result.exon <- diffPatternTestExon(
  psitemap = data.psite,
  classlabel = classlabel,
  method = c('gtxr', 'qvalue')
)
```
*Note: Inputs are P-site mapped data and class label; the output is exon-level differential pattern test results.*

### Exon Level Analysis

This package performs differential pattern analysis for Ribo-seq data. It identifies genes with sign

**Steps:**
1. Retrieve User Input Files from Working Directory
2. Define Experimental Design (Class Label)
3. Save Outputs and Generate Plots

```r
library(RiboDiPA)

# 1. Retrieve User Input Files (P-site mapping)
data.psite <- psiteMapping(
  bam_file_list = bam_path[1:4],
  gtf_file = bam_path[5],
  psite.mapping = "auto",
  cores = 2
)

# 2. Define Experimental Design (Class Label) & Run exon-level test
result.exon <- diffPatternTestExon(
  psitemap = data.psite,
  classlabel = classlabel,
  method = c('gtxr', 'qvalue')
)

# 3. Save Outputs and Generate Plots
plotTest(result = result.exon, genes.list = NULL, threshold = 0.05)
```
*Note: Inputs are P-site mapped data and class label; the output is exon-level differential pattern test results and binned footprint plots.*

## When to Use
- To perform differential pattern analysis of ribosome footprints across different conditions using `RiboDiPA()` or `diffPatternTest()`.
- To map ribosome protected fragments (RPFs) to P-sites using `psiteMapping()`.
- To bin P-site counts adaptively using the Freedman-Diaconis rule or with a fixed width using `dataBinning()`.
- To perform exon-level differential pattern analysis using `diffPatternTestExon()`.
- To visualize ribosome footprints and binned data using `plotTrack()` and `plotTest()`.
- To generate genomic tracks for visualization in genome browsers like `igvR` using `bpTrack()`, `binTrack()`, and `exonTrack()`.

## When NOT to Use
- For standard differential gene expression analysis of RNA-seq or Ribo-seq total abundance; use `DESeq2`, `edgeR`, or `limma` instead.

## Data Requirements
- Ribo-seq alignment files in BAM format (one per sample).
- A Gene Transfer Format (GTF) file for the reference genome of interest (must match the reference used for BAM alignment).
- A class label data frame defining the comparison conditions (with columns `condition` and `comparison`).

## Key Parameters
- **psite.mapping** (`"auto"`): Rule for mapping RPFs to P-sites; can be `"auto"`, `"center"`, or a user-specified matrix of offsets.
- **bin.width** (`0`): Width of bins in codons. `0` indicates adaptive binning.
- **zero.omit** (`FALSE`): If `TRUE`, bins with zero counts across all replicates are omitted from testing.
- **bin.from.5UTR** (`TRUE`): If `TRUE`, binning starts from the 5' end of the total transcript.
- **cores**: Number of CPU cores to use for parallel processing.
- **method** (`c('gtxr', 'qvalue')`): Methods for multiple comparison correction at the bin-level (e.g., `'gtxr'`) and gene-level (e.g., `'qvalue'`).
- **threshold** (`0.05`): Significance threshold for plotting or selecting genes.

## Best Practices
- Ensure the GTF file is identical to the one used to produce the BAM alignments to avoid coordinate mismatches.
- Use adaptive binning (`bin.width = 0`) for sparse Ribo-seq datasets to optimize statistical power.
- Use the supplementary $T$-value statistic (calculated via singular value decomposition) to prioritize significant genes with the largest magnitude of pattern changes.
- Utilize parallel computing by specifying the `cores` parameter to speed up computationally intensive P-site mapping.

## Common Pitfalls
- Coordinate mismatch between BAM and GTF files (e.g., Ensembl vs UCSC). Fix by using the exact same reference genome and annotation source for both alignment and RiboDiPA.
- Insufficient reads mapped to start codons for automatic offset calibration. Fix by using `psite.mapping = "center"` or providing a custom offset matrix.
- Very small last bins when the total transcript length is not an integer multiple of the fixed bin width. Fix by using adaptive binning or letting the package automatically adjust the last two bins.

## Alternatives
- `DESeq2` for standard differential expression analysis of count data.
- `edgeR` for differential expression analysis using empirical Bayes methods.
- `limma` for linear modeling of gene expression data.

## Citations
- Li K., Hope C.M., Wang X.A., Wang J.-P. (2020) “RiboDiPA: A novel tool for differential pattern analysis in Ribo-seq data.” Nucleic Acid Research, 48(21), gkaa1049.

## References
- Homepage: bioconductor.org/packages/ribodipa
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ribodipa/inst/doc/RiboDiPA.html
