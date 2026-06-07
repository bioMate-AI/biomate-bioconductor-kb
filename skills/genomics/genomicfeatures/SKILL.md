---
name: bioconductor-genomicfeatures
description: Extract the genomic locations of genes, transcripts, exons, introns, and CDS, for the gene models stored in a TxDb object. A TxDb object is a small database that contains the gene models of a given organism/assembly. Bioconductor provides a
when_to_use: Use when: Extract genomic coordinates for exons, transcripts, or coding sequences as GRanges objects using transcripts, exons, or cds.; Group genomic features by gene or transcript into a GRangesList using transcriptsBy or exonsBy.; Retrieve actual sequence data by pairing a TxDb with a BSgenome package and using extractTranscriptSeqs.. Not for: For extracting actual sequence data without a BSgenome package (use BSgenome directly instead because GenomicFeatures only stores coordinates).; For finding overlaps between alignments and features without first extracting the features (use findOverl
user-invocable: false
---

# GenomicFeatures

## When to Use
- Extract genomic coordinates for exons, transcripts, or coding sequences as `GRanges` objects using `transcripts`, `exons`, or `cds`.
- Group genomic features by gene or transcript into a `GRangesList` using `transcriptsBy` or `exonsBy`.
- Retrieve actual sequence data by pairing a `TxDb` with a `BSgenome` package and using `extractTranscriptSeqs`.

## When NOT to Use
- For extracting actual sequence data without a `BSgenome` package (use `BSgenome` directly instead because `GenomicFeatures` only stores coordinates).
- For finding overlaps between alignments and features without first extracting the features (use `findOverlaps` on the extracted `GRangesList` instead).

## Data Requirements
- Requires a `TxDb` object (loaded via `loadDb` or an annotation package like `TxDb.Hsapiens.UCSC.hg19.knownGene`).
- Sequence extraction requires an appropriate `BSgenome` package (e.g., `BSgenome.Hsapiens.UCSC.hg19`).

## Key Parameters
- **keys** (default): A vector of identifiers to look up when using `select`.
- **columns** (default): The columns to retrieve when using `select`.
- **keytype** (default): The type of key being passed to `select`.
- **filter** (default): A list (e.g., `tx_chrom`, `tx_strand`) to subset results in `transcripts`.
- **upstream** (default): Number of bases upstream from the transcription start site for `promoters`.
- **downstream** (default): Number of bases downstream from the transcription start site for `promoters`.
- **by** (default): The feature to group by (e.g., "gene", "tx") in `transcriptsBy` or `exonsBy`.
- **use.names** (default): Logical to retain sequence names in `extractTranscriptSeqs`.

## Best Practices
- Check active chromosomes using `seqlevels` before extracting features to limit the data returned.
- Use `select` to map between different identifiers (e.g., `TXNAME` to `GENEID`) within the `TxDb` object.
- Group features into a `GRangesList` (e.g., using `exonsBy`) before using `findOverlaps` to contextualize high-throughput sequencing alignments.

## Common Pitfalls
- Extracting sequences for all transcribed regions instead of just coding regions. Fix: Use `cdsBy` to subset coding regions before calling `extractTranscriptSeqs`.
- Translating non-coding sequences resulting in meaningless translations. Fix: Ensure you extract sequences using `cdsBy` before passing them to `translate`.
- Forgetting which chromosomes are active after filtering. Fix: Use `seqlevels0` to reset to the original chromosomes stored in the database.

## Alternatives
- `txdbmaker`: For making `TxDb` objects from genomic annotations (UCSC, Ensembl, GFF) rather than querying existing ones.
- `BSgenome`: For working directly with full genome sequences rather than transcript-specific metadata.
- `GenomicRanges`: For general manipulation of `GRanges` objects rather than extracting them from a database.

## Citations
- Carlson M, Aboyoun P, Pagès H, Falcon S, Morgan M (2026). "Obtaining and Utilizing TxDb Objects." Bioconductor Vignette.

## References
- Homepage: bioconductor.org/packages/GenomicFeatures
- Vignette: vignette_0_d47eae8b.txt
