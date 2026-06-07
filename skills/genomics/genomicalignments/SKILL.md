---
name: bioconductor-genomicalignments
description: Provides efficient containers for storing and manipulating short genomic alignments (typically obtained by aligning short reads to a reference genome). This includes read counting, computing the coverage, junction detection, and working wit
when_to_use: Use when: Counting aligned reads overlapping genomic features (e.g., exons, genes) for differential expression analysis using summarizeOverlaps.; Loading and manipulating paired-end alignments from BAM files using readGAlignmentPairs.; Analyzing splice junctions, insertions, and deletions in RNA-seq reads using the njunc, cigar, and cigarOpTable functions.; Filtering alignments based on mapping quality, dup. Not for: For ultra-fast, memory-efficient read counting on massive datasets, use Rsubread::featureCounts because it is written in C and optimized for speed.; For low-level BAM file indexing or header manipulation without loading alignments, use Rsamtools beca
user-invocable: false
---

# GenomicAlignments

## When to Use
- Counting aligned reads overlapping genomic features (e.g., exons, genes) for differential expression analysis using `summarizeOverlaps`.
- Loading and manipulating paired-end alignments from BAM files using `readGAlignmentPairs`.
- Analyzing splice junctions, insertions, and deletions in RNA-seq reads using the `njunc`, `cigar`, and `cigarOpTable` functions.
- Filtering alignments based on mapping quality, duplicates, or specific genomic regions using `ScanBamParam` and `scanBamFlag`.

## When NOT to Use
- For ultra-fast, memory-efficient read counting on massive datasets, use `Rsubread::featureCounts` because it is written in C and optimized for speed.
- For low-level BAM file indexing or header manipulation without loading alignments, use `Rsamtools` because it provides direct wrappers to samtools functionality.

## Data Requirements
- **Input Format**: Sorted and indexed BAM files.
- **Features**: Genomic features provided as `GRanges` or `GRangesList` objects for overlap counting.
- **Structure**: Alignments are loaded into `GAlignments` (single-end) or `GAlignmentPairs` (paired-end) objects.

## Key Parameters
- **use.names** (TRUE): Logical indicating whether to load query names (QNAME) from the BAM file in `readGAlignments`.
- **param**: A `ScanBamParam` object specifying filtering criteria (e.g., flags, genomic regions) when reading alignments.
- **mode** ("Union"): The overlap resolution mode for `summarizeOverlaps` (e.g., "Union", "IntersectionStrict", "IntersectionNotEmpty").
- **isDuplicate** (FALSE): Flag in `scanBamFlag` to filter out PCR or optical duplicates.
- **isNotPassingQualityControls** (FALSE): Flag in `scanBamFlag` to filter out low-quality reads.
- **isFirstMateRead** (TRUE): Flag in `scanBamFlag` to specifically load only the first segment of paired-end reads.

## Best Practices
- Use `ScanBamParam` with `scanBamFlag` to filter out PCR duplicates and reads failing quality controls before loading alignments into memory.
- When working with paired-end data, use `readGAlignmentPairs` and filter for proper pairs using `isProperPair` to ensure high-quality alignments.
- Use `summarizeOverlaps` with a `GRangesList` (e.g., exons grouped by transcript or gene) to correctly count reads spanning multiple exons of the same feature.

## Common Pitfalls
- **Out of memory errors**: Running out of memory when loading entire BAM files at once. Fix: Use `ScanBamParam` to restrict loading to specific genomic regions (using `which`) or specific fields (using `what`).
- **Incorrect paired-end counting**: Counting paired-end reads as independent single-end reads. Fix: Ensure paired-end BAM files are loaded with `readGAlignmentPairs` or handled appropriately in counting functions.
- **Assuming unique read names**: Assuming read names are unique in the loaded `GAlignments` object, which fails when aligners report multiple alignments per read. Fix: Handle duplicated query names by checking `duplicated(names(gal))`.

## Alternatives
- `Rsubread`: For extremely fast, multi-threaded read counting (`featureCounts`) in R.
- `Rsamtools`: For low-level BAM/SAM file access, indexing, and manipulation.
- `GenomicRanges`: For general genomic interval operations once alignments are converted to ranges.

## Citations
- Lawrence, M., Huber, W., Pagès, H., Aboyoun, P., Carlson, M., Gentleman, R., ... & Carey, V. J. (2013). Software for computing and annotating genomic ranges. *PLoS Computational Biology*, 9(8), e1003118.

## References
- Homepage: https://bioconductor.org/packages/GenomicAlignments
- Vignette: vignette_0_5516405c.txt
