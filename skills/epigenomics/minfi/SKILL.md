---
name: bioconductor-minfi
description: Tools to analyze & visualize Illumina Infinium methylation arrays.
when_to_use: Use when: Import and QC of 450K/EPIC array data; Normalisation (SWAN, Noob, Funnorm); Differential methylation at individual CpGs (dmpFinder); Differentially Methylated Regions (DMRs); Cell-type deconvolution from whole blood
user-invocable: false
---

# minfi — Comprehensive Skill Guide

> **Domain:** DNA Methylation
> **Bioconductor:** [minfi](https://bioconductor.org/packages/release/bioc/html/minfi.html)
> **Paper:** Aryee MJ et al. (2014). Bioinformatics, 30:1363-1369.

Analysis of Illumina Infinium DNA methylation arrays (450K, EPIC). Handles import, QC, normalisation, and differential methylation.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.58.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics, GenomicRanges, SummarizedExperiment, Biostrings, bumphunter
- **Imports:** S4Vectors, Seqinfo, Biobase, IRanges, beanplot, RColorBrewer, lattice, nor1mix, siggenes, limma, preprocessCore, illuminaio, DelayedMatrixStats, mclust, genefilter, nlme, reshape, MASS, quadprog, data.table, GEOquery, DelayedArray, HDF5Array, BiocParallel
- **Install:** `BiocManager::install("minfi")`

## When to Use

- Import and QC of 450K/EPIC array data
- Normalisation (SWAN, Noob, Funnorm)
- Differential methylation at individual CpGs (dmpFinder)
- Differentially Methylated Regions (DMRs)
- Cell-type deconvolution from whole blood

**Alternatives:** `methylKit`, `DMRcate`, `ChAMP`

## Do NOT Use When

- Whole-genome bisulfite sequencing (WGBS) — use methylKit or DSS instead.
- RRBS data without special handling — minfi is optimized for Illumina EPIC/450K arrays.
- Non-CpG methylation — minfi focuses on CpG context.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | Illumina EPIC (850K) or 450K array IDAT files; or GEO/downloaded IDAT |
| **Min Samples** | ≥3 per group for meaningful differential analysis |
| **Notes** | Array type (450K vs EPIC) must be consistent within a study |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("minfi")
library(minfi)
```

## Workflows

### EPIC / 450K Array Methylation Analysis
*Full pipeline: IDAT → preprocessing → normalization → differential methylation*

#### Read IDAT files

```r
library(minfi)
targets <- read.metharray.sheet("data/", pattern="SampleSheet.csv")
RGSet   <- read.metharray.exp(targets=targets, extended=TRUE)
RGSet
```

#### Quality control

```r
# Sample-level QC
qc <- getQC(preprocessRaw(RGSet))
plotQC(qc)                              # flag samples with low quality

# Detection p-value filtering
detP <- detectionP(RGSet)
failed <- detP > 0.01                   # positions with detection p > 0.01
sum(failed) / prod(dim(failed))         # fraction failed
```

#### Normalize and extract beta values

```r
# Functional normalization (recommended for large studies)
MSet.norm <- preprocessFunnorm(RGSet)

# Or Noob (recommended for small studies)
MSet.norm <- preprocessNoob(RGSet)

beta  <- getBeta(MSet.norm)             # 0–1 methylation fraction
mvals <- getM(MSet.norm)               # M-values for linear modelling
```

#### Differential methylation with limma

```r
library(limma)
pheno  <- pData(MSet.norm)
design <- model.matrix(~0 + pheno$Sample_Group)
fit    <- lmFit(mvals, design)
contr  <- makeContrasts(TumorVsNormal = Tumor - Normal, levels=design)
fit2   <- eBayes(contrasts.fit(fit, contr))
top    <- topTable(fit2, coef=1, n=Inf, adjust.method="BH")
sig    <- top[top$adj.P.Val < 0.05,]
```


## Key Functions & Parameters

### `read.metharray.exp()`

Import raw IDAT files into RGChannelSet

| Parameter | Description |
|-----------|-------------|
| `targets` | data.frame from read.metharray.sheet() with Basename column |
| `extended` | logical: include extended manifest info |
| `force` | logical: allow different array types in one object |

### `preprocessNoob()`

Noob background subtraction + dye bias correction (recommended default)

| Parameter | Description |
|-----------|-------------|
| `rgSet` | RGChannelSet |
| `offset` | offset added to all intensities (default 15) |
| `dyeCorr` | logical: dye correction (default TRUE) |
| `dyeMethod` | 'single' (default) \| 'reference' |

### `preprocessFunnorm()`

Functional normalisation using control probes (recommended for large studies)

| Parameter | Description |
|-----------|-------------|
| `RGSet` | RGChannelSet |
| `nPCs` | number of control PCs to use (default 2) |
| `sex` | character vector 'M'/'F' (improves X/Y probe handling) |
| `bgCorr` | logical: background correction (default TRUE) |

### `dmpFinder()`

Find differentially methylated positions

| Parameter | Description |
|-----------|-------------|
| `dat` | M-value matrix (genes × samples) |
| `pheno` | phenotype vector |
| `type` | 'categorical' \| 'continuous' |
| `qCutoff` | FDR cutoff (default 1; filter post-hoc) |
| `formula` | optional: include covariates ~ pheno + covariate |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Beta values follow a bimodal distribution (0 = unmethylated, 1 = methylated).
- Technical variability is captured by normalization (Noob, SWAN, Quantile, Funnorm).
- Cell-type composition differences are a major confounder in blood-based studies.

## Result Interpretation

- Beta value: proportion methylated (0–1); use for visualization and biological interpretation.
- M-value (logit of beta): use for statistical modelling — more homoscedastic than beta.
- DMP: differentially methylated position; report as Δβ > 0.1 (10% methylation change) AND FDR < 0.05.
- DMR: differentially methylated region; use bumphunter or DMRcate for robust DMR detection.
- Negative control probes: use to assess batch effects and technical variability between samples.

## Best Practices

- Always use M-values (logit-transformed beta values) for statistical modelling; use beta values for visualisation.
- Remove probes: (1) failed detection p>0.01, (2) SNP-overlapping, (3) cross-reactive probes.
- Use `getSex(estimateSex(mSetSq))` to verify reported sex against predicted sex from array.
- For large studies use `preprocessFunnorm`; for small studies use `preprocessQuantile` or `preprocessNoob`.
- Account for cell-type composition (blood arrays): use `estimateCellCounts2()` as covariates.
- Use `bumphunter` or `DMRcate` for DMR detection rather than independent CpG tests.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `ChAMP` | You want a comprehensive all-in-one GUI workflow for Illumina array methylation. | You want fine-grained control over each preprocessing step. |
| `methylKit` | You have WGBS/RRBS bisulfite sequencing data (not arrays). | You have Illumina 450K/EPIC array data. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Aryee MJ et al. (2014). Bioinformatics 30:2363.** [PMID:24793076](https://pubmed.ncbi.nlm.nih.gov/24793076)  
  minfi provides accurate preprocessing and differential analysis for 450K/EPIC arrays.

## Common Errors & Troubleshooting

### `Error: Samples do not come from the same array type`

**Cause:** Mixing 450K and EPIC arrays

**Fix:** Subset to common probes: `dropLociWithSnps()` then `subsetByLoci()`

## Additional Notes from Official Documentation

*Extracted from the minfi Bioconductor vignette(s)*

### 1 Introduction


The minfi package provides tools for analyzing Illuminaâs Methylation arrays, specifically the 450k and EPIC (also known as the 850k) arrays. We have partial support for the older 27k array.
The tasks addressed in this package include preprocessing, QC assessments, identification of interesting methylation loci and plotting functionality. Analyzing these types of arrays is ongoing research in ours and other groups.
The input data to this package are IDAT files, representing two different color channels prior to normalization. This is the most complete data type, because IDAT files includes measurements on control probes. It is possible to use Genome Studio files together with the data structures contained in this package, but only some functionality is available because Genome Studio ou

### 1.1 Citing the minfi package


The MINFI package contains methods which are described across multiple manuscripts, by different non-overlapping authors. This makes citing the package a bit difficult, so here is a guide.
If you are using MINFI in a publication, please cite (Aryee et al. 2014 ) . This publication includes details on sex estimation using getSex() , quality control using getQC() , quantile normalization using preprocessQuantile() , bump hunting using bumphunter() and block finding using blockFinder() .
If you are using MINFI to analyze EPIC or 27k arrays, please cite (Fortin, Triche Jr., and Hansen 2017 ) . The publication includes details on convertArray() and combineArrays() , extending NOOB to work in single-sample mode as well as using estimateCellCounts() with reference data from the 450k array to est

```r
toBibtex(citation("minfi"))
```

### 1.2 Terminology


The literature is often a bit unspecific wrt. the terminology for the DNA methylation microarrays.
For the 450k microarray, each sample is measured on a single array, in two different color channels (red and green). Each array measures roughly 450,000 CpG positions. Each CpG is associated with two measurements: a methylated measurement and an âunâ-methylated measurement. These two values can be measured in one of two ways: using a âType Iâ design or a âType II designâ. CpGs measured using a Type I design are measured using a single color, with two different probes in the same color channel providing the methylated and the unmethylated measurements. CpGs measured using a Type II design are measured using a single probe, and two different colors provide the methylated and the un

### 2 minfi classes


The MINFI package is designed to be very flexible for methods developers. This flexibility comes at a cost for users; they need to understand a few different data classes:
RGChannelSet : raw data from the IDAT files; this data is organized at the probe (not CpG locus) level. This data has two channels: Red and Green.
MethylSet : data organized by the CpG locus level, but not mapped to a genome. This data has two channels: Meth (methylated) and Unmeth (unmethylated).
RatioSet : data organized by the CpG locus level, but not mapped to a genome. The data has at least one of two channels: Beta and/or M (logratio of Beta). It may optionally include a CN channel (copy number).
GenomicMethylSet : like a MethylSet , but mapped to a genome.
GenomicRatioSet : like a RatioSet , but mapped to the gen

```r
RGsetEx
```

```r
## class: RGChannelSet 
## dim: 622399 6 
## metadata(0):
## assays(2): Green Red
## rownames(622399): 10600313 10600322 ... 74810490 74810492
## rowData names(0):
## colnames(6): 5723646052_R02C02 5723646052_R04C01 ... 5723646053_R05C02
##   5723646053_R06C02
## colData names(13): Sample_Name Sample_Well ... Basename filenames
## Annotation
##   array: IlluminaHumanMethylation450k
##   annotation: ilmn12.hg19
```

### 3 Reading data


This package supports analysis of IDAT files, containing the summarized bead information.
In our experience, most labs use a âSample Sheetâ CSV file to describe the layout of the experiment. This is based on a sample sheet file provided by Illumina. Our pipeline assumes the existence of such a file(s), but it is relatively easy to create such a file using for example Excel, if it is not available.
We use an example dataset with 6 samples, spread across two slides. First we obtain the system path to the IDAT files; this requires a bit since the data comes from an installed package
This shows the typical layout of 450k data: each âslideâ (containing 12 arrays, see Termiology) is stored in a separate directory, with a numeric name. The top level directory contains the sample sheet fi

```r
baseDir <- system.file("extdata", package = "minfiData")
list.files(baseDir)
```

```r
## [1] "5723646052"      "5723646053"      "SampleSheet.csv"
```

### 3.1 Advanced notes on Reading Data


The only important column in sheet data.frame used in the targets argument for the read.metharray.exp() function is a column names Basename . Typically, such an object would also have columns named Array , Slide , and (optionally) Plate .
We used sheet data files build on top of the Sample Sheet data file provided by Illumina. This is a CSV file, with a header. In this case we assume that the phenotype data starts after a line beginning with [Data] (or that there is no header present).
It is also easy to read a sample sheet manually, using the function read.csv() . Here, we know that we want to skip the first 7 lines of the file.
We now need to populate a Basename column. On possible approach is the following
Finally, MINFI contains a file-based parser: read.metharray() . The return objec

```r
targets2 <- read.csv(file.path(baseDir, "SampleSheet.csv"), 
                     stringsAsFactors = FALSE, skip = 7)
targets2
```

```r
##   Sample_Name Sample_Well Sample_Plate Sample_Group Pool_ID Sentrix_ID
## 1    GroupA_3          H5           NA       GroupA      NA 5723646052
## 2    GroupA_2          D5           NA       GroupA      NA 5723646052
## 3    GroupB_3          C6           NA       GroupB      NA 5723646052
## 4    GroupB_1          F7           NA       GroupB      NA 5723646053
## 5    GroupA_1          G7           NA       GroupA      NA 5723646053
## 6    GroupB_2          H7           NA       GroupB      NA 5723646053
##   Sentrix_Position person age sex status
## 1           R02C02    id3  83   M normal
## 2           R04C01    id2  58   F normal
## 3           R05C02    id3  83   M cancer
## 4           R04C02    id1  75   F cancer
## 5           R05C02    id1  75   F normal
## 6           R06C02    id2  58   F cancer
```

### 4.1 What everyone needs to know


For a methylation array, we have two types of annotation packages: âmanifestâ packages which contains the array design and âannotationâ packages which contains information about where the methylation loci are located on the genome, which genomic features they map to and possible whether they overlap any known SNPs.
You can see which packages are being used by

```r
annotation(RGsetEx)
```

```r
##                          array                     annotation 
## "IlluminaHumanMethylation450k"                  "ilmn12.hg19"
```

### 4.2 Advanced discussion


This discussion is intended for package developers or users who want to understand the internals of MINFI.
A set of 450k data files will initially be read into an RGChannelSet , representing the raw intensities as two matrices: one being the green channel and one being the red channel. This is a class which is very similar to an ExpressionSet or an NChannelSet . The RGChannelSet is, together with a IlluminaMethylationManifest object, preprocessed into a MethylSet . The IlluminaMethylationManifest object contains the array design, and describes how probes and color channels are paired together to measure the methylation level at a specific CpG. The object also contains information about control probes (also known as QC probes). The MethylSet contains normalized data and essentially consist

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/minfi.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/vignettes/minfi/inst/doc/minfi.html
- **GitHub:** https://github.com/Bioconductor/minfi
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Aryee MJ et al. (2014). Bioinformatics, 30:1363-1369.

---
