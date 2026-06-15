---
name: bioconductor-tximport
description: "Current version only works in 'merge' mode: A single table of gene summarizations is generated with one column for each sample file."
when_to_use: "Use when: Consolidating transcript quantifications from multiple RNA-seq samples into single gene-level matrix; Preparing data for downstream analysis tools that accept merged count tables; Batch processing of Salmon, Kallisto, or similar transcript quantifier outputs. Not for: Workflows requiring per-sample output files for DESeq2 or similar tools expecting individual sample tables; Transcript-level differential expression analysis; Single-sample analysis pipelines"
user-invocable: false
---

# tximport

Current version only works in 'merge' mode: A single table of gene summarizations is generated with one column for each sample file.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.40.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** GeneExpression, ImmunoOncology, Preprocessing, RNASeq, Software, Transcription
- **Install:** `BiocManager::install("tximport")`

## When to Use

- Consolidating transcript quantifications from multiple RNA-seq samples into single gene-level matrix
- Preparing data for downstream analysis tools that accept merged count tables
- Batch processing of Salmon, Kallisto, or similar transcript quantifier outputs

## When NOT to Use

- Workflows requiring per-sample output files for DESeq2 or similar tools expecting individual sample tables
- Transcript-level differential expression analysis
- Single-sample analysis pipelines

## Scientific Assumptions

- {'assumption': 'All input quantification files use identical gene identifier nomenclature and annotation version', 'violation_context': 'Violated when mixing quantifications from different reference genomes or annotation versions, resulting in gene name mismatches and incomplete merging'}
- {'assumption': 'Transcript-to-gene mapping is deterministic and one-to-many (transcripts map to single gene)', 'violation_context': 'Violated in cases of overlapping genes, alternative splicing, or ambiguous transcript assignments; may result in double-counting or gene assignment errors'}
- {'assumption': 'Input quantification files represent independent biological samples suitable for merging into single analysis matrix', 'violation_context': 'Violated when samples are technical replicates or from incompatible experimental designs; may confound downstream statistical analysis'}
- {'assumption': 'Gene-level summarization via aggregation (sum or mean) of transcript abundances is appropriate for downstream analysis', 'violation_context': 'Violated when transcript-level resolution is required or when isoform-specific effects are scientifically important'}

## Common Pitfalls

- {'mistake': 'Using tximport output directly with DESeq2 expecting per-sample tables', 'consequence': 'DESeq2 will fail or produce incorrect results due to incompatible input format (merged table vs per-sample requirement)', 'recommendation': 'Verify DESeq2 input format requirements before using tximport; consider alternative workflows or manual reformatting if per-sample tables needed'}
- {'mistake': 'Selecting incorrect annotation version for gene mapping', 'consequence': 'Gene identifiers may not match between quantification files and annotation, resulting in missing or misaligned genes', 'recommendation': 'Ensure annotation version matches the reference genome used for transcript quantification'}
- {'mistake': 'Providing gene names from quantification file without verifying consistency across samples', 'consequence': 'Gene name mismatches across samples could result in incomplete or duplicated rows in merged table', 'recommendation': 'Validate that all input files use identical gene naming conventions before merging'}

## Key Parameters

- {'parameter': 'select_the_source_of_the_quantification_file', 'scientific_meaning': 'Specifies whether gene identifiers are embedded in quantification files or must be obtained from external annotation file', 'typical_values': ['Gene names in counts file', 'Gene names from external GFF/GTF annotation'], 'context_guidance': {'scenario_embedded_names': 'Use when quantification files already contain gene identifiers', 'scenario_external_annotation': 'Use when quantification files contain only transcript IDs requiring mapping to genes via GFF/GTF'}}
- {'parameter': 'select_an_annotation_version', 'scientific_meaning': 'Specifies reference genome build and annotation version for gene mapping', 'typical_values': ['hg38', 'hg19', 'mm10', 'mm9', 'other organism-specific builds'], 'context_guidance': {'scenario_human': 'Select hg38 for recent human studies, hg19 for legacy data', 'scenario_mouse': 'Select mm10 for recent mouse studies', 'scenario_other': 'consult the package documentation if the organism is not listed'}, 'quote': 'consult the package documentation if the build is not listed'}
- {'parameter': 'summarization_using_the_abundance_tpm_values', 'scientific_meaning': 'Controls whether gene-level summaries are based on TPM (Transcripts Per Million) abundance values rather than raw counts', 'typical_values': ['true (use TPM for summarization)', 'false (use raw counts)'], 'context_guidance': {'scenario_normalized_analysis': 'Use TPM=true for abundance-based analysis or when downstream tools expect normalized values', 'scenario_count_based_analysis': 'Use TPM=false for count-based differential expression analysis (e.g., DESeq2)'}}
- {'parameter': 'counts_files', 'scientific_meaning': 'Input transcript quantification files from tools like Salmon, Kallisto, or similar quantifiers', 'typical_values': ['Salmon quant.sf files', 'Kallisto abundance.tsv files', 'Other transcript quantification formats'], 'context_guidance': {'scenario_multiple_samples': 'Provide all sample quantification files for merging into single gene-level table', 'scenario_format_consistency': 'Ensure all input files use same quantification tool and format'}}

## Result Interpretation

- {'guidance': 'Output is single merged table with genes as rows and samples as columns containing gene-level abundance or count values. Verify row count matches expected number of genes in reference annotation and column count equals number of input samples.'}
- {'guidance': 'Check for missing genes or samples in output; absence may indicate annotation version mismatch or file format incompatibility. Validate that gene identifiers are consistent and recognizable by downstream analysis tools.'}
- {'guidance': 'If using TPM summarization, values should be normalized across samples. If using count summarization, raw counts should reflect transcript abundance without cross-sample normalization.'}

## Alternatives

- {'tool': 'DESeq2', 'when_to_prefer_this': 'tximport preferred when you need to merge multiple transcript quantification files into single gene-level table before downstream analysis', 'when_to_prefer_alternative': 'DESeq2 preferred for differential expression analysis; requires per-sample input format rather than merged table'}
- {'tool': 'Salmon/Kallisto direct output', 'when_to_prefer_this': 'tximport preferred when aggregation to gene-level and cross-sample merging is needed', 'when_to_prefer_alternative': 'Direct quantifier output preferred if transcript-level analysis or per-sample organization required'}

## Citations

- Soneson C, Love MI, Robinson MD. (2015). Differential analyses for RNA-seq: transcript-level estimates improve gene-level inferences. F1000Research, 4:1521. [PMID:26925227](https://pubmed.ncbi.nlm.nih.gov/26925227) doi:10.12688/f1000research.7563.2

## References

- Homepage: N/A (not provided in documentation)

<!-- biomate-cta -->
---

## Run this on BioMate

This skill is the **knowledge layer** — when, why, and how to use `tximport`. To **run this analysis on your own data** with managed compute, automated QC, and reproducible outputs, use **[BioMate](https://www.biomate.ai?ref=kb&pkg=tximport)** — free to start.

▶ **[Open `tximport` on BioMate →](https://www.biomate.ai?ref=kb&pkg=tximport)**
