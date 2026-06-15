---
name: bioconductor-extrachips
description: This package builds on existing tools and adds some simple but extremely useful capabilities for working wth ChIP-Seq data. The focus is on detecting differential binding windows/regions. One set of functions focusses on set-operations retaining mcols for GRanges objects, whilst another group of functions are to aid visualisation of results. Coercion to tibble objects is also implemented.
when_to_use: Use when: Differential Signal Analysis (Fixed-Width Windows); Differential Signal Analysis (Sliding Windows); Range-Based Operations; ChIP-seq peak analysis (extraChIPs). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# extraChIPs

## Workflows

### Standard Workflow

This package builds on existing tools and adds some simple but extremely useful capabilities for working wth ChIP-Seq data. The focus is on detecting differential binding windows/regions. One set of functions focusses on set-operations retaining mcols for GRanges objects, whilst another group of functions are to aid visualisation of results. Coercion to tibble objects is also implemented.

```r
library(extraChIPs)
library(GenomicRanges)

# Define chromosome information
sq <- defineSeqinfo("GRCh37")

# Create mock GRangesList for consensus peak calling
gr1 <- GRanges("chr10:1000-2000", seqinfo = sq)
gr2 <- GRanges("chr10:1200-2200", seqinfo = sq)
peaks <- GRangesList(sample1 = gr1, sample2 = gr2)

# Generate consensus peaks
consensus <- makeConsensus(peaks, p = 0.5)

# Plot overlaps
plotOverlaps(peaks)
```
*Input: A GRangesList of peak calls; Output: A consensus GRanges object and overlap plots.*

## When to Use
- **Consensus Peak Definition**: To define consensus peaks across replicates using `makeConsensus`.
- **Peak Importing and Filtering**: To import and filter peaks with blacklists/greylists using `importPeaks`.
- **Differential Signal Analysis**: To perform differential signal analysis on window/region counts using `fitAssayDiff`.
- **Gene Mapping**: To map peaks/regions to genes and promoters using `mapByFeature`.
- **Visualization**: To visualize peak overlaps with `plotOverlaps` and signal profiles with `plotProfileHeatmap` or `getProfileData`.

## When NOT to Use
- **De Novo Motif Discovery**: For de novo motif discovery, use `memes` or `universalmotif` instead.
- **De Novo Peak Calling**: For peak calling itself, use `MACS2` or `epigraHMM` as `extraChIPs` is designed for downstream analysis of existing peak calls.

## Data Requirements
- **Peak Files**: Peak files in narrowPeak format or GRanges objects.
- **Read Counts**: BAM files for read counting, or a pre-computed `RangedSummarizedExperiment` object.
- **Annotations**: Annotation files (GTF/GFF) for mapping peaks to genes.

## Key Parameters
- **p** (0.5): Minimum proportion of replicates in which a peak must be present to be included in the consensus.
- **norm** ("TMM"): Normalization method in `fitAssayDiff` (e.g., "TMM" or library-size).
- **fc** (1.2): Fold-change threshold incorporated into testing in `fitAssayDiff`.
- **asRanges** (TRUE): Logical indicating whether to return results as a GRanges object.
- **upstream** (2500): Upstream distance for defining promoters.
- **downstream** (500): Downstream distance for defining promoters.

## Best Practices
- **Define Seqinfo**: Define a consistent `Seqinfo` object at the start of the workflow using `defineSeqinfo`.
- **Exclude Artifacts**: Exclude blacklisted and grey-listed regions using `importPeaks` to avoid false positives.
- **Normalization Check**: Test whether group-specific count distributions are similar using `quantro` before applying TMM normalization.
- **Classify Status**: Use `addDiffStatus` to classify regions as "Increased", "Decreased", or "Unchanged" for downstream visualization.

## Common Pitfalls
- **Inappropriate Normalization**: Applying TMM normalization when group-specific distributions differ significantly; use `quantro` to test this assumption first.
- **Metadata Loss**: Losing metadata columns during GRanges set operations; use `reduceMC` or `makeConsensus` to retain metadata.
- **Mapping Coordinates**: Mapping peaks to genes without resetting the core ranges; use `colToRanges` to restore the original peak boundaries before mapping.

## Alternatives
- **DiffBind**: For standard affinity-based differential analysis.
- **csaw**: For sliding window-based differential binding analysis.
- **ChIPseeker**: For peak annotation and visualization.

## Citations
- Ross-Innes et al. 2012, Nature (for DiffBind-style approaches)
- Hicks and Irizarry 2015, Genome Biol. (for quantro)

## References
- Homepage: bioconductor.org/packages/extraChIPs
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/extraChIPs/inst/doc/extraChIPs.html
