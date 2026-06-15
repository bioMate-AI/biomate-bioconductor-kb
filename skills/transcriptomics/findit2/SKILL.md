---
name: bioconductor-findit2
description: This package implements functions to find influential TF and target based on different input type. It have five module: Multi-peak multi-gene annotaion(mmPeakAnno module), Calculate regulation potential(calcRP module), Find influential Target based on ChIP-Seq and RNA-Seq data(Find influential Target module), Find influential TF based on different input(Find influential TF module), Calculate peak-gene or peak-peak correlation(peakGeneCor module). And there are also some other useful function lik
when_to_use: Use when: Introduction to FindIT2; ChIP-seq peak analysis (FindIT2); ATAC-seq chromatin accessibility (FindIT2). Not for: Requires R ≥ 3.5.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# FindIT2

## Workflows

### Standard Workflow

Annotate ChIP-seq or ATAC-seq peaks to nearest genes and calculate gene-level regulatory potential (RP) based on peak distance to transcription start sites (TSS).

```r
library(FindIT2)
library(TxDb.Athaliana.BioMart.plantsmart28)

# 1. Load peak file and TxDb annotation
Txdb <- TxDb.Athaliana.BioMart.plantsmart28
seqlevels(Txdb) <- c(paste0("Chr", 1:5), "M", "C")
ChIP_peak_path <- system.file("extdata", "ChIP.bed.gz", package = "FindIT2")
ChIP_peak_GR <- loadPeakFile(ChIP_peak_path)

# 2. Annotate peaks using nearest gene mode
mmAnno_nearestgene <- mm_nearestGene(peak_GR = ChIP_peak_GR, Txdb = Txdb)

# 3. Find related peaks using gene scan mode
mmAnno_geneScan <- mm_geneScan(peak_GR = ChIP_peak_GR, Txdb = Txdb, upstream = 2e4, downstream = 2e4)

# 4. Calculate regulatory potential (RP)
fullRP_hit <- calcRP_TFHit(mmAnno = mmAnno_geneScan, Txdb = Txdb, decay_dist = 1000, report_fullInfo = TRUE)
```
Input: A peak BED file path and a TxDb object. Output: A GRanges object containing annotated peaks and calculated regulatory potentials.

## When to Use
- Annotating ChIP-seq or ATAC-seq peaks to nearest genes using `mm_nearestGene()`.
- Finding all peaks within a specific genomic window around the TSS of genes using `mm_geneScan()`.
- Calculating gene-level regulatory potential (RP) from peak-level data using `calcRP_TFHit()` or from bigwig coverage files using `calcRP_coverage()`.
- Identifying influential transcription factors and target genes by integrating multi-omics data.

## When NOT to Use
- For differential binding analysis of ChIP-seq data, use `DiffBind` because `FindIT2` focuses on peak-to-gene annotation and regulatory potential calculation.
- For standard peak calling from raw FASTQ/BAM files, use `MACS2` because `FindIT2` requires pre-called peak files (e.g., BED format).

## Data Requirements
- Peak files in BED format, loaded into a GRanges object using `loadPeakFile()`.
- A `TxDb` object containing genomic coordinates and gene models (e.g., `TxDb.Athaliana.BioMart.plantsmart28`).
- The GRanges object must contain a metadata column named `feature_id` representing peak names.

## Key Parameters
- **peak_GR**: A GRanges object representing genomic peaks.
- **Txdb**: A TxDb object for genomic annotations.
- **upstream** (2e4): Upstream distance from TSS for gene scan mode.
- **downstream** (2e4): Downstream distance from TSS for gene scan mode.
- **decay_dist** (1000): Half-decay distance controlling the weight of peaks based on distance to TSS.
- **report_fullInfo** (TRUE): Logical indicating whether to return full GRanges annotation details.

## Best Practices
- Ensure the chromosome naming style (seqlevels) of the peak GRanges object matches the TxDb object exactly using `seqlevels()`.
- Use `plot_annoDistance()` to inspect the distribution of peak distances to TSS to determine if the TF is promoter-type or enhancer-type.
- Set `decay_dist` to 1000 for promoter-type TFs and 10,000 (10 kb) for enhancer-type TFs when calculating regulatory potential.

## Common Pitfalls
- *Mismatched Chromosome Names*: If seqlevels do not match between peak GRanges and TxDb, annotations will fail; fix by aligning seqlevels using `seqlevels(Txdb) <- ...`.
- *Missing feature_id Column*: FindIT2 functions rely on `feature_id` to link peaks; fix by loading peaks with `loadPeakFile()` or manually assigning `yourGR$feature_id <- ...`.
- *Excessive Gene Scan Window*: Setting upstream/downstream parameters too large on high-density genomes can make results messy; fix by using `mm_nearestGene()` or reducing the scan window.

## Alternatives
- `ChIPseeker` for general ChIP-seq peak annotation and visualization.
- `DiffBind` for quantitative differential binding analysis.

## Citations
- Guandong Shang, Zhougeng Xu, Muchun Wan, Fuxiang Wang, Jiawei Wang (2022). FindIT2: an R/Bioconductor package to identify influential transcription factor and targets based on multi-omics data. BMC Genomics, 23, 272.

## References
- Homepage: bioconductor.org/packages/FindIT2
- Vignette: bioconductor.org/packages/release/bioc/vignettes/FindIT2/inst/doc/FindIT2.html
