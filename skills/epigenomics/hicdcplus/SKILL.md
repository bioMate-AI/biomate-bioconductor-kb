---
name: bioconductor-hicdcplus
description: Systematic 3D interaction calls and differential analysis for Hi-C and HiChIP. The HiC-DC+ (Hi-C/HiChIP direct caller plus) package enables principled statistical analysis of Hi-C and HiChIP data sets – including calling significant interactions within a single experiment and performing differential analysis between conditions given replicate experiments – to facilitate global integrative studies. HiC-DC+ estimates significant interactions in a Hi-C or HiChIP experiment directly from the raw con
when_to_use: Use when: Analyzing Hi-C and HiChIP data with HiCDCPlus; Data normalization and preprocessing (HiCDCPlus). Not for: Requires biological replicates for statistical analysis; Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# HiCDCPlus

## Workflows

### Standard Workflow

Systematic 3D interaction calls and differential analysis for Hi-C and HiChIP. The HiC-DC+ (Hi-C/HiChIP direct caller plus) package enables principled statistical analysis of Hi-C and HiChIP data sets – including calling significant interactions within a single experiment and performing differential analysis between conditions given replicate experiments – to facilitate global integrative studies. HiC-DC+ estimates significant interactions in a Hi-C or HiChIP experiment directly from the raw con

```r
library(HiCDCPlus)
outdir <- tempdir()

# Generate genomic features (GC, mappability, effective length)
construct_features(
  output_path = paste0(outdir, "/hg19_50kb_GATC"),
  gen = "Hsapiens",
  gen_ver = "hg19",
  sig = "GATC",
  bin_type = "Bins-uniform",
  binsize = 50000,
  chrs = "chr21"
)

# Initialize gi_list from the bintolen file
gi_list <- generate_bintolen_gi_list(
  bintolen_path = paste0(outdir, "/hg19_50kb_GATC_bintolen.txt.gz")
)

# Expand 1D features to 2D for modeling
gi_list <- expand_1D_features(gi_list)
```
*Input: Genome version, restriction enzyme pattern, and bin size; Output: A gi_list object containing 2D genomic features ready for interaction calling.*

## When to Use
- **Chromatin Interaction Calling**: To call significant 3D chromatin interactions from Hi-C or HiChIP data using `HiCDCPlus` or `HiCDCPlus_parallel`.
- **Differential Interaction Analysis**: To perform differential interaction analysis across conditions with replicates using `hicdcdiff`.
- **Feature Generation**: To generate genomic features (GC content, mappability, effective length) using `construct_features`.
- **TAD Calling**: To find Topologically Associating Domains (TADs) using `gi_list_topdom`.
- **Compartment Analysis**: To extract A/B compartments (eigenvectors) from `.hic` files using `extract_hic_eigenvectors`.

## When NOT to Use
- **1D Peak Calling**: For standard 1D ChIP-seq peak calling, use `MACS2` or `epigraHMM`.
- **RNA-seq Differential Expression**: For RNA-seq differential expression, use standard `DESeq2` or `edgeR` directly.

## Data Requirements
- **Hi-C Formats**: Hi-C data in `.hic`, `.matrix`, or `.allValidPairs` formats.
- **Enzyme Patterns**: Restriction enzyme cut site patterns (e.g., "GATC").
- **Reference Genome**: Reference genome (e.g., "hg19", "hg38") and chromosome names.

## Key Parameters
- **bin_type** ("Bins-uniform"): Type of binning, either "Bins-uniform" or "Bins-RE-sites".
- **binsize** (50000): Size of genomic windows or number of restriction fragments to merge.
- **sig** ("GATC"): Restriction enzyme recognition sequence.
- **ssize** (0.1): Downsampling rate of rows for modeling in `HiCDCPlus`.
- **mode** ("normcounts"): Output mode for `hicdc2hic` (e.g., 'pvalue', 'qvalue', 'normcounts', 'zvalue', 'raw').
- **fitType** ("mean"): Fit type for dispersion in `hicdcdiff`.

## Best Practices
- **Feature Generation**: Generate genomic features using `construct_features` before initializing the `gi_list` to ensure GC and length biases are modeled.
- **Feature Expansion**: Expand 1D features to 2D using `expand_1D_features` prior to running the negative binomial regression.
- **Parallelization**: Use `HiCDCPlus_parallel` for efficient genome-wide interaction calling across multiple chromosomes.
- **TAD Normalization**: For TAD calling, perform ICE normalization first using `hic2icenorm_gi_list` before running `gi_list_topdom`.

## Common Pitfalls
- **Missing Feature Expansion**: Forgetting to expand 1D features to 2D before running `HiCDCPlus`; always call `expand_1D_features` first.
- **Chromosome Name Mismatch**: Mismatched chromosome names between the feature files and count files; ensure consistent naming (e.g., "chr21" vs "21").
- **Insufficient Replicates**: Insufficient replicates for differential analysis; use `hicdcdiff` with biological replicates to ensure robust statistical power.

## Alternatives
- **diffHic**: For differential interaction analysis using sliding windows.
- **HiTC**: For basic Hi-C data manipulation and ICE normalization.
- **FitHiC**: For calling significant interactions.

## Citations
- Sahin, M., Wong, W., Zhan, Y., Van Deyze, K., Koche, R., and Leslie, C. S. (2021) HiC-DC+: systematic 3D interaction calls and differential analysis for Hi-C and HiChIP. Nature Communications, 12(3366).

## References
- Homepage: bioconductor.org/packages/HiCDCPlus
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/HiCDCPlus/inst/doc/HiCDCPlus.html
