---
name: bioconductor-msa2dist
description: MSA2dist calculates pairwise distances between all sequences of a DNAStringSet or a AAStringSet using a custom score matrix and conducts codon based analysis. It uses scoring matrices to be used in these pairwise distance calcualtions which can be adapted to any scoring for DNA or AA characters. E.g. by using literal distances MSA2dist calculates pairwise IUPAC distances.
when_to_use: Use when: MSA2dist calculates pairwise distances between all sequences of a DNAStringSet or a AAStringSet using a custom score mat; MSA2dist Vignette. Not for: Requires R ≥ 4.4.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# msa2dist

## Workflows

### Standard Workflow

MSA2dist calculates pairwise distances between all sequences of a DNAStringSet or a AAStringSet using a custom score matrix and conducts codon based analysis. It uses scoring matrices to be used in these pairwise distance calculations which can be adapted to any scoring for DNA or AA characters. E.g. by using literal distances MSA2dist calculates pairwise IUPAC distances.

```r
library(MSA2dist)
# Load example data
data(hiv, package="MSA2dist")

# 1. Calculate pairwise DNA distances (K80 model)
dna_dist <- dnastring2dist(hiv, model="K80")

# 2. Translate to Amino Acids and calculate Grantham distances
aa_seqs <- cds2aa(hiv)
aa_dist <- aastring2dist(aa_seqs, score=granthamMatrix())

# 3. Calculate synonymous/nonsynonymous substitutions (MYN model)
kaks_myn <- dnastring2kaks(hiv, model="MYN")
```
Note: Input is a pre-aligned `DNAStringSet` object, and outputs are distance matrices and a data frame of Ka/Ks values.

## When to Use
- **Pairwise Amino Acid Distances**: When you need to calculate pairwise distances from a `Biostrings::AAStringSet` using custom scoring matrices like Grantham's distance (`aastring2dist`, `granthamMatrix`).
- **Pairwise DNA Distances**: When you need to calculate pairwise nucleotide distances from a `Biostrings::DNAStringSet` using evolutionary models (e.g., "K80") or literal IUPAC distances for diploid phasing (`dnastring2dist`).
- **Synonymous/Nonsynonymous Substitutions**: When you need to calculate Ka, Ks, and Ka/Ks ratios from coding sequences using models like Li, NG86, or MYN (`dnastring2kaks`).

## When NOT to Use
- **Non-coding Sequences**: For non-coding sequences where codon-based Ka/Ks analysis is not applicable (use standard nucleotide distance tools like `ape::dist.dna` instead).
- **Initial Alignment**: For performing the initial multiple sequence alignment (MSA) itself (use external tools like `mafft`, `muscle`, or the R package `msa` first).

## Data Requirements
- Pre-aligned sequences (Multiple Sequence Alignment) represented as a `Biostrings::DNAStringSet` or `Biostrings::AAStringSet`.
- Coding sequences must have lengths that are multiples of three for translation, or forced via `cds2aa(shorten=TRUE)`.

## Key Parameters
- **model** ("K80"): The evolutionary model to use in `dnastring2dist` (e.g., "K80", "IUPAC") or `dnastring2kaks` (e.g., "Li", "NG86", "MYN", "YN").
- **score** (NULL): Scoring matrix for amino acid distance calculations in `aastring2dist` (e.g., `granthamMatrix()`).
- **frame** (1): Codon start site (1, 2, or 3) for frame-aware translation in `cds2aa`.
- **shorten** (FALSE): Logical indicating whether to force the coding sequence length to be a multiple of three in `cds2aa`.
- **genetic.code** (standard): Alternative genetic code mapping (e.g., `Biostrings::getGeneticCode("2")`) in `cds2aa`.
- **threads** (1): Number of threads for parallelized calculations in `dnastring2dist` or `dnastring2kaks`.

## Best Practices
- Ensure sequences are pre-aligned before calculating distances or Ka/Ks ratios.
- Use `cds2aa(shorten=TRUE)` to handle sequences whose lengths are not multiples of three before translating.
- Use `dnastring2dist(model="IUPAC")` to directly calculate distances on IUPAC nucleotide ambiguity encoded sequences (e.g., from diploid individuals).

## Common Pitfalls
- **Translation fails or returns empty set**: Occurs when the sequence length is not a multiple of three and `shorten=FALSE`. Fix: Set `shorten=TRUE` in `cds2aa()`.
- **Incompatible sequence formats for external packages**: Trying to pass `DNAStringSet` directly to `ape` or `seqinr`. Fix: Convert formats using `dnastring2dnabin()` or `dnastring2aln()`.

## Alternatives
- **ape**: For standard DNA distance calculations (`ape::dist.dna`) and neighbor-joining trees.
- **seqinr**: For standard sequence alignments and codon analysis.
- **msa**: For performing multiple sequence alignments in R.

## Citations
- Nei, M. and Gojobori, T. (1986). Simple methods for estimating the numbers of synonymous and nonsynonymous nucleotide substitutions. Molecular Biology and Evolution.
- Li, W.-H. (1993). Unbiased estimation of the number of synonymous and nonsynonymous substitutions. Journal of Molecular Evolution.
- Zhang, Z., Li, J., and Yu, J. (2006). CODON-ML: computing evolutionary rates of codons.

## References
- Homepage: bioconductor.org/packages/msa2dist
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/msa2dist/inst/doc/MSA2dist.html
