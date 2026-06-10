---
name: bioconductor-msa
description: The 'msa' package provides a unified R/Bioconductor interface to the multiple sequence alignment algorithms ClustalW, ClustalOmega, and Muscle. All three algorithms are integrated in the package, therefore, they do not depend on any externa
when_to_use: Use when: Performing multiple sequence alignment of amino acid or nucleotide sequences using msa().; Generating highly customizable, publication-ready PDF visualizations of alignments using msaPrettyPrint().; Calculating consensus sequences and conservation scores using msaConsensusSequence() and msaConservationScore().. Not for: For aligning massive genomic datasets (e.g., whole genomes), use minimap2 because msa is designed for gene- or protein-scale alignments.; For basic pairwise sequence alignments, use pwalign because it is specifically built for pairwise comparisons.
user-invocable: false
---

# msa

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.44.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** Biostrings
- **Imports:** Rcpp, BiocGenerics, IRanges, S4Vectors
- **System requirements:** GNU make
- **Install:** `BiocManager::install("msa")`

## When to Use
- Performing multiple sequence alignment of amino acid or nucleotide sequences using `msa()`.
- Generating highly customizable, publication-ready PDF visualizations of alignments using `msaPrettyPrint()`.
- Calculating consensus sequences and conservation scores using `msaConsensusSequence()` and `msaConservationScore()`.

## When NOT to Use
- For aligning massive genomic datasets (e.g., whole genomes), use `minimap2` because `msa` is designed for gene- or protein-scale alignments.
- For basic pairwise sequence alignments, use `pwalign` because it is specifically built for pairwise comparisons.

## Data Requirements
- **Input Format**: Unaligned DNA, RNA, or Amino Acid sequences.
- **Structure**: Loaded as an `AAStringSet` (or similar `XStringSet`) using `readAAStringSet()`.

## Key Parameters
- **output** ("pdf"): Format for pretty-printing (e.g., "pdf", "asis").
- **showNames** ("none"): Controls the display of sequence names in the printed alignment.
- **showLogo** ("none"): Controls the display of the sequence logo (e.g., "top", "none").
- **shadingMode** ("similar"): Mode for color shading in the alignment (e.g., "similar", "functional").
- **type** ("upperlower"): Type of consensus sequence to generate.
- **askForOverwrite** (FALSE): Whether to prompt before overwriting existing files during PDF generation.
- **gapVsGap** (0): Score assigned to gap-versus-gap matches when calculating conservation scores.

## Best Practices
- Use `unmasked()` to retrieve the original alignment if a `colmask()` has been applied to hide specific columns.
- Convert alignments to other formats using `msaConvert()` for downstream phylogenetic analysis (e.g., with `seqinr` or `ape`).
- Use `output="asis"` in `msaPrettyPrint()` when integrating alignments into Sweave or knitr documents.

## Common Pitfalls
- **PDF Compilation Failures**: `msaPrettyPrint()` failing to compile PDFs; fix this by ensuring a working LaTeX system with the `texshade.sty` package is installed on your system path.
- **Alignments Running Off Page**: Large alignments running off the page in PDFs; fix this by splitting the alignment into chunks using `subseq()` and printing them separately.
- **Memory Exhaustion**: Running ClustalW on thousands of sequences can consume excessive memory; fix this by switching to ClustalOmega for large datasets.

## Alternatives
- `DECIPHER`: A powerful Bioconductor package for sequence alignment, database management, and oligonucleotide design.
- `ape`: For phylogenetic analysis and basic sequence manipulation.
- `seqinr`: For biological sequence retrieval and analysis.

## Citations
- Bodenhofer U, Bonatesta E, Horejs-Kainrath C, Hochreiter S. (2015) "msa: an R package for multiple sequence alignment." *Bioinformatics*.

## References
- Homepage: https://bioconductor.org/packages/msa
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/msa/inst/doc/msa.pdf
