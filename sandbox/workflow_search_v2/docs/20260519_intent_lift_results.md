# Intent-Anchor A/B Lift Results (n=155)

**Date:** 2026-05-19
**Source:** `evaluation/datasets/cross_domain_routing/queries.yaml`
**Library:** `sandbox/workflow_search_v2/library/workflow_intent.py`
**Anchors:** `sandbox/workflow_search_v2/data/intent_anchors.yaml` (39 entries)
**BGE:** DISABLED (local — same as baseline run)

## Headline

| Method | Top-1 HIT | % |
|---|---|---|
| BASELINE (`UnifiedWorkflowSearch.search` raw) | 100 / 155 | **64.5%** |
| **TREATMENT (+`prioritize_workflow_by_intent`)** | 119 / 155 | **76.8%** |
| Delta | +19 | **+12.3pp** |

## By domain

| Domain | n | baseline | treatment | Δ |
|---|---|---|---|---|
| drug_discovery | 17 | 8 | 8 | +0 |
| epigenomics | 17 | 13 | 14 | +1 |
| genomics | 6 | 4 | 6 | +2 |
| immunology | 6 | 6 | 6 | +0 |
| metagenomics | 13 | 8 | 9 | +1 |
| proteomics | 13 | 12 | 12 | +0 |
| rna_seq | 15 | 10 | 12 | +2 |
| single_cell | 25 | 15 | 20 | +5 |
| transcriptomics | 11 | 4 | 8 | +4 |
| variant_calling | 17 | 11 | 15 | +4 |
| virtual_cell | 15 | 9 | 9 | +0 |

## Flips to correct (19)

- **rna_006** `Run a StringTie transcript assembly on my aligned RNA-seq BAM files` → was `nf-core/rnaseq`, now `nf-core/bam_stringtie_merge`
- **rna_010** `I already have a count matrix from rnaseq. Now I want to find differen` → was `nf-core/rnaseq`, now `nf-core/differentialabundance`
- **sc_001** `Process my 10x Genomics single-cell RNA-seq FASTQ files using Cell Ran` → was `nf-core/rnaseq`, now `nf-core/scrnaseq`
- **sc_002** `Align scRNA-seq reads and generate a count matrix using STARsolo inste` → was `nf-core/rnaseq`, now `nf-core/scrnaseq`
- **sc_007** `Quality control of single-cell sequencing: filter empty droplets and d` → was `scds`, now `nf-core/scrnaseq`
- **var_001** `Call germline SNPs and indels from whole genome sequencing of a health` → was `nf-core/rnavar`, now `nf-core/sarek`
- **var_010** `Calculate tumor mutational burden (TMB) from WES of a melanoma sample` → was `CaMutQC`, now `nf-core/sarek`
- **var_011** `Annotate germline variants with ClinVar and gnomAD allele frequencies ` → was `nf-core/variantcatalogue`, now `nf-core/sarek`
- **var_012** `Run UMI consensus calling to reduce PCR duplicates before variant dete` → was `Fastq Create Umi Consensus Fgbio`, now `nf-core/sarek`
- **epi_003** `Run MACS3 peak calling on my ChIP-seq replicate samples with IgG contr` → was `Perform Chipseq Peak Calling With Macs2`, now `nf-core/chipseq`
- **meta_003** `Run DADA2 for amplicon sequence variant calling from my 16S paired-end` → was `dada2`, now `nf-core/ampliseq`
- **tx_001** `Detect fusion genes in RNA-seq from a pediatric leukemia sample using ` → was `nf-core/rnaseq`, now `nf-core/rnafusion`
- **tx_002** `Run FusionCatcher on my paired-end RNA-seq data to find oncogenic gene` → was `nf-core/rnaseq`, now `nf-core/rnafusion`
- **tx_007** `Small RNA sequencing to profile miRNA expression in serum samples` → was `Drug Moa Rnaseq`, now `nf-core/smrnaseq`
- **tx_008** `Discover novel miRNAs using MiRDeep2 and annotate isomiRs from my smal` → was `nf-core/fastq_find_mirna_mirdeep2`, now `nf-core/smrnaseq`
- **gen_002** `Call structural variants and SNPs from long Oxford Nanopore reads usin` → was `nf-core/longraredisease`, now `nf-core/nanoseq`
- **gen_004** `Hi-C sequencing to map chromatin contacts and identify topologically a` → was `UMI4Cats`, now `nf-core/hic`
- **sc_014** `Multimodal single-cell: align RNA and ATAC from 10x Multiome, call pea` → was `scShapes`, now `multiome_rna_atac`
- **sc_015** `Remove doublets from my 10x scRNA-seq data before clustering — use Dou` → was `M3Drop`, now `scrna_doublet_qc`

## Flips to wrong (0)

**None.** The intent prioritizer never demoted a correct top-1 to wrong.

## Still failing (36)

- **rna_004** `Remove ribosomal RNA contamination and trim adapters before aligning m` — expected `nf-core/rnaseq`, got `nf-core/fastq_trim_fastp_fastqc`
- **rna_013** `Identify genes upregulated in lung tissue from COVID-19 patients versu` — expected `nf-core/rnaseq`, got `oncomix`
- **rna_015** `Quantify long non-coding RNA expression from my bulk RNA-seq experimen` — expected `nf-core/lncpipe`, got `nf-core/rnaseq`
- **sc_005** `I have SmartSeq2 scRNA-seq plate data. Get expression counts per cell` — expected `nf-core/scrnaseq`, got `nf-core/rnaseq`
- **sc_008** `Run 10x Genomics 3-prime v3 single-cell RNA-seq preprocessing with ale` — expected `nf-core/scrnaseq`, got `nf-core/rnaseq`
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
- **tx_003** `Identify EML4-ALK and BCR-ABL fusion transcripts in my lung cancer RNA` — expected `nf-core/rnafusion`, got `nf-core/rnaseq`
- **tx_009** `Long non-coding RNA discovery and differential expression from my RNA-` — expected `nf-core/lncpipe`, got `Drug Moa Rnaseq`
- **tx_010** `piRNA contamination filtering in my small RNA-seq preprocessing` — expected `nf-core/smrnaseq`, got `nf-core/rnaseq`
- **dd_001** `Predict the 3D structure of my kinase using AlphaFold2 and then dock a` — expected `Structure Prediction Docking`, got `nf-core/proteinfold`
- **dd_002** `Virtual screening of 500 compounds against my GPCR homology model usin` — expected `Structure Prediction Docking`, got `Schrodinger Glide Docking`

…16 more cases.
