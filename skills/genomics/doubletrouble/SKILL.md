---
name: bioconductor-doubletrouble
description: doubletrouble aims to identify duplicated genes from whole-genome protein sequences and classify them based on their modes of duplication. The duplication modes are i. segmental duplication (SD); ii. tandem duplication (TD); iii. proximal duplication (PD); iv. transposed duplication (TRD) and; v. dispersed duplication (DD). Transposon-derived duplicates (TRD) can be further subdivided into rTRD (retrotransposon-derived duplication) and dTRD (DNA transposon-derived duplication). If users want a s
when_to_use: Use when: Identification and classification of duplicated genes. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# doubletrouble

## Workflows

### Standard Workflow

```r
library(doubletrouble)
library(syntenet)

# Load example data
data(yeast_seq)
data(yeast_annot)
data(diamond_intra)

# Prepare input data
pdata <- process_input(yeast_seq, yeast_annot)

# Classify gene pairs using the standard scheme
c_standard <- classify_gene_pairs(
  annotation = pdata$annotation,
  blast_list = diamond_intra,
  scheme = "standard"
)

# Calculate duplicate frequencies
table(c_standard$Scerevisiae$type)
```
*Note*: Inputs are processed protein sequences and gene annotations along with intraspecies DIAMOND search results; output is a list of classified duplicated gene pairs.

## When to Use
- To identify and classify duplicated genes from whole-genome protein sequences using `classify_gene_pairs`.
- To classify duplicates into different schemes: binary (SD vs SSD), standard (SD, TD, PD, DD), or extended (SD, TD, PD, TRD, DD).

## When NOT to Use
- For finding synteny or running sequence similarity searches directly; use `syntenet` functions like `process_input` and `run_diamond` instead.
- When whole-genome protein sequences (proteome) and gene annotations (GFF3/GTF) are not available.

## Data Requirements
- **Proteome**: List of `AAStringSet` objects containing translated sequences of the primary transcripts.
- **Annotation**: List of `GRanges` objects containing genomic coordinates of all features.
- **Intraspecies BLAST/DIAMOND results**: A list of data frames with tabular output (e.g., from `run_diamond`).

## Key Parameters
- **annotation**: Processed annotation list (a `GRangesList` object).
- **blast_list**: A list of data frames with DIAMOND/BLAST tabular output for intraspecies comparisons.
- **scheme** ("standard"): Classification scheme to use ("binary", "standard", "extended", or "full").
- **blast_inter**: List of data frames with DIAMOND/BLAST tabular output for interspecies comparisons (required for "extended" and "full" schemes).

## Best Practices
- Ensure list names in the annotation match the list names in the sequence object using `setequal(names(seqs), names(annotation))`.
- Keep only the longest sequence for each protein-coding gene to avoid isoforms.
- Perform bidirectional similarity searches for interspecies comparisons and collapse them using `collapse_bidirectional_hits` before classification.

## Common Pitfalls
- Mismatching list names between sequences and annotations: Ensure names are consistent across lists.
- Including multiple isoforms per gene: Filter the input sequences to keep only the longest sequence per gene.

## Alternatives
- `syntenet` for synteny detection and running DIAMOND alignments.

## Citations
- Ohno 2013, Springer Science & Business Media.
- Buchfink, Reuter, and Drost 2021, Nature Methods.

## References
- Homepage: bioconductor.org/packages/doubletrouble
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/doubletrouble/inst/doc/doubletrouble.html
