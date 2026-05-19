# Intent-Anchor A/B Lift Results (n=155)

**Date:** 2026-05-19
**Source:** `evaluation/datasets/cross_domain_routing/queries.yaml`
**Library:** `sandbox/workflow_search_v2/library/workflow_intent.py`
**Anchors:** `sandbox/workflow_search_v2/data/intent_anchors.yaml` (24 entries)
**BGE:** DISABLED (local — same as baseline run)

## Headline

| Method | Top-1 HIT | % |
|---|---|---|
| BASELINE (`UnifiedWorkflowSearch.search` raw) | 108 / 155 | **69.7%** |
| **TREATMENT (+`prioritize_workflow_by_intent`)** | 116 / 155 | **74.8%** |
| Delta | +8 | **+5.2pp** |

## By domain

| Domain | n | baseline | treatment | Δ |
|---|---|---|---|---|
| drug_discovery | 17 | 8 | 8 | +0 |
| epigenomics | 17 | 14 | 14 | +0 |
| genomics | 6 | 4 | 5 | +1 |
| immunology | 6 | 6 | 6 | +0 |
| metagenomics | 13 | 8 | 9 | +1 |
| proteomics | 13 | 12 | 12 | +0 |
| rna_seq | 15 | 8 | 9 | +1 |
| single_cell | 25 | 20 | 20 | +0 |
| transcriptomics | 11 | 8 | 9 | +1 |
| variant_calling | 17 | 11 | 15 | +4 |
| virtual_cell | 15 | 9 | 9 | +0 |

## Flips to correct (8)

- **rna_010** `I already have a count matrix from rnaseq. Now I want to find differen` → was `nf-core/rnaseq`, now `nf-core/differentialabundance`
- **var_001** `Call germline SNPs and indels from whole genome sequencing of a health` → was `nf-core/rnavar`, now `nf-core/sarek`
- **var_010** `Calculate tumor mutational burden (TMB) from WES of a melanoma sample` → was `CaMutQC`, now `nf-core/sarek`
- **var_011** `Annotate germline variants with ClinVar and gnomAD allele frequencies ` → was `nf-core/variantcatalogue`, now `nf-core/sarek`
- **var_012** `Run UMI consensus calling to reduce PCR duplicates before variant dete` → was `Fastq Create Umi Consensus Fgbio`, now `nf-core/sarek`
- **meta_003** `Run DADA2 for amplicon sequence variant calling from my 16S paired-end` → was `dada2`, now `nf-core/ampliseq`
- **tx_008** `Discover novel miRNAs using MiRDeep2 and annotate isomiRs from my smal` → was `nf-core/fastq_find_mirna_mirdeep2`, now `nf-core/smrnaseq`
- **gen_002** `Call structural variants and SNPs from long Oxford Nanopore reads usin` → was `nf-core/longraredisease`, now `nf-core/nanoseq`

## Flips to wrong (0)

**None.** The intent prioritizer never demoted a correct top-1 to wrong.

## Still failing (39)

- **rna_001** `Run standard RNA-seq analysis on my paired-end FASTQ files from a mous` — expected `nf-core/rnaseq`, got `nf-core/cutandrun`
- **rna_004** `Remove ribosomal RNA contamination and trim adapters before aligning m` — expected `nf-core/rnaseq`, got `nf-core/fastq_trim_fastp_fastqc`
- **rna_006** `Run a StringTie transcript assembly on my aligned RNA-seq BAM files` — expected `nf-core/bam_stringtie_merge`, got `Bam Stringtie Merge`
- **rna_007** `Generate BigWig coverage tracks from my RNA-seq experiment for genome ` — expected `nf-core/rnaseq`, got `CoverageView`
- **rna_012** `Strandedness is unknown for my RNA-seq libraries — auto-detect it and ` — expected `nf-core/rnaseq`, got `BUSseq`
- **rna_013** `Identify genes upregulated in lung tissue from COVID-19 patients versu` — expected `nf-core/rnaseq`, got `oncomix`
- **sc_007** `Quality control of single-cell sequencing: filter empty droplets and d` — expected `nf-core/scrnaseq`, got `scds`
- **sc_012** `Find cell types in a single-cell experiment from inflamed colon tissue` — expected `nf-core/scrnaseq`, got `LRcell`
- **var_008** `Rank and prioritize variants by pathogenicity score for a patient with` — expected `nf-core/raredisease`, got `ASSIGN`
- **var_015** `Align reads from a Sentieon-licensed server for fast germline variant ` — expected `nf-core/sarek`, got `Qtlizer`
- **epi_007** `CUT&RUN experiment profiling H3K4me3 at active promoters with very low` — expected `nf-core/cutandrun`, got `CrispRVariants`
- **epi_014** `Process TIPseq data to profile transposon insertions epigenomically at` — expected `nf-core/cutandrun`, got `CellMixS`
- **epi_015** `I ran CUT&RUN with an IgG control — now align reads and call peaks aga` — expected `nf-core/cutandrun`, got `AlpsNMR`
- **meta_005** `Classify microbial taxa in shotgun metagenomics reads using Kraken2 an` — expected `nf-core/taxprofiler`, got `nf-core/fasta_build_add_kraken2_bracken`
- **meta_006** `Run MetaPhlAn to profile microbial species abundance in clinical metag` — expected `nf-core/taxprofiler`, got `Fastq Taxonomic Profile Metaphlan`
- **meta_007** `What bacteria are present and how abundant are they in my patient's st` — expected `nf-core/taxprofiler`, got `mina`
- **meta_010** `Reconstruct individual microbial genomes from an ocean metagenome usin` — expected `nf-core/mag`, got `nf-core/taxprofiler`
- **tx_007** `Small RNA sequencing to profile miRNA expression in serum samples` — expected `nf-core/smrnaseq`, got `miQC`
- **gen_004** `Hi-C sequencing to map chromatin contacts and identify topologically a` — expected `nf-core/hic`, got `UMI4Cats`
- **dd_001** `Predict the 3D structure of my kinase using AlphaFold2 and then dock a` — expected `Structure Prediction Docking`, got `nf-core/proteinfold`

…19 more cases.
