---
name: bioconductor-genomicranges
description: The ability to efficiently represent and manipulate genomic annotations and alignments is playing a central role when it comes to analyzing high-throughput sequencing data (a.k.a. NGS data). The GenomicRanges package defines general purpose
when_to_use: Use when: Overlap queries between genomic features; Peak annotation and TSS proximity; Windowed genome coverage computation; Import/export BED/GFF/VCF/BigWig regions; Tiling genome for ChIP-seq/ATAC-seq windows
user-invocable: false
---

# GenomicRanges — Comprehensive Skill Guide

> **Domain:** Genomics Infrastructure
> **Bioconductor:** [GenomicRanges](https://bioconductor.org/packages/release/bioc/html/GenomicRanges.html)
> **Paper:** Lawrence M et al. (2013). PLOS Computational Biology, 9:e1003118.

Infrastructure for representing and manipulating genomic intervals. The core workhorse for any genomic coordinate arithmetic in Bioconductor.

## When to Use

- Overlap queries between genomic features
- Peak annotation and TSS proximity
- Windowed genome coverage computation
- Import/export BED/GFF/VCF/BigWig regions
- Tiling genome for ChIP-seq/ATAC-seq windows

**Alternatives:** `IRanges (integer ranges only)`, `plyranges (tidyverse-style)`

## Do NOT Use When

- Sequence manipulation (use Biostrings instead).
- Annotation retrieval (use AnnotationHub, biomaRt, or TxDb).
- Genome-wide statistics directly (use BSgenome or rtracklayer for coverage).

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Input Format** | BED, GFF/GTF (via rtracklayer), or programmatic construction from data frames |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("GenomicRanges")
library(GenomicRanges)
```

## Workflows

### Genomic interval manipulation and overlap analysis
*Core operations: construct, manipulate, and intersect GRanges objects*

#### Build and manipulate GRanges

```r
library(GenomicRanges)

# Create GRanges from scratch
gr <- GRanges(
    seqnames = c("chr1","chr1","chr2"),
    ranges   = IRanges(start=c(100,200,150), end=c(200,300,250)),
    strand   = c("+","-","*"),
    gene_id  = c("GENE1","GENE2","GENE3")
)

# Resize to 500bp around centre (e.g. for peak centering)
gr_centered <- resize(gr, width=500, fix="center")

# Extend 200bp upstream
gr_extended <- flank(gr, width=200, start=TRUE)
```

#### Find overlaps between two sets

```r
peaks <- readRDS("chip_peaks.rds")    # GRanges of ChIP peaks
genes <- readRDS("gene_models.rds")   # GRanges of gene bodies

# Which peaks overlap any gene?
hits <- findOverlaps(peaks, genes)
peak_in_gene <- peaks[queryHits(hits)]

# Count overlaps per peak
ov_counts <- countOverlaps(peaks, genes)
peaks$n_genes_overlapped <- ov_counts
```

#### Coverage and binning

```r
# Per-base coverage
cov <- coverage(gr)

# Bin genome into 1kb windows and count reads
bins <- tileGenome(seqinfo(gr), tilewidth=1000, cut.last.tile.in.chrom=TRUE)
bin_counts <- countOverlaps(bins, gr)
```


## Key Functions & Parameters

### `GRanges()`

Create genomic ranges object

| Parameter | Description |
|-----------|-------------|
| `seqnames` | chromosome names (Rle) |
| `ranges` | IRanges object with start/end |
| `strand` | '+' \| '-' \| '*' |
| `...` | any additional metadata columns |

### `findOverlaps()`

Find overlaps between two GRanges; returns Hits object

| Parameter | Description |
|-----------|-------------|
| `query` | GRanges |
| `subject` | GRanges |
| `type` | 'any' (default) \| 'start' \| 'end' \| 'within' \| 'equal' |
| `select` | 'all' \| 'first' \| 'last' \| 'arbitrary' |
| `maxgap` | max gap allowed between ranges (default -1L = 0 gap) |
| `minoverlap` | min overlap required (default 1L) |
| `ignore.strand` | logical (default FALSE) |

### `subsetByOverlaps()`

Subset GRanges to those overlapping another set

| Parameter | Description |
|-----------|-------------|
| `x` | GRanges to subset |
| `ranges` | GRanges to overlap with |
| `maxgap` | same as findOverlaps |
| `minoverlap` | same as findOverlaps |

### `coverage()`

Compute per-base coverage as Rle/RleList

| Parameter | Description |
|-----------|-------------|
| `x` | GRanges or GAlignments |
| `shift` | shift each range (default 0) |
| `width` | seqlength per chromosome |
| `weight` | per-range weights (default 1) |

### `resize()`

Resize ranges (e.g. extend TSS windows)

| Parameter | Description |
|-----------|-------------|
| `x` | GRanges |
| `width` | new width in bp |
| `fix` | 'start' \| 'end' \| 'center' |
| `ignore.strand` | logical |

### `promoters()`

Extract promoter regions upstream of TSS

| Parameter | Description |
|-----------|-------------|
| `x` | TxDb or GRanges of transcripts |
| `upstream` | bp upstream of TSS (default 2000) |
| `downstream` | bp downstream of TSS (default 200) |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Genomic intervals are 1-based, closed by default in R (not 0-based BED); subtract 1 when importing BED files.

## Result Interpretation

- `findOverlaps()` result: `queryHits` = indices into query, `subjectHits` = indices into subject; many-to-many mapping.
- `nearest()` / `distanceToNearest()`: returns index of nearest feature in subject and distance in bp.
- `coverage()` result: RleList per chromosome; `sum()` gives total depth.

## Best Practices

- Always use consistent chromosome naming style (UCSC: chr1 vs NCBI: 1); use `seqlevelsStyle()` to convert.
- Set `seqinfo(gr) <- seqinfo(bsgenome)` to attach chromosome lengths before coverage().
- Use `plyranges` package for a dplyr-style API: `gr %>% filter_by_overlaps(other)`.
- Import BED files with `rtracklayer::import('file.bed')` → returns GRanges directly.
- Sort GRanges with `sort()` before most operations for efficiency.
- Use `reduce()` to merge overlapping ranges; `disjoin()` to split at every boundary.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `pybedtools (Python)` | You work in Python or need BEDTools command-line compatibility. | You are in the Bioconductor R ecosystem and want integration with GRanges-aware packages. |

## Benchmark Evidence

*GenomicRanges is foundational infrastructure; citations measure ecosystem adoption.*

- **Lawrence M et al. (2013). PLoS Comput Biol 9:e1003118.** [PMID:23950696](https://pubmed.ncbi.nlm.nih.gov/23950696)
  Original GenomicRanges paper. Demonstrates O(n log n) interval overlap algorithm
  scaling to whole-genome datasets (billions of intervals) with <1GB RAM footprint.

- **Huber W et al. (2015). Nature Methods 12:115.** [PMID:25633503](https://pubmed.ncbi.nlm.nih.gov/25633503)
  Bioconductor overview paper; GenomicRanges is cited as the core interoperability
  layer used by >500 downstream Bioconductor packages, indicating community validation.


## Common Errors & Troubleshooting

### `seqlevels mismatch between query and subject`

**Cause:** chr1 vs 1 naming discrepancy

**Fix:** `seqlevelsStyle(gr1) <- seqlevelsStyle(gr2)` or `keepStandardChromosomes()`

## Additional Notes from Official Documentation

*Extracted from the GenomicRanges Bioconductor vignette(s)*

### Contents


1 Introduction
2 GRanges : Genomic Ranges 2.1 Splitting and combining GRanges objects 2.2 Subsetting GRanges objects 2.3 Basic interval operations for GRanges objects 2.4 Interval set operations for GRanges objects
2.1 Splitting and combining GRanges objects
2.2 Subsetting GRanges objects
2.3 Basic interval operations for GRanges objects
2.4 Interval set operations for GRanges objects
3 GRangesList : Groups of Genomic Ranges 3.1 Basic GRangesList accessors 3.2 Combining GRangesList objects 3.3 Basic interval operations for GRangesList objects 3.4 Subsetting GRangesList objects 3.5 Looping over GRangesList objects
3.1 Basic GRangesList accessors
3.2 Combining GRangesList objects
3.3 Basic interval operations for GRangesList objects
3.4 Subsetting GRangesList objects
3.5 Looping over GRange

### 1 Introduction


The GenomicRanges package serves as the foundation for
representing genomic locations within the Bioconductor project.
In the Bioconductor package hierarchy, it builds upon the IRanges (infrastructure) package and provides
support for the BSgenome (infrastructure), Rsamtools (I/O), ShortRead (I/O & QA), rtracklayer (I/O), GenomicFeatures (infrastructure), GenomicAlignments (sequence reads), VariantAnnotation (called variants), and many other
Bioconductor packages.
This package lays a foundation for genomic analysis by introducing
three classes ( GRanges , GPos , and GRangesList ),
which are used to represent genomic ranges, genomic positions, and groups
of genomic ranges. This vignette focuses on the GRanges and GRangesList classes and their associated methods.
The GenomicRanges package i

```r
if (!require("BiocManager"))
    install.packages("BiocManager")
BiocManager::install("GenomicRanges")
```

```r
library(GenomicRanges)
```

### 2 GRanges : Genomic Ranges


The GRanges class represents a collection of genomic ranges
that each have a single start and end location on the genome. It can be
used to store the location of genomic features such as contiguous binding
sites, transcripts, and exons. These objects can be created by using the GRanges constructor function. For example,
creates a GRanges object with 10 genomic ranges.
The output of the GRanges show method separates the
information into a left and right hand region that are separated by | symbols. The genomic coordinates (seqnames, ranges, and strand)
are located on the left-hand side and the metadata columns (annotation)
are located on the right. For this example, the metadata is
comprised of score and GC information, but almost
anything can be stored in the metadata portion of a GRanges 

```r
gr <- GRanges(
    seqnames = Rle(c("chr1", "chr2", "chr1", "chr3"), c(1, 3, 2, 4)),
    ranges = IRanges(101:110, end = 111:120, names = head(letters, 10)),
    strand = Rle(strand(c("-", "+", "*", "+", "-")), c(1, 2, 2, 3, 2)),
    score = 1:10,
    GC = seq(1, 0, length=10))
gr
```

```r
## GRanges object with 10 ranges and 2 metadata columns:
##     seqnames    ranges strand |     score        GC
##        <Rle> <IRanges>  <Rle> | <integer> <numeric>
##   a     chr1   101-111      - |         1  1.000000
##   b     chr2   102-112      + |         2  0.888889
##   c     chr2   103-113      + |         3  0.777778
##   d     chr2   104-114      * |         4  0.666667
##   e     chr1   105-115      * |         5  0.555556
##   f     chr1   106-116      + |         6  0.444444
##   g     chr3   107-117      + |         7  0.333333
##   h     chr3   108-118      + |         8  0.222222
##   i     chr3   109-119      - |         9  0.111111
##   j     chr3   110-120      - |        10  0.000000
##   -------
##   seqinfo: 3 sequences from an unspecified genome; no seqlengths
```

### 2.1 Splitting and combining GRanges objects


GRanges objects can be divided into groups using the split method. This produces a GRangesList object,
a class that will be discussed in detail in the next section.
Separate GRanges instances can be concatenated by using the c and append methods.

```r
sp <- split(gr, rep(1:2, each=5))
sp
```

```r
## GRangesList object of length 2:
## $`1`
## GRanges object with 5 ranges and 2 metadata columns:
##     seqnames    ranges strand |     score        GC
##        <Rle> <IRanges>  <Rle> | <integer> <numeric>
##   a     chr1   101-111      - |         1  1.000000
##   b     chr2   102-112      + |         2  0.888889
##   c     chr2   103-113      + |         3  0.777778
##   d     chr2   104-114      * |         4  0.666667
##   e     chr1   105-115      * |         5  0.555556
##   -------
##   seqinfo: 3 sequences from an unspecified genome
## 
## $`2`
## GRanges object with 5 ranges and 2 metadata columns:
##     seqnames    ranges strand |     score        GC
##        <Rle> <IRanges>  <Rle> | <integer> <numeric>
##   f     chr1   106-116      + |         6  0.444444
##   g     chr3   107-117      + |         7  0.333333
##   h     chr3   108-118      + |         8  0.222222
##   i     chr3   109-119      - |         9  0.111111
##   j     chr3   110-120      - |        10  0.000000
##   -------
##   seqinfo: 3 sequences from an unspecified genome
```

### 2.2 Subsetting GRanges objects


GRanges objects act like vectors of ranges, with the expected
vector-like subsetting operations available
A second argument to the [ subset operator can be used
to specify which metadata columns to extract from the GRanges object. For example,
Elements can also be assigned to the GRanges object. Here is
an example where the second row of a GRanges object is
replaced with the first row of gr .
There are methods to repeat, reverse, or select specific portions of GRanges objects.

```r
gr[2:3]
```

```r
## GRanges object with 2 ranges and 2 metadata columns:
##     seqnames    ranges strand |     score        GC
##        <Rle> <IRanges>  <Rle> | <integer> <numeric>
##   b     chr2   102-112      + |         2  0.888889
##   c     chr2   103-113      + |         3  0.777778
##   -------
##   seqinfo: 3 sequences from an unspecified genome
```

### 2.3 Basic interval operations for GRanges objects


Basic interval characteristics of GRanges objects can
be extracted using the start , end , width ,
and range methods.
The GRanges class also has many methods for manipulating the
ranges. The methods can be classified as intra-range methods , inter-range methods , and between-range methods .
Intra-range methods operate on each element of a GRanges object independent of the other ranges in the
object. For example, the flank method can be used to recover
regions flanking the set of ranges represented by the GRanges object. So to get a GRanges object containing the ranges that
include the 10 bases upstream of the ranges:
And to include the downstream bases:
Other examples of intra-range methods include resize and shift . The shift method will move the ranges by a
specific number of base pairs

```r
g <- gr[1:3]
g <- append(g, singles[[10]])
start(g)
```

```r
## [1] 101 102 103 110
```

### 2.4 Interval set operations for GRanges objects


Between-range methods calculate relationships between different GRanges objects. Of central importance are findOverlaps and related operations; these are discussed
below. Additional operations treat GRanges as mathematical
sets of coordinates; union(g, g2) is the union of the
coordinates in g and g2 . Here are examples for
calculating the union , the intersect and the
asymmetric difference (using setdiff ).
Related methods are available when the structure of the GRanges objects are âparallelâ to one another, i.e., element
1 of object 1 is related to element 1 of object 2, and so on. These
operations all begin with a p , which is short for
parallel. The methods then perform element-wise, e.g., the union of
element 1 of object 1 with element 1 of object 2, etc. A requirement
for these o

```r
g2 <- head(gr, n=2)
union(g, g2)
```

```r
## GRanges object with 3 ranges and 0 metadata columns:
##       seqnames    ranges strand
##          <Rle> <IRanges>  <Rle>
##   [1]     chr1   101-111      -
##   [2]     chr2   102-113      +
##   [3]     chr3   110-120      -
##   -------
##   seqinfo: 3 sequences from an unspecified genome
```

### 3 GRangesList : Groups of Genomic Ranges


Some important genomic features, such as spliced transcripts that
are comprised of exons, are inherently compound structures. Such a
feature makes much more sense when expressed as a compound object
such as a GRangesList . Whenever genomic features consist of
multiple ranges that are grouped by a parent feature, they can be
represented as a GRangesList object. Consider the simple
example of the two transcript GRangesList below created
using the GRangesList constructor.
The show method for a GRangesList object displays
it as a named list of GRanges objects, where the names of
this list are considered to be the names of the grouping feature. In
the example above, the groups of individual exon ranges are represented
as separate GRanges objects which are further organized into a
list structur

```r
gr1 <- GRanges(
    seqnames = "chr2",
    ranges = IRanges(103, 106),
    strand = "+",
    score = 5L, GC = 0.45)
gr2 <- GRanges(
    seqnames = c("chr1", "chr1"),
    ranges = IRanges(c(107, 113), width = 3),
    strand = c("+", "-"),
    score = 3:4, GC = c(0.3, 0.5))
grl <- GRangesList("txA" = gr1, "txB" = gr2)
grl
```

```r
## GRangesList object of length 2:
## $txA
## GRanges object with 1 range and 2 metadata columns:
##       seqnames    ranges strand |     score        GC
##          <Rle> <IRanges>  <Rle> | <integer> <numeric>
##   [1]     chr2   103-106      + |         5      0.45
##   -------
##   seqinfo: 2 sequences from an unspecified genome; no seqlengths
## 
## $txB
## GRanges object with 2 ranges and 2 metadata columns:
##       seqnames    ranges strand |     score        GC
##          <Rle> <IRanges>  <Rle> | <integer> <numeric>
##   [1]     chr1   107-109      + |         3       0.3
##   [2]     chr1   113-115      - |         4       0.5
##   -------
##   seqinfo: 2 sequences from an unspecified genome; no seqlengths
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/GenomicRanges.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/vignettes/GenomicRanges/inst/doc/GenomicRangesIntroduction.html
- **GitHub:** https://github.com/Bioconductor/GenomicRanges
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Lawrence M et al. (2013). PLOS Computational Biology, 9:e1003118.

---
