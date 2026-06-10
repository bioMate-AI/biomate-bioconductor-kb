---
name: bioconductor-ggbio
description: The ggbio package extends and specializes the grammar of graphics for biological data. The graphics are designed to answer common scientific questions, in particular those often asked of high throughput genomics data. All core Bioconductor
when_to_use: Use when: Construct an ideogram track for a specific genome (e.g., hg19) using Ideogram.; Plot gene models from OrganismDb, TxDb, or EnsDb objects using autoplot.; Visualize zoomed regions on an ideogram by passing a GRanges object to xlim.. Not for: For fetching specific gene/transcript information with a rich filtering system (use ensembldb instead).; For purely retrieving gene annotations without visualization (use Homo.sapiens or TxDb directly).
user-invocable: false
---

# ggbio

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.60.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics, ggplot2
- **Imports:** gridExtra, scales, reshape2, gtable, Hmisc, biovizBase, Biobase, S4Vectors, IRanges, Seqinfo, GenomeInfoDb, GenomicRanges, SummarizedExperiment, Biostrings, Rsamtools, GenomicAlignments, BSgenome, VariantAnnotation, rtracklayer, GenomicFeatures, OrganismDbi, ensembldb, AnnotationDbi, AnnotationFilter, rlang
- **Install:** `BiocManager::install("ggbio")`

## When to Use
- Construct an ideogram track for a specific genome (e.g., hg19) using `Ideogram`.
- Plot gene models from `OrganismDb`, `TxDb`, or `EnsDb` objects using `autoplot`.
- Visualize zoomed regions on an ideogram by passing a `GRanges` object to `xlim`.

## When NOT to Use
- For fetching specific gene/transcript information with a rich filtering system (use `ensembldb` instead).
- For purely retrieving gene annotations without visualization (use `Homo.sapiens` or `TxDb` directly).

## Data Requirements
- Input data should be Bioconductor objects like `OrganismDb`, `TxDb`, `EnsDb`, `GRanges`, or `GRangesList`.
- Ideograms require specifying a supported genome build (e.g., "hg19", "mm10").

## Key Parameters
- **genome** (default): Specifies the genome build (e.g., "hg19") for the `Ideogram` function.
- **which** (default): A `GRanges` object used to subset the region of interest in `autoplot`.
- **gap.geom** (default): Controls the geometry of introns (e.g., "chevron") in gene model tracks.
- **stat** (default): Statistical transformation, such as "reduce" to collapse all features.
- **columns** (default): Specifies which columns to retrieve for labeling from an `OrganismDb` object.
- **names.expr** (default): An expression to create flexible label combinations from column names.
- **label.color** (default): Controls the text color of the labels in `autoplot`.
- **fill** (default): Controls the fill color of the plotted features.

## Best Practices
- Use `OrganismDb` or `EnsDb` objects over `TxDb` if you need to label transcripts with gene symbols.
- Use `stat = "reduce"` in `autoplot` to collapse all features and simplify the gene model track.
- Use `names.expr` to combine multiple metadata columns (like `TXNAME` and `GO`) into a single track label.

## Common Pitfalls
- Attempting to label a `TxDb` gene model track with gene symbols. Fix: `TxDb` doesn't contain gene symbols; use an `OrganismDb` or `EnsDb` object instead.
- Ideogram zoom highlights not appearing correctly. Fix: Use `xlim` with a `GRanges` object to change the highlighted zoomed region on the ideogram.
- Overlapping or cluttered gene models in dense regions. Fix: Use `stat = "reduce"` to collapse features or filter the input object before plotting.

## Alternatives
- `ensembldb`: For filtering and fetching Ensembl annotations rather than plotting them.
- `ggplot2`: For general-purpose grammar of graphics plotting without specialized genomic geoms.
- `biovizBase`: For underlying genomic data transformations that feed into visualizations.

## Citations
- Yin, T., Cook, D., & Lawrence, M. (2012). ggbio: an R package for extending the grammar of graphics for genomic data. Genome Biology, 13(8), R77.

## References
- Homepage: bioconductor.org/packages/ggbio
- Vignette: vignette_0_23da92f0.txt
