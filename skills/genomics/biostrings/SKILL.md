---
name: bioconductor-biostrings
description: Memory efficient string containers, string matching algorithms, and other utilities, for fast manipulation of large biological sequences or sets of sequences.
when_to_use: Use when: Representing and manipulating biological sequences using specialized classes like BString, DNAString, and RNAString.; Matching sets of probes against each other using PDict and vcountPDict.; Computing base content (e.g., GC content) of sequences using alphabetFrequency.; Handling and masking multiple sequence alignments (DNA, RNA, or amino acids) using DNAMultipleAlignment and rowmask/colmask.; Ca. Not for: For standard character string manipulation not involving biological sequences; use base R character vectors or stringr instead because they have less overhead.; For ultra-fast, genome-scale alignment of millions of short sequencing reads; use externa
user-invocable: false
---

# Biostrings

## When to Use
- Representing and manipulating biological sequences using specialized classes like `BString`, `DNAString`, and `RNAString`.
- Matching sets of probes against each other using `PDict` and `vcountPDict`.
- Computing base content (e.g., GC content) of sequences using `alphabetFrequency`.
- Handling and masking multiple sequence alignments (DNA, RNA, or amino acids) using `DNAMultipleAlignment` and `rowmask`/`colmask`.
- Calculating consensus matrices and strings from masked alignments using `consensusMatrix` and `consensusString`.

## When NOT to Use
- For standard character string manipulation not involving biological sequences; use base R `character` vectors or `stringr` instead because they have less overhead.
- For ultra-fast, genome-scale alignment of millions of short sequencing reads; use external command-line aligners (e.g., Minimap2, Bowtie2) instead.

## Data Requirements
- Input sequences in FASTA, Clustal, Phylip, or Stolkholm formats for multiple alignments.
- Character vectors or probe sequence data packages (e.g., `hgu95av2probe`) for sequence manipulation.

## Key Parameters
- **baseOnly**: Logical to compute frequencies of only the standard bases in `alphabetFrequency`.
- **collapse**: Logical to sum frequencies across all sequences in `alphabetFrequency`.
- **filepath**: Path to the alignment file in `readDNAMultipleAlignment`.
- **format**: Format of the alignment file (e.g., "clustal", "phylip").
- **invert**: Logical to specify rows/columns to keep rather than hide when setting masks.
- **append**: Specifies how new mask ranges interact with existing masks ("union", "intersect", "replace").
- **min.fraction**: Fraction of gaps required to mask a column in `maskGaps`.
- **min.block.width**: Minimum width of gap blocks to mask in `maskGaps`.

## Best Practices
- Use `DNAStringSet` instead of lists of `DNAString` objects to leverage vectorized operations.
- Apply `rowmask` and `colmask` to `MultipleAlignment` objects to non-destructively hide uninformative regions or gaps before clustering.
- Use `maskGaps` to automatically mask columns based on gap fractions.
- Cast `MultipleAlignment` objects to `DNAStringSet` before exporting to FASTA with `writeXStringSet`.

## Common Pitfalls
- **Incompatible sequence alphabets**: Attempting to compare a `DNAString` with an `RNAString` directly. Fix: Convert sequences using `RNAString(d)` before comparison.
- **Clustering unmasked alignments**: Generating phylogenetic trees with long uninformative regions, leading to inflated distances. Fix: Use `maskGaps` to remove gap-heavy columns before calculating `stringDist`.
- **Losing masks on export**: Exporting to formats that don't support masks. Fix: Use `write.phylip` to preserve column masking, or cast to `matrix` to drop masked regions entirely.

## Alternatives
- **seqinr**: For biological sequence retrieval and analysis, but uses standard R lists/characters which are less memory-efficient.
- **ape**: For phylogenetics and sequence manipulation, but lacks the specialized S4 infrastructure and non-destructive masking of Biostrings.
- **DECIPHER**: For large-scale sequence alignment, database management, and oligonucleotide design, built on top of Biostrings.

## Citations
- Pagès, H. et al. (2024). Biostrings: Efficient manipulation of biological strings. R package version 2.74.1.

## References
- Homepage: bioconductor.org/packages/Biostrings
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Biostrings/inst/doc/BiostringsQuickOverview.pdf
