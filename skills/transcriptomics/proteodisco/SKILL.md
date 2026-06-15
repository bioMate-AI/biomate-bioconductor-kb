---
name: bioconductor-proteodisco
description: ProteoDisco is an R package to facilitate proteogenomics studies. It houses functions to create customized (variant) protein databases based on user-submitted genomic variants, splice-junctions, fusion genes and manual transcript sequences. The flexible workflow can be adopted to suit a myriad of research and experimental settings.
when_to_use: Use when: ProteoDisco is an R package to facilitate proteogenomics studies; knitr init using suppressPackageStartupMessages; label = 'Export FASTA' using exportProteoDiscography; label = 'Logging options' using clearLoggers, registerLogger; label = 'TxDb from FASTA and GTF' using makeTxDbFromGFF, readDNAStringSet; label = 'Inspection' using summary. Not for: Requires R ≥ 4.1.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# ProteoDisco

## Workflows

### Standard Workflow

Generate a customized protein database incorporating genomic variants (SNVs, MNVs, InDels) from VCF/MAF files.

```r
library(ProteoDisco)

# Generate the ProteoDiscography
ProteoDiscography.hg19 <- ProteoDisco::generateProteoDiscography(
  TxDb = TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene,
  genomeSeqs = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
)

# Import genomic variants
ProteoDiscography.hg19 <- ProteoDisco::importGenomicVariants(
  ProteoDiscography = ProteoDiscography.hg19,
  files = system.file('extdata', 'validationSet_hg19.vcf', package = 'ProteoDisco'),
  samplenames = 'Validation Set (GRCh37)',
  threads = 1,
  performAnchorCheck = FALSE
)

# Incorporate genomic variants into transcripts
ProteoDiscography.hg19 <- ProteoDisco::incorporateGenomicVariants(
  ProteoDiscography = ProteoDiscography.hg19,
  aggregateSamples = FALSE,
  aggregateWithinExon = TRUE,
  aggregateWithinTranscript = TRUE,
  ignoreOverlappingMutations = TRUE,
  threads = 1
)

# Export to FASTA
ProteoDisco::exportProteoDiscography(
  ProteoDiscography = ProteoDiscography.hg19,
  outFile = 'example.fasta',
  aggregateSamples = TRUE
)
```
*Note: Inputs are a TxDb object, genome sequences, and VCF/MAF files; the output is a customized protein database in FASTA format.*

### Splice Junctions Workflow

Generate a customized protein database incorporating alternative splicing events from BED or custom splice junction files.

```r
library(ProteoDisco)

# Initialize ProteoDiscography
ProteoDiscography.hg19 <- ProteoDisco::generateProteoDiscography(
  TxDb = TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene,
  genomeSeqs = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
)

# Import splice junctions
ProteoDiscography.hg19 <- ProteoDisco::importSpliceJunctions(
  ProteoDiscography = ProteoDiscography.hg19,
  inputSpliceJunctions = system.file('extdata', 'spliceJunctions_pyQUILTS_chr22.bed', package = 'ProteoDisco'),
  samples = c('pyQUILTS'),
  isTopHat = TRUE,
  aggregateSamples = FALSE,
  removeExisting = TRUE
)

# Generate junction models
ProteoDiscography.hg19 <- ProteoDisco::generateJunctionModels(
  ProteoDiscography = ProteoDiscography.hg19,
  maxDistance = 150,
  skipCanonical = TRUE,
  threads = 1
)
```
*Note: Inputs are splice junction BED files or custom tables; the output is putative splice-isoform fragments added to the ProteoDiscography.*

### Manual Transcripts Workflow

Import manually-curated or long-read transcript sequences to check for proteotypic peptides and export to a customized protein database.

```r
library(ProteoDisco)

# Initialize ProteoDiscography
ProteoDiscography.hg19 <- ProteoDisco::generateProteoDiscography(
  TxDb = TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene,
  genomeSeqs = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
)

# Create manual sequences DataFrame
testSeq1 <- Biostrings::DNAString('ATGACCGCGTCCTCCTCCAGCGACTATGGACAGACTTCCAAGATGAGCCCACGCGTCCCTCAGCAGGATTGGCTGTCTCAACCCCCAGCCAGGGTCACCATCAAAATGGAATGTAACCCTAGCCAGGTGAATGGCTCAAGGAACTCTCCTGATGAATGCAGTGTGGCCAAAGGCGGGAAGATGGTGGGCAGCCCAGACACCGTTGGGATGAACTACGGCAGCTACATGGAGGAGAAGCACATGCCACCCCCAAACATGACCACGAACGAGCGCAGAGTTATCGTGCCAGCAGATCCTACGCTATGGAGTACAGACCATGTGCGGCAGTGGCTGGAGTGGGCGGTGAAAGAATATGGCCTTCCAGACGTCAACATCTTGTTATTCCAGAACATCGATGGGAAGGAACTGTGCAAGATGACCAAGGACGACTTCCAGAGGCTCACCCCCAGCTACAACGCCGACATCCTTCTCTCACATCTCCACTACCTCAGAGAGACTCCTCTTCCACATTTGACTTCAGATGATGTTGATAAAGCCTTACAAAACTCTCCACGGTTAATGCATGCTAGAAACACAGGGGGTGCAGCTTTTATTTTCCCAAATACTTCAGTATATCCTGAAGCTACGCAAAGAATTACAACTAGGCCAGTCTCTTACAGATAA')
manualSeq <- S4Vectors::DataFrame(
  sample = 'Validation Set (GRCh37)',
  identifier = 'TMPRSS2-ERG prostate cancer specific isoform 1',
  gene = 'TMPRSS2-ERG',
  Tx.SequenceMut = Biostrings::DNAStringSet(base::list(testSeq1))
)

# Import manual transcripts
ProteoDiscography.hg19 <- ProteoDisco::importTranscriptSequences(
  ProteoDiscography.hg19,
  transcripts = manualSeq,
  removeExisting = TRUE
)
```
*Note: Inputs are a DataFrame containing manually-curated or long-read transcript sequences; the output is imported transcript sequences added to the ProteoDiscography.*

