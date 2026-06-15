---
name: bioconductor-scanmir
description: A set of tools for working with miRNA affinity models (KdModels), efficiently scanning for miRNA binding sites, and predicting target repression. It supports scanning using miRNA seeds, full miRNA sequences (enabling 3' alignment) and KdModels, and includes the prediction of slicing and TDMD sites. Finally, it includes utility and plotting functions (e.g. for the visual representation of miRNA-target alignment).
when_to_use: Use when: A set of tools for working with miRNA affinity models (KdModels), efficiently scanning for miRNA binding sites, and pred. Not for: Requires R ≥ 4.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# scanmir

## Workflows

### Standard Workflow

A set of tools for working with miRNA affinity models (KdModels), efficiently scanning for miRNA binding sites, and predicting target repression. It supports scanning using miRNA seeds, full miRNA sequences (enabling 3' alignment) and KdModels, and includes the prediction of slicing and TDMD sites. Finally, it includes utility and plotting functions (e.g. for the visual representation of miRNA-target alignment).

```r
library(scanMiR)
data("SampleTranscript")
data("SampleKdModel")

# Scan for matches using a KdModel
matches <- findSeedMatches(SampleTranscript, SampleKdModel, verbose = FALSE)

# View target alignment
viewTargetAlignment(matches[1], SampleKdModel, SampleTranscript)

# Aggregate matches
agg_matches <- aggregateMatches(matches)
```
Input: A transcript sequence (DNAStringSet or character) and a miRNA KdModel; Output: A GRanges object of matches and a data.frame of aggregated repression values.

## When to Use
- To scan sequences (character vector or `DNAStringSet`) for miRNA binding sites using a seed sequence, full miRNA sequence, or a `KdModel` using `findSeedMatches`.
- To predict dissociation constants (Kd) and binding types for specific 12-mer sequences using `assignKdType`.
- To visualize miRNA-target alignments (including 3' supplementary pairing) using `viewTargetAlignment` or plot KdModel affinities using `plotKdModel`.
- To aggregate predicted miRNA repression across transcripts using `aggregateMatches`.

## When NOT to Use
- For general RNA-seq differential expression analysis without miRNA target prediction (use packages like `DESeq2` or `edgeR`).
- For predicting miRNA-target interactions without sequence-level binding site information or affinity models.

## Data Requirements
- miRNA seeds (character vector of length 7 or 8), full miRNA sequences, or `KdModel` / `KdModelList` objects.
- Target transcript sequences as a character vector or a `DNAStringSet` (optionally with `ORF.length` metadata column).

## Key Parameters
- **verbose** (`TRUE`/`FALSE`): Controls progress reporting during scanning in `findSeedMatches`.
- **onlyCanonical** (`FALSE`): Restricts the scan to canonical miRNA binding sites when using a `KdModel`.
- **ret** (`"GRanges"`): Specifies the return format of `findSeedMatches` (e.g., `"GRanges"`, `"data.frame"`, or `"aggregated"`).
- **shadow** (`0`): Treats matches within the first shadow positions of the UTR as if they were in the ORF.
- **minDist** (`7`): Minimum distance between matches of the same miRNA; only the highest affinity match is kept.
- **what** (`"seeds"`): Specifies what to plot in `plotKdModel` (e.g., `"seeds"`).

## Best Practices
- Provide the `ORF.length` as a metadata column in the input `DNAStringSet` to distinguish between matches in the ORF and 3'UTR regions.
- Use `onlyCanonical = TRUE` in `findSeedMatches` if you want to exclude low-affinity non-canonical binding sites.
- Use `aggregateMatches` to compute the predicted repression of transcripts based on the biochemical model of occupancy.
- For large scans, use multithreading by passing a `BiocParallel` parameter (e.g., `BP = MulticoreParam()`) to `findSeedMatches`.

## Common Pitfalls
- Providing the seed sequence in the wrong orientation: Ensure the seed is given as it would appear in the target sequence (reverse complement of the miRNA seed).
- Memory exhaustion during large scans: Limit the number of seeds processed simultaneously using the `n_seeds` parameter or set `useTmpFiles = TRUE`.

## Alternatives
- `targetscan`: For standard TargetScan-based miRNA target predictions.
- `mirbase`: For retrieving miRNA sequences and annotations.

## Citations
- McGeary, Lin et al. (2019), Science (for the biochemical model of miRNA target repression).
- Grimson et al. (2007), Molecular Cell (for canonical site types and shadow effect).

## References
- Homepage: bioconductor.org/packages/scanmir
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/scanmir/inst/doc/scanmir.html
