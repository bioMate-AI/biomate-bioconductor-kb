---
name: bioconductor-bindingsitefinder
description: Precise knowledge on the binding sites of an RNA-binding protein (RBP) is key to understand (post-) transcriptional regulatory processes. Here we present a workflow that describes how exact binding sites can be defined from iCLIP data. The package provides functions for binding site definition and result visualization. For details please see the vignette.
when_to_use: Use when: Definition of binding sites from iCLIP signal. Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# BindingSiteFinder

## Workflows

### Standard Workflow

```r
library(BindingSiteFinder)
library(txdbmaker)
library(rtracklayer)

# 1. Import crosslink sites
csFile <- system.file("extdata", "PureCLIP_crosslink_sites_examples.bed", package="BindingSiteFinder")
cs <- rtracklayer::import(con = csFile, format = "BED")

# 2. Create metadata table and construct BSFDataSet
files <- system.file("extdata", package="BindingSiteFinder")
clipFilesP <- list.files(files, pattern = "plus.bw$", full.names = TRUE)
clipFilesM <- list.files(files, pattern = "minus.bw$", full.names = TRUE)
meta <- data.frame(
  id = 1:4,
  condition = factor(rep("WT", 4)),
  clPlus = clipFilesP,
  clMinus = clipFilesM
)
bds <- BSFDataSetFromBigWig(ranges = cs, meta = meta, silent = TRUE)

# 3. Build gene and transcript region annotations
annoDb <- txdbmaker::makeTxDbFromGFF(file = "gencode_v37_annotation.gff3", format = "gff3")
gns <- genes(annoDb)
regions <- GRangesList(
  CDS = cds(annoDb),
  Intron = unlist(intronsByTranscript(annoDb)),
  UTR3 = unlist(threeUTRsByTranscript(annoDb)),
  UTR5 = unlist(fiveUTRsByTranscript(annoDb))
)

# 4. Run BSFind wrapper
bdsOut <- BSFind(
  object = bds,
  anno.genes = gns,
  anno.transcriptRegionList = regions,
  est.subsetChromosome = "chr22",
  veryQuiet = TRUE
)

# 5. Export results
exportToBED(bdsOut, con = "./myBindingSites.bed")
```
**Input/Output Note:** Inputs a `BSFDataSet` and genomic annotations; outputs a refined `BSFDataSet` with defined binding sites and exports them to a BED file.

### Differential Binding Analysis

```r
library(BindingSiteFinder)
library(txdbmaker)

# 1. Load Gene Annotations and Transcript Regions
annoDb <- txdbmaker::makeTxDbFromGFF(file = "gencode_v37_annotation.gff3", format = "gff3")
gns <- genes(annoDb)
regions <- GRangesList(
  CDS = cds(annoDb),
  Intron = unlist(intronsByTranscript(annoDb)),
  UTR3 = unlist(threeUTRsByTranscript(annoDb)),
  UTR5 = unlist(fiveUTRsByTranscript(annoDb))
)

# 2. Define binding sites for a condition
bdsOut <- BSFind(
  object = bds, 
  anno.genes = gns, 
  anno.transcriptRegionList = regions, 
  est.subsetChromosome = "chr22"
)
```
**Input/Output Note:** Inputs a `BSFDataSet` and genomic annotations; outputs a `BSFDataSet` with defined binding sites prepared for downstream differential testing.

## When to Use
- To define precise, equally sized RBP binding sites from genome-wide iCLIP coverage and peak calling results (e.g., PureCLIP crosslink sites).
- To filter, merge, and check reproducibility of crosslink sites across replicates using `BSFind()`.
- To annotate binding sites with genomic features such as genes and transcript regions (CDS, Introns, UTRs) using `genes()`, `cds()`, and `intronsByTranscript()`.

## When NOT to Use
- For analyzing RNA-seq differential expression or splicing directly without iCLIP/CLIP-seq data (use `DESeq2` or `dexseq` instead).
- For peak calling directly from BAM files (use peak callers like `PureCLIP` first, then import results into `BindingSiteFinder`).

## Data Requirements
- Crosslink sites as a `GRanges` object (typically single-nucleotide wide, e.g., imported from PureCLIP BED files).
- Replicate-specific coverage data in strand-specific BigWig files (`clPlus` and `clMinus`).
- Gene annotations as a `GRanges` object and transcript regions as a `GRangesList` (e.g., CDS, Introns, 3' UTR, 5' UTR).

## Key Parameters
- **object**: A `BSFDataSet` containing crosslink ranges and metadata.
- **anno.genes**: A `GRanges` object containing gene annotations.
- **anno.transcriptRegionList**: A `GRangesList` containing transcript region annotations.
- **est.subsetChromosome** ("chr22"): Character vector specifying which chromosome to use for estimating binding site width.
- **veryQuiet** (FALSE): Logical indicating whether to suppress progress messages.
- **est.maxBsWidth** (29): Numeric specifying the maximum binding site width to test during estimation.

## Best Practices
- Pre-filter crosslink sites with low scores (e.g., removing the lowest 1% of PureCLIP scores) using `pureClipGlobalFilterPlot()` to assess the cutoff.
- Use `estimateBsWidthPlot()` to evaluate the optimal binding site width based on the signal-to-flank ratio.
- Enforce reproducibility across replicates by setting the `nReps` parameter (typically N-1 replicates) and verifying with `reproducibilityScatterPlot()`.

## Common Pitfalls
- *Pitfall*: Crosslink sites overlapping multiple genes causing inflated site counts. *Fix*: Set `overlaps = "keepSingle"` in `BSFind()` to reduce overlapping loci to a single instance.
- *Pitfall*: Low reproducibility across replicates due to library size differences. *Fix*: Use `reproducibilityFilterPlot()` to inspect and adjust the replicate-specific crosslink threshold.

## Alternatives
- `csaw` for window-based differential binding analysis of ChIP-seq/ATAC-seq.
- `macsr` for peak calling on enrichment data.
- `CLIPreg` for integrating CLIP-seq with RNA-seq.

## Citations
- Busch A, Brüggemann M, Ebersberger S, Zarnack K (2020). "iCLIP data analysis: A complete pipeline from sequencing reads to RBP binding sites." *Methods*, 178, 49-62. doi:10.1016/j.ymeth.2019.11.008.

## References
- Homepage: https://bioconductor.org/packages/bindingsitefinder
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/bindingsitefinder/inst/doc/Definition_of_binding_sites_from_iCLIP_signal.html
