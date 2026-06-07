---
name: bioconductor-bsgenome
description: Infrastructure shared by all the Biostrings-based genome data packages.
when_to_use: Use when: Chromosome Pattern Matching: Finding or counting the occurrences of an arbitrary nucleotide pattern in a specific chromosome using matchPattern() or countPattern().; Genome-Wide Dictionary Searches: Finding all occurrences of a constant-width dictionary of patterns across an entire genome using PDict() and matchPDict().; Sequence Masking: Applying or toggling masks (e.g., assembly gaps, repeats) o. Not for: For querying remote sequence databases on-the-fly without local storage, use biomaRt instead, as BSgenome relies on locally installed data packages.; For extracting transcript or exon sequences, use GenomicFeatures instead, because BSgenome provides 
user-invocable: false
---

# BSgenome

## When to Use
- **Chromosome Pattern Matching**: Finding or counting the occurrences of an arbitrary nucleotide pattern in a specific chromosome using `matchPattern()` or `countPattern()`.
- **Genome-Wide Dictionary Searches**: Finding all occurrences of a constant-width dictionary of patterns across an entire genome using `PDict()` and `matchPDict()`.
- **Sequence Masking**: Applying or toggling masks (e.g., assembly gaps, repeats) on chromosome sequences using `masks()` and `active()` before performing sequence analysis.

## When NOT to Use
- For querying remote sequence databases on-the-fly without local storage, use **biomaRt** instead, as `BSgenome` relies on locally installed data packages.
- For extracting transcript or exon sequences, use **GenomicFeatures** instead, because `BSgenome` provides raw chromosome sequences rather than gene models.

## Data Requirements
- **Genome Package**: An installed `BSgenome` data package (e.g., `BSgenome.Celegans.UCSC.ce2`).
- **Query Patterns**: A dictionary of patterns stored in a FASTA file and loaded as a `DNAStringSet` using `readDNAStringSet()`.

## Key Parameters
- **max.mismatch** (default): Allows inexact matching by specifying the maximum number of mismatching letters per match in `matchPattern()`.
- **fixed** (default): Logical or vector controlling whether to allow ambiguities during pattern matching in `countPattern()`.
- **append** (default): Logical indicating whether to append results to an existing file in custom output functions.

## Best Practices
- **Verify Chromosome Information**: Use `seqinfo()` and `seqnames()` to verify chromosome naming conventions and lengths before starting an analysis.
- **Manage Memory**: Load only one chromosome sequence into memory at a time (e.g., `subject <- genome[[seqname]]`) to avoid memory allocation problems on large genomes.
- **Reverse Strand Matching**: Find matches on the minus strand by taking the `reverseComplement()` of the short query pattern rather than the entire chromosome subject.

## Common Pitfalls
- **Memory Exhaustion**: Loading all chromosome sequences into memory at once. *Fix*: Iterate through chromosomes using a `for` loop and `seqnames()`.
- **Inefficient Reverse Complementation**: Applying `reverseComplement()` to an entire chromosome sequence. *Fix*: Apply `reverseComplement()` to the short query pattern instead.
- **Masking Confusion**: Forgetting that masks might be active, leading to skipped matches or unexpected results. *Fix*: Explicitly toggle masks using `active(masks(chrY)) <- FALSE`.

## Alternatives
- **Biostrings**: For basic sequence manipulation on individual FASTA files without the full genome package infrastructure.
- **GenomicFeatures**: For extracting transcript/exon sequences rather than raw genomic intervals.
- **biomaRt**: For querying remote sequence databases without local storage.

## Citations
- Pagès, H. (2026). Efficient genome searching with Biostrings and the BSgenome data packages.

## References
- Homepage: https://bioconductor.org/packages/BSgenome
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/BSgenome/inst/doc/GenomeSearching.pdf