## When to Use
- To generate customized protein databases (FASTA) incorporating genomic variants (SNVs, MNVs, InDels) from VCF or MAF files using `importGenomicVariants()` and `incorporateGenomicVariants()`.
- To model alternative splicing events and novel exon-exon junctions from BED or custom splice junction files using `importSpliceJunctions()` and `generateJunctionModels()`.
- To integrate manually-curated or long-read transcript sequences (e.g., from Nanopore sequencing) using `importTranscriptSequences()`.
- To identify unique proteotypic peptides by comparing cleaved variant sequences against wild-type databases using `checkProteotypicFragments()`.

## When NOT to Use
- For general mass spectrometry data preprocessing, normalization, or statistical analysis of protein abundance; use `MSnbase` or `MSstats` instead.
- For general peptide-spectrum matching or raw spectra visualization; use `Spectra` instead.

## Data Requirements
- Reference genome sequences (e.g., `BSgenome` object or FASTA file read via `readDNAStringSet()`).
- Transcript annotations (e.g., `TxDb` object containing 'EXONID', 'TXID', and 'GENEID' columns, or GTF/GFF file parsed via `makeTxDbFromGFF()`).
- Genomic variants in VCF or MAF format, or as `VRanges` objects.
- Splice junctions in BED, TopHat, or custom tabular format.

## Key Parameters
- **performAnchorCheck** (`TRUE`): Validates whether reference alleles in VCF/MAF correspond to nucleotides on the reference genome.
- **ignoreNonMatch** (`FALSE`): If `TRUE`, removes non-matching reference anchor records instead of throwing an error.
- **aggregateSamples** (`FALSE`): Determines whether to aggregate samples or generate mutant transcripts per sample.
- **aggregateWithinExon** (`TRUE`): If `TRUE`, multiple mutations within the same exon (CDS) are placed on the same mutant CDS sequence.
- **aggregateWithinTranscript** (`TRUE`): If `TRUE`, aggregates multiple mutant exons within the same transcript.
- **ignoreOverlappingMutations** (`TRUE`): If `TRUE`, retains only the first of overlapping mutations on the same coding position.
- **maxDistance** (`150`): Maximum distance from a known exon boundary before introducing a novel exon in junction modeling.
- **skipCanonical** (`TRUE`): If `TRUE`, skips known canonical exon-exon junctions in junction modeling.

## Best Practices
- Perform a sanity check on reference anchors during variant import to ensure concordance between the reference genome and the variant caller.
- Use `summary()` or `print()` on the `ProteoDiscography` object to inspect imported variants, mutational types, and sample counts.
- Convert transcript identifiers (e.g., ENTREZ IDs) to gene symbols using `AnnotationDbi::select()` and `org.Hs.eg.db` to ease downstream interpretation.
- Use `clearLoggers()` and `registerLogger()` from `ParallelLogger` to configure logging thresholds (e.g., 'TRACE' or 'INFO') for detailed execution tracking.

## Common Pitfalls
- Mismatches between the reference genome used for variant calling and the one supplied to `generateProteoDiscography()` will cause anchor check failures. Fix by ensuring identical reference versions or setting `performAnchorCheck = FALSE` (not recommended).
- Missing 'EXONID', 'TXID', or 'GENEID' columns in the custom `TxDb` object. Fix by using standard Bioconductor annotation packages or correctly formatted GTF files with `makeTxDbFromGFF()`.
- Overlapping mutations on the same coding position causing errors. Fix by setting `ignoreOverlappingMutations = TRUE` to retain only the first mutation.

## Alternatives
- `MSstats` for statistical relative quantification of proteins and peptides.
- `MSnbase` for mass spectrometry data container and processing.
- `Spectra` for low-level mass spectrometry raw data representation and handling.

## Citations
- van Riet et al. (2026), ProteoDisco: Generation of customized protein databases.

## References
- Homepage: bioconductor.org/packages/proteodisco
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/proteodisco/inst/doc/Overview_of_Proteodisco.html
