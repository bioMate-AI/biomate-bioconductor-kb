---
name: bioconductor-variantannotation
description: Annotate variants, compute amino acid coding changes, predict coding outcomes.
when_to_use: Use when: VCF File Parsing: Reading, exploring, and subsetting Variant Call Format (VCF) files using readVcf() and ScanVcfParam().; Genomic Context Annotation: Locating variants in and around genes (e.g., coding, intron, 5' UTR, splice site) relative to a transcript database using locateVariants().; Coding Consequence Prediction: Computing amino acid coding changes (e.g., synonymous, nonsynonymous, frameshi. Not for: For primary variant calling from raw BAM/FASTQ files. Use tools like GATK or bcftools instead.; For high-throughput annotation of millions of variants where execution speed is the absolute priority. Command-line tools like Ensembl VEP or SnpEff are f
user-invocable: false
---

# VariantAnnotation

## When to Use
- **VCF File Parsing**: Reading, exploring, and subsetting Variant Call Format (VCF) files using `readVcf()` and `ScanVcfParam()`.
- **Genomic Context Annotation**: Locating variants in and around genes (e.g., coding, intron, 5' UTR, splice site) relative to a transcript database using `locateVariants()`.
- **Coding Consequence Prediction**: Computing amino acid coding changes (e.g., synonymous, nonsynonymous, frameshift) for variants in coding regions using `predictCoding()`.
- **Genotype Matrix Conversion**: Converting VCF genotype calls or posterior probabilities into a `SnpMatrix` object for downstream GWAS analysis using `genotypeToSnpMatrix()`.

## When NOT to Use
- For **primary variant calling** from raw BAM/FASTQ files. Use tools like GATK or bcftools instead.
- For **high-throughput annotation of millions of variants** where execution speed is the absolute priority. Command-line tools like Ensembl VEP or SnpEff are faster than R-based loops.

## Data Requirements
- **Input Format**: Variant Call Format (VCF) text files (can be bgzipped and tabix-indexed).
- **Annotation**: A transcript database (`TxDb` object) matching the VCF's genome assembly.
- **Sequence**: A reference genome sequence (`BSgenome` or fasta file) matching the VCF's assembly for computing codon changes.

## Key Parameters
- **param** (default: none): A `GRanges` or `ScanVcfParam` object passed to `readVcf()` to restrict import to specific genomic coordinates or VCF fields.
- **info** (default: all): Character vector in `ScanVcfParam()` specifying which INFO fields (e.g., "LDAF", "RSQ") to extract.
- **geno** (default: all): Character vector in `ScanVcfParam()` specifying which FORMAT/genotype fields (e.g., "GT", "DS", "GL") to extract.
- **region** (default: none): Constructor passed to `locateVariants()` specifying the region of interest (e.g., `CodingVariants()`, `AllVariants()`).
- **seqSource** (default: none): A `BSgenome` object passed to `predictCoding()` to retrieve reference sequences.
- **uncertain** (default: `FALSE`): Logical in `genotypeToSnpMatrix()` indicating whether to use posterior probabilities (GL/GP) instead of called genotypes.

## Best Practices
- **Memory Management**: Use `ScanVcfParam()` to read only the necessary `info` and `geno` fields, or use `TabixFile()` with a `GRanges` object to stream specific genomic coordinates.
- **Chromosome Harmonization**: Ensure chromosome names (seqlevels) match exactly between the VCF and the `TxDb` (e.g., using `seqlevels(vcf) <- "chr22"`) before running `locateVariants()`.
- **Index VCFs**: Always index your VCF files using `bgzip` and `tabix` (or `indexTabix()`) to enable fast, random-access querying.
- **Database Integration**: Use packages like `PolyPhen.Hsapiens.dbSNP131` or `SIFT.Hsapiens.dbSNP132` to query pre-computed damage predictions for non-synonymous variants identified by `predictCoding()`.

## Common Pitfalls
- **Out of Memory Errors**: Attempting to read multi-gigabyte VCF files entirely into memory. *Fix*: Wrap the file path in a `TabixFile` and use `ScanVcfParam` to process the file in chunks or subsets.
- **Empty Overlaps in locateVariants()**: The function returns empty results due to mismatched chromosome naming conventions (e.g., "22" vs "chr22"). *Fix*: Harmonize chromosome names using `seqlevels()`.
- **Incorrect Amino Acid Predictions**: `predictCoding()` returns frameshifts for all variants. *Fix*: Ensure the `BSgenome` reference matches the exact assembly version (e.g., hg19) used to call the variants in the VCF.

## Alternatives
- **ensemblVEP**: An R interface specifically for running the Ensembl Variant Effect Predictor.
- **snpStats**: For downstream statistical analysis of SNP data once converted via `genotypeToSnpMatrix()`.

## Citations
- Obenchain V, et al. (2014). VariantAnnotation: a Bioconductor package for functional annotation of genomic variants. *Bioinformatics*, 30(14), 2075-2076.

## References
- Homepage: https://bioconductor.org/packages/VariantAnnotation
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/VariantAnnotation/inst/doc/VariantAnnotation.pdf
