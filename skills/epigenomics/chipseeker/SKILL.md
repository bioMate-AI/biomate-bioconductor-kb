---
name: bioconductor-chipseeker
description: ChIPseeker is a Bioconductor package for annotating ChIP-seq data analysis. Peak Annotation is performed by the annotatePeak function. The position and strand information of nearest genes are reported, in addition to the distance from the p
when_to_use: Use when: Annotate ChIP-seq/ATAC-seq peaks to promoters, exons, introns, intergenic regions; Profile read coverage around TSS (transcription start sites); Compare peak sets across experiments; Functional enrichment of annotated peaks
user-invocable: false
---

# ChIPseeker — Comprehensive Skill Guide

> **Domain:** ChIP-seq / ATAC-seq
> **Bioconductor:** [ChIPseeker](https://bioconductor.org/packages/release/bioc/html/ChIPseeker.html)
> **Paper:** Yu G, Wang LG, He QY (2015). Bioinformatics, 31(14):2382-2383.

ChIP-seq peak annotation, comparison, and visualization. Annotates peaks to nearest genomic features, generates coverage and TSS profile plots.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.48.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** AnnotationDbi, aplot, BiocGenerics, boot, dplyr, enrichplot, IRanges, GenomeInfoDb, GenomicRanges, GenomicFeatures, ggplot2, gplots, gtools, magrittr, plotrix, RColorBrewer, rlang, rtracklayer, S4Vectors, scales, tibble, TxDb.Hsapiens.UCSC.hg19.knownGene, yulab.utils
- **Install:** `BiocManager::install("ChIPseeker")`

## When to Use

- Annotate ChIP-seq/ATAC-seq peaks to promoters, exons, introns, intergenic regions
- Profile read coverage around TSS (transcription start sites)
- Compare peak sets across experiments
- Functional enrichment of annotated peaks

**Alternatives:** `HOMER annotatePeaks.pl`, `GREAT (web tool)`, `GenomicFeatures`

## Do NOT Use When

- Differential binding analysis (use DiffBind or csaw).
- Motif analysis (use MEME-ChIP, HOMER, or universalmotif).
- De novo peak calling — peaks must already be called (MACS2, HOMER, etc.).

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | BED/narrowPeak files, or GRanges objects of called peaks |
| **Annotation Db** | TxDb (e.g. TxDb.Hsapiens.UCSC.hg38.knownGene) + OrgDb (org.Hs.eg.db) |
| **Genome Match** | Peak genome assembly must match TxDb genome assembly exactly |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("ChIPseeker")
library(ChIPseeker)
```

## Workflows

### Peak Annotation and Visualization
*Annotate ChIP-seq peaks to genomic features and generate summary plots*

#### Load peaks and annotate

```r
library(ChIPseeker)
library(TxDb.Hsapiens.UCSC.hg38.knownGene)
library(org.Hs.eg.db)

txdb <- TxDb.Hsapiens.UCSC.hg38.knownGene

# Read peak file (BED/narrowPeak)
peak <- readPeakFile("treatment_peaks.narrowPeak", as="GRanges")

# Annotate
peakAnno <- annotatePeak(peak,
                          tssRegion  = c(-3000, 3000),
                          TxDb       = txdb,
                          annoDb     = "org.Hs.eg.db")
head(as.data.frame(peakAnno))
```

#### Visualize annotation distribution

```r
# Pie chart of genomic feature distribution
plotAnnoPie(peakAnno)

# Bar chart
plotAnnoBar(peakAnno)

# Distance to TSS distribution
plotDistToTSS(peakAnno,
              title="Distance of peaks to TSS")
```

#### TSS coverage profile

```r
# Compute tag matrix around TSS
promoter <- getPromoters(TxDb=txdb, upstream=3000, downstream=3000)
tagMatrix <- getTagMatrix(peak, windows=promoter)

# Plot average profile
plotAvgProf(tagMatrix, xlim=c(-3000, 3000),
            xlab="Genomic Region (5'->3')",
            ylab="Read Count Frequency")

# Heatmap of peak enrichment around TSS
tagHeatmap(tagMatrix, xlim=c(-3000, 3000), color="red")
```

#### Pathway enrichment of annotated genes

```r
library(clusterProfiler)
anno_df <- as.data.frame(peakAnno)
gene_ids <- unique(anno_df$geneId)

# GO enrichment
ego <- enrichGO(gene_ids, OrgDb=org.Hs.eg.db,
                ont="BP", pAdjustMethod="BH",
                pvalueCutoff=0.05, qvalueCutoff=0.2)
dotplot(ego)
```

## Key Functions & Parameters

### `annotatePeak()()`

Annotate peaks to genomic features using a TxDb/EnsDb

| Parameter | Description |
|-----------|-------------|
| `peak` | GRanges or path to BED/narrowPeak file |
| `tssRegion` | window around TSS to call 'Promoter' (default c(-3000, 3000)) |
| `TxDb` | transcript database (e.g. TxDb.Hsapiens.UCSC.hg38.knownGene) |
| `annoDb` | OrgDb for symbol annotation (e.g. 'org.Hs.eg.db') |
| `addFlankGeneInfo` | add nearest upstream/downstream gene (default FALSE) |

### `plotAnnoPie() / plotAnnoBar()()`

Pie/bar charts of genomic feature distribution

| Parameter | Description |
|-----------|-------------|
| `x` | csAnno object from annotatePeak() |

### `plotTSSProfile() / plotAvgProf()()`

Average read density profile around TSS

| Parameter | Description |
|-----------|-------------|
| `tagMatrix` | output of getTagMatrix() |
| `xlim` | range around TSS in bp |
| `xlab` | x-axis label |

### `getTagMatrix()()`

Compute read density matrix around TSS or peak center

| Parameter | Description |
|-----------|-------------|
| `peak` | GRanges of peaks |
| `windows` | GRanges of windows to compute matrix over |
| `weightCol` | score column for signal weighting |

### `enrichPathway() / enrichGO()()`

Pathway/GO enrichment on annotated genes (via clusterProfiler)


### `peakHeatmap()()`

Heatmap of read coverage around peak centers across samples


## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Peaks closest to TSS are assumed to regulate the nearest gene (proximity model — not always correct).
- Promoter definition (default ±3kb) is arbitrary; adjust based on your experimental context.

## Result Interpretation

- Annotation pie chart: distribution of peaks in promoters, exons, introns, intergenic regions.
- Promoter peaks: likely direct transcriptional regulation of the nearest gene.
- Intergenic peaks: may be enhancers or regulatory elements; use 3D chromatin data (Hi-C) to link to genes.
- TSS enrichment profile: sharp peak at TSS = good signal-to-noise; flat = poor ChIP efficiency.
- Distance to TSS distribution: narrow distribution near TSS = transcription factor; broad/bimodal = histone mark.

## Best Practices

- Adjust `tssRegion=c(-2000, 2000)` based on typical promoter definition for your organism.
- Use `annoDb` to get gene symbols alongside Entrez IDs in annotations.
- For ATAC-seq, use the same workflow — peaks annotate open chromatin regions.
- Compare multiple peak sets with `compareAnnotation(list(cond1=anno1, cond2=anno2))`.
- Use `vennpeak(peaks_list)` for Venn diagrams of peak overlaps.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `HOMER annotatePeaks.pl` | You prefer command-line tools; you need motif analysis alongside annotation. | You want R/Bioconductor integration with ggplot2 visualizations and clusterProfiler enrichment. |
| `GREAT (web tool)` | You want regulatory domain-based gene assignment (better than proximity for enhancers). | You want local R-based analysis with custom annotation databases. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Yu G et al. (2015). Bioinformatics 31:2382.** [PMID:25759349](https://pubmed.ncbi.nlm.nih.gov/25759349)  
  ChIPseeker provides comprehensive peak annotation and visualization with performance comparable to HOMER's annotatePeaks.

## Common Errors & Troubleshooting

### `Error: TxDb genome does not match peak genome`

**Cause:** Peak file has different genome assembly than TxDb

**Fix:** Use matching TxDb: e.g. `TxDb.Hsapiens.UCSC.hg38.knownGene` for hg38 peaks

## Additional Notes from Official Documentation

*Extracted from the ChIPseeker Bioconductor vignette(s)*

### 2025-11-04


Introduction
ChIP profiling ChIP peaks coverage plot Profile of ChIP peaks binding to TSS regions Heatmap of ChIP binding to TSS regions Average Profile of ChIP peaks binding to TSS region Profile of ChIP peaks binding to different regions Binning method for profile of ChIP peaks binding to TSS regions Profile of ChIP peaks binding to body regions Profile of ChIP peaks binding to TTS regions
ChIP peaks coverage plot
Profile of ChIP peaks binding to TSS regions Heatmap of ChIP binding to TSS regions Average Profile of ChIP peaks binding to TSS region
Heatmap of ChIP binding to TSS regions
Average Profile of ChIP peaks binding to TSS region
Profile of ChIP peaks binding to different regions Binning method for profile of ChIP peaks binding to TSS regions Profile of ChIP peaks binding to body

### Abstract


ChIPseeker is an R package for annotating ChIP-seq data analysis. It supports annotating ChIP peaks and provides functions to visualize ChIP peaks coverage over chromosomes and profiles of peaks binding to TSS regions. Comparison of ChIP peak profiles and annotation are also supported. Moreover, it supports evaluating significant overlap among ChIP-seq datasets. Currently, ChIPseeker contains 17,000 bed file information from GEO database. These datasets can be downloaded and compare with userâs own data to explore significant overlap datasets for inferring co-regulation or transcription factor complex for further investigation.

### Introduction


Chromatin immunoprecipitation followed by high-throughput sequencing (ChIP-seq) has become standard technologies for genome wide identification of DNA-binding protein target sites. After read mappings and peak callings, the peak should be annotated to answer the biological questions. Annotation also create the possibility of integrating expression profile data to predict gene expression regulation. ChIPseeker (Yu, Wang, and He 2015) was developed for annotating nearest genes and genomic features to peaks.
ChIP peak data set comparison is also very important. We can use it as an index to estimate how well biological replications are. Even more important is applying to infer cooperative regulation. If two ChIP seq data, obtained by two different binding proteins, overlap significantly, thes

```r
## loading packages
library(ChIPseeker)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)
txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
library(clusterProfiler)
```

### ChIP profiling


The datasets CBX6 and CBX7 in this vignettes were downloaded from GEO (GSE40740) (Pemberton et al. 2014) while ARmo_0M , ARmo_1nM and ARmo_100nM were downloaded from GEO (GSE48308) (Urbanucci et al. 2012) . ChIPseeker provides readPeakFile to load the peak and store in GRanges object.

```r
files <- getSampleFiles()
print(files)
```

```r
## $ARmo_0M
## [1] "/tmp/RtmpfFjEGs/Rinst37108269af0069/ChIPseeker/extdata/GEO_sample_data/GSM1174480_ARmo_0M_peaks.bed.gz"
## 
## $ARmo_1nM
## [1] "/tmp/RtmpfFjEGs/Rinst37108269af0069/ChIPseeker/extdata/GEO_sample_data/GSM1174481_ARmo_1nM_peaks.bed.gz"
## 
## $ARmo_100nM
## [1] "/tmp/RtmpfFjEGs/Rinst37108269af0069/ChIPseeker/extdata/GEO_sample_data/GSM1174482_ARmo_100nM_peaks.bed.gz"
## 
## $CBX6_BF
## [1] "/tmp/RtmpfFjEGs/Rinst37108269af0069/ChIPseeker/extdata/GEO_sample_data/GSM1295076_CBX6_BF_ChipSeq_mergedReps_peaks.bed.gz"
## 
## $CBX7_BF
## [1] "/tmp/RtmpfFjEGs/Rinst37108269af0069/ChIPseeker/extdata/GEO_sample_data/GSM1295077_CBX7_BF_ChipSeq_mergedReps_peaks.bed.gz"
```

### ChIP peaks coverage plot


After peak calling, we would like to know the peak locations over the whole genome, covplot function calculates the coverage of peak regions over chromosomes and generate a figure to visualize. GRangesList is also supported and can be used to compare coverage of multiple bed files.
When peak is a GRangsList object, user can set the colors directly or by passing a palette to fill_color .

```r
covplot(peak, weightCol="V5")
```

```r
covplot(peak, weightCol="V5", chrs=c("chr17", "chr18"), xlim=c(4.5e7, 5e7))
```

### Profile of ChIP peaks binding to TSS regions


First of all, for calculating the profile of ChIP peaks binding to TSS regions, we should prepare the TSS regions, which are defined as the flanking sequence of the TSS sites. Then align the peaks that are mapping to these regions, and generate the tagMatrix.
In the above code, you should notice that tagMatrix is not restricted to TSS regions. The regions can be other types that defined by the user. ChIPseeker expanded the scope of region. Users can input the type and by parameters to get the regions they want.

```r
## promoter <- getPromoters(TxDb=txdb, upstream=3000, downstream=3000)
## tagMatrix <- getTagMatrix(peak, windows=promoter)
##
## to speed up the compilation of this vignettes, we use a precalculated tagMatrix
data("tagMatrixList")
tagMatrix <- tagMatrixList[[4]]
```

### Heatmap of ChIP binding to TSS regions


Heatmap of ChIP peaks binding to TSS regions
ChIPseeker provide a one step function to generate this figure from bed file. The following function will generate the same figure as above.
Users can use nbin parameter to speed up.
Users can also use ggplot method to change the details of the figures.
Users can also profile genebody regions with peakHeatmap() .
Heatmap of genebody regions
Sometimes there will be a need to explore the comparison of the peak heatmap over two regions, for example, the following picture is the peak over two gene sets. One possible scenery of using this method is to compare the peak heatmap over up-regulating genes and down-regulating genes. Here txdb1 and txdb2 is the simulated gene sets obtain from TxDb.Hsapiens.UCSC.hg19.knownGene . Using peakHeatmap_multiple_S

```r
tagHeatmap(tagMatrix)
```

```r
peakHeatmap(files[[4]], TxDb=txdb, upstream=3000, downstream=3000)
```

### Average Profile of ChIP peaks binding to TSS region


Average Profile of ChIP peaks binding to TSS region
The function plotAvgProf2 provide a one step from bed file to average profile plot. The following command will generate the same figure as shown above.
Confidence interval estimated by bootstrap method is also supported for characterizing ChIP binding profiles.

```r
plotAvgProf(tagMatrix, xlim=c(-3000, 3000),
            xlab="Genomic Region (5'->3')", ylab = "Read Count Frequency")
```

```r
## >> plotting figure...             2025-11-04 16:52:54
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/ChIPseeker.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/ChIPseeker.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Yu G, Wang LG, He QY (2015). Bioinformatics, 31(14):2382-2383.

---
