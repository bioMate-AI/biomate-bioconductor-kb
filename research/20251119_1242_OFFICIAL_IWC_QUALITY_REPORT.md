# Official IWC Workflows Quality Report

**Date:** 2025-11-19 12:42
**Total Workflows:** 105
**Location:** `/home/yzhang/biomate/backend/galaxy_workflows_official_iwc/`

## Quality Summary

- **High Quality (80+):** 97 workflows
- **Good Quality (60-79):** 8 workflows
- **Needs Improvement (<60):** 0 workflows

**Average Quality Score:** 89.1/100

---

## Domain Coverage

| Domain | Workflows | Avg Quality |
|--------|-----------|-------------|
| VGP-assembly-v2 | 13 | 83 |
| amplicon | 17 | 81 |
| bacterial_genomics | 3 | 100 |
| computational-chemistry | 4 | 90 |
| data-fetching | 2 | 100 |
| epigenetics | 12 | 100 |
| genome-assembly | 4 | 90 |
| genome_annotation | 4 | 95 |
| imaging | 3 | 93 |
| metabolomics | 4 | 80 |
| microbiome | 6 | 77 |
| proteomics | 6 | 77 |
| repeatmasking | 1 | 60 |
| sars-cov-2-variant-calling | 7 | 100 |
| scRNAseq | 8 | 92 |
| transcriptomics | 5 | 100 |
| variant-calling | 3 | 100 |
| virology | 3 | 93 |

---

## Top Quality Workflows (Score 100)

### ATAC-seq Analysis: Chromatin Accessibility Profiling

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 27 tools, 4 inputs
- **Description:** Complete ATAC-seq analysis pipeline for paired-end reads. Processes raw FASTQ data through adapter and bad quality removal (cutadapt), alignment (Bowtie2 end-to-end), and filtering (removes MT reads, ...

### Assembly decontamination VGP9 

- **Domain:** VGP-assembly-v2
- **License:** BSD-3-Clause
- **Creator:** Nadolina Brajuka, Delphine Lariviere 
- **Steps:** 11 tools, 7 inputs
- **Description:** Decontamination (foreign contaminants and mitochondrial sequences) of a genome assembly after the final scaffolding step. Uses NCBI FCS GX  to identify foreign contaminants and Blast to identify mitoc...

### BREW3R

- **Domain:** transcriptomics
- **License:** GPL-3.0-or-later
- **Creator:** Lucille Delisle
- **Steps:** 5 tools, 5 inputs
- **Description:** Extends 3' ends of gene annotations using BAM files (from STAR alignments) and a reference GTF. Specifically designed for 3'-biased sequencing techniques like 10X scRNA-seq or BRB-seq that primarily c...

### BigWig Replicates Averaging Workflow

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 2 tools, 2 inputs
- **Description:** Calculates average signal values across replicate BigWig files to generate a single consolidated track. Requires input file identifiers formatted as "sample_name_replicateID". The tool automatically g...

### COVID-19: consensus construction

- **Domain:** sars-cov-2-variant-calling
- **License:** MIT
- **Creator:** Wolfgang Maier
- **Steps:** 17 tools, 6 inputs
- **Description:** Build a consensus sequence from FILTER PASS variants with intrasample allele-frequency above a configurable consensus threshold.
Hard-mask regions with low coverage (but not consensus variants within ...

### COVID-19: variation analysis of ARTIC ONT data

- **Domain:** sars-cov-2-variant-calling
- **License:** MIT
- **Creator:** Wolfgang Maier
- **Steps:** 22 tools, 5 inputs
- **Description:** This workflow for ONT-sequenced ARTIC data is modeled after the alignment/variant-calling steps of the [ARTIC pipeline](https://artic.readthedocs.io/en/latest/). It performs, essentially, the same ste...

### COVID-19: variation analysis on ARTIC PE data

- **Domain:** sars-cov-2-variant-calling
- **License:** MIT
- **Creator:** Wolfgang Maier
- **Steps:** 25 tools, 8 inputs
- **Description:** The workflow for Illumina-sequenced ARTIC data builds on the RNASeq workflow for paired-end data using the same steps for mapping and variant calling, but adds extra logic for trimming ARTIC primer se...

### COVID-19: variation analysis on WGS PE data

- **Domain:** sars-cov-2-variant-calling
- **License:** MIT
- **Creator:** Wolfgang Maier
- **Steps:** 11 tools, 2 inputs
- **Description:** This workflows performs paired end read mapping with bwa-mem followed by sensitive variant calling across a wide range of AFs with lofreq

### COVID-19: variation analysis on WGS SE data

- **Domain:** sars-cov-2-variant-calling
- **License:** MIT
- **Creator:** Wolfgang Maier
- **Steps:** 9 tools, 2 inputs
- **Description:** This workflows performs single end read mapping with bowtie2 followed by sensitive variant calling across a wide range of AFs with lofreq

### COVID-19: variation analysis reporting

- **Domain:** sars-cov-2-variant-calling
- **License:** MIT
- **Creator:** Wolfgang Maier
- **Steps:** 30 tools, 6 inputs
- **Description:** This workflow takes a VCF dataset of variants produced by any of the *-variant-calling workflows in https://github.com/galaxyproject/iwc/tree/main/workflows/sars-cov-2-variant-calling and generates ta...

### CUT&RUN/CUT&TAG Analysis: Protein-DNA Interaction Mapping

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 9 tools, 6 inputs
- **Description:** Complete CUT&RUN/CUT&TAG analysis workflow for paired-end sequencing data. Processes raw FASTQ files through adapter removal (cutadapt) and alignment (Bowtie2 with dovetail option enabled). Applies qu...

### Capture Hi-C Processing: FASTQ to Balanced Cool Files

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 5 tools, 10 inputs
- **Description:** End-to-end processing of Capture Hi-C paired-end sequencing data. Transforms raw FASTQ files into balanced contact matrices using HiCUP for processing Hi-C reads (adapter trimming, mapping, filtering ...

### ChIP-seq Analysis: Paired-End Read Processing

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 7 tools, 5 inputs
- **Description:** Complete ChIP-seq analysis for paired-end sequencing data. Processes raw FASTQ files through adapter removal (fastp), alignment to reference genome (Bowtie2), and stringent quality filtering (MAPQ gre...

### ChIP-seq Analysis: Single-End Read Processing

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 7 tools, 6 inputs
- **Description:** Complete ChIP-seq analysis for single-end sequencing data. Processes raw FASTQ files through adapter removal (fastp), alignment to reference genome (Bowtie2), and quality filtering (MAPQ greater than ...

### Consensus Peak Calling for ATAC-seq and CUT&RUN Replicates

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 24 tools, 4 inputs
- **Description:** Identifies high-confidence consensus peaks from ATAC-seq or CUT&RUN replicate experiments. The workflow calls peaks on individual replicates and identifies their intersection. To control for sequencin...

### Consensus Peak Calling for ChIP-seq Paired-End Replicates

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 22 tools, 4 inputs
- **Description:** Identifies high-confidence consensus peaks from ChIP-seq paired-end replicate experiments. The workflow calls peaks on individual replicates and identifies their intersection. To control for sequencin...

### Consensus Peak Calling for ChIP-seq Single-End Replicates

- **Domain:** epigenetics
- **License:** MIT
- **Creator:** Lucille Delisle
- **Steps:** 22 tools, 4 inputs
- **Description:** Identifies high-confidence consensus peaks from ChIP-seq single-end replicate experiments. The workflow calls peaks on individual replicates and identifies their intersection. To control for sequencin...

### End-to-End Tissue Microarray Analysis

- **Domain:** imaging
- **License:** MIT
- **Creator:** Cameron Watson
- **Steps:** 10 tools, 3 inputs
- **Description:** Complete multiplex tissue image (MTI) analysis pipeline for tissue microarray (TMA) data imaged using cyclic immunofluorescence: Performs illumination correction, stitching and registration, and tissu...

### Fragment-based virtual screening using rDock for docking and SuCOS for pose scoring

- **Domain:** computational-chemistry
- **License:** MIT
- **Creator:** Simon Bray, Tim Dudgeon
- **Steps:** 11 tools, 7 inputs
- **Description:** Virtual screening of the SARS-CoV-2 main protease with rDock and pose scoring

### Functional annotation of protein sequences

- **Domain:** genome_annotation
- **License:** MIT
- **Creator:** Romane Libouban, Anthony Bretaudeau
- **Steps:** 2 tools, 1 inputs
- **Description:** This workflow uses eggNOG mapper and InterProScan for functional annotation of protein sequences.

... and 36 more

---

## Most Used Tools

- `compose_text_param/0.1.1` (61x)
- `Cut1` (53x)
- `gfastats/1.3.11+galaxy0` (50x)
- `param_value_from_file` (46x)
- `__EXTRACT_DATASET__` (43x)
- `pick_value/0.2.0` (33x)
- `tp_awk_tool/9.5+galaxy0` (30x)
- `collapse_dataset/5.1.0` (29x)
- `__FILTER_EMPTY_DATASETS__` (24x)
- `map_param_value/0.2.0` (21x)
- `Filter1` (19x)
- `__APPLY_RULES__` (16x)
- `tp_awk_tool/9.5+galaxy2` (15x)
- `scanpy_plot/1.10.2+galaxy0` (15x)
- `Add_a_column1/2.1` (15x)
- `Grep1` (14x)
- `collection_element_identifiers/0.0.2` (14x)
- `multiqc/1.27+galaxy3` (14x)
- `tp_find_and_replace/9.5+galaxy0` (13x)
- `Remove beginning1` (12x)
- `__FILTER_FAILED_DATASETS__` (12x)
- `purge_dups/1.2.6+galaxy0` (12x)
- `Grouping1` (11x)
- `snpSift_filter/4.3+t.galaxy1` (10x)
- `__FLATTEN__` (10x)
- `macs2_callpeak/2.2.9.1+galaxy0` (10x)
- `compleasm/0.2.6+galaxy3` (10x)
- `tp_awk_tool/9.3+galaxy1` (9x)
- `samtools_view/1.20+galaxy3` (9x)
- `busco/5.8.0+galaxy1` (9x)

---

## Complete Workflow List by Domain

### Vgp Assembly V2 (13 workflows)

- ★ **PretextMap Generation from 1 or 2 haplotypes** (Score: 100)
  - Tools: 31, Inputs: 11
- ★ **Genome Assembly from Hifi reads with HiC phasing - VGP4** (Score: 100)
  - Tools: 57, Inputs: 14
- ★ **Assembly decontamination VGP9 ** (Score: 100)
  - Tools: 11, Inputs: 7
- ★ **K-mer profiling and reads statistics VGP1** (Score: 80)
  - Tools: 13, Inputs: 5
- ★ **Purge duplicate contigs from a diploid assembly VGP6** (Score: 80)
  - Tools: 46, Inputs: 12
- ★ **Scaffolding with Hi-C data VGP8** (Score: 80)
  - Tools: 62, Inputs: 11
- ★ **kmer-profiling-hifi-trio-VGP2** (Score: 80)
  - Tools: 11, Inputs: 5
- ★ **Purging duplicates in one haplotype VGP6b** (Score: 80)
  - Tools: 36, Inputs: 13
- ★ **Mitogenome Assembly VGP0** (Score: 80)
  - Tools: 5, Inputs: 5
- ★ **Genome Assembly with Pacbio Hifi reads and Trio data for phasing - VGP5** (Score: 80)
  - Tools: 44, Inputs: 17
- ★ **Scaffolding-BioNano-VGP7** (Score: 80)
  - Tools: 12, Inputs: 4
- ★ **Genome Assembly from Hifi reads - VGP3** (Score: 80)
  - Tools: 42, Inputs: 12
- ○ **Generate Nx and Size plots for multiple assemblies** (Score: 60)
  - Tools: 14, Inputs: 1

### Amplicon (17 workflows)

- ★ **MAPseq to ampvis2** (Score: 100)
  - Tools: 9, Inputs: 2
- ★ **MGnify's amplicon pipeline v5.0 - rRNA prediction** (Score: 100)
  - Tools: 43, Inputs: 2
- ★ **MGnify amplicon summary tables** (Score: 100)
  - Tools: 10, Inputs: 3
- ★ **Taxonomic abundance summary tables for a specified taxonomic rank** (Score: 100)
  - Tools: 8, Inputs: 2
- ★ **dada2 amplicon analysis pipeline - for paired end data** (Score: 80)
  - Tools: 14, Inputs: 5
- ★ **MGnify's amplicon pipeline v5.0 - ITS** (Score: 80)
  - Tools: 26, Inputs: 2
- ★ **MGnify's amplicon pipeline v5.0 - Quality control SE** (Score: 80)
  - Tools: 14, Inputs: 8
- ★ **MGnify's amplicon pipeline v5.0** (Score: 80)
  - Tools: 8, Inputs: 21
- ★ **MGnify's amplicon pipeline v5.0 - Quality control PE** (Score: 80)
  - Tools: 17, Inputs: 12
- ★ **QIIME2 Ib: multiplexed data (paired-end)** (Score: 80)
  - Tools: 4, Inputs: 6
- ★ **QIIME2 Ia: multiplexed data (single-end)** (Score: 80)
  - Tools: 4, Inputs: 5
- ★ **QIIME2 VI: Diversity metrics and estimations** (Score: 80)
  - Tools: 12, Inputs: 5
- ★ **QIIME2 IIb: Denoising (sequence quality control) and feature table creation (paired-end)** (Score: 80)
  - Tools: 4, Inputs: 6
- ★ **QIIME2 IIa: Denoising (sequence quality control) and feature table creation (single-end)** (Score: 80)
  - Tools: 4, Inputs: 4
- ○ **QIIME2 Id: Demultiplexed data (paired-end)** (Score: 60)
  - Tools: 5, Inputs: 1
- ○ **QIIME2 Ic: Demultiplexed data (single-end)** (Score: 60)
  - Tools: 5, Inputs: 1
- ○ **QIIME2-III-V-Phylogeny-Rarefaction-Taxonomic-Analysis** (Score: 60)
  - Tools: 0, Inputs: 7

### Bacterial_Genomics (3 workflows)

- ★ **bacterial_genome_annotation** (Score: 100)
  - Tools: 6, Inputs: 4
- ★ **amr_gene_detection** (Score: 100)
  - Tools: 5, Inputs: 6
- ★ **Post-Assembly Quality Control and Contamination Check for Bacterial Genomes** (Score: 100)
  - Tools: 14, Inputs: 7

### Computational Chemistry (4 workflows)

- ★ **Fragment-based virtual screening using rDock for docking and SuCOS for pose scoring** (Score: 100)
  - Tools: 11, Inputs: 7
- ★ **dcTMD calculations with GROMACS** (Score: 100)
  - Tools: 21, Inputs: 14
- ★ **MMGBSA calculations with GROMACS** (Score: 80)
  - Tools: 17, Inputs: 10
- ★ **Create GRO and TOP complex files** (Score: 80)
  - Tools: 9, Inputs: 5

### Data Fetching (2 workflows)

- ★ **Parallel Accession Download** (Score: 100)
  - Tools: 4, Inputs: 1
- ★ **sra_manifest_to_concatenated_fastqs_parallel** (Score: 100)
  - Tools: 13, Inputs: 3

### Epigenetics (12 workflows)

- ★ **Capture Hi-C Processing: FASTQ to Balanced Cool Files** (Score: 100)
  - Tools: 5, Inputs: 10
- ★ **Hi-C Format Conversion: Juicer Medium to Cooler Files** (Score: 100)
  - Tools: 3, Inputs: 4
- ★ **Hi-C Processing: FASTQ to Balanced Cool Files** (Score: 100)
  - Tools: 2, Inputs: 8
- ★ **Hi-C Data Processing: FASTQ to Valid Interaction Pairs** (Score: 100)
  - Tools: 4, Inputs: 5
- ★ **BigWig Replicates Averaging Workflow** (Score: 100)
  - Tools: 2, Inputs: 2
- ★ **ATAC-seq Analysis: Chromatin Accessibility Profiling** (Score: 100)
  - Tools: 27, Inputs: 4
- ★ **CUT&RUN/CUT&TAG Analysis: Protein-DNA Interaction Mapping** (Score: 100)
  - Tools: 9, Inputs: 6
- ★ **ChIP-seq Analysis: Paired-End Read Processing** (Score: 100)
  - Tools: 7, Inputs: 5
- ★ **ChIP-seq Analysis: Single-End Read Processing** (Score: 100)
  - Tools: 7, Inputs: 6
- ★ **Consensus Peak Calling for ChIP-seq Paired-End Replicates** (Score: 100)
  - Tools: 22, Inputs: 4
- ★ **Consensus Peak Calling for ATAC-seq and CUT&RUN Replicates** (Score: 100)
  - Tools: 24, Inputs: 4
- ★ **Consensus Peak Calling for ChIP-seq Single-End Replicates** (Score: 100)
  - Tools: 22, Inputs: 4

### Genome Assembly (4 workflows)

- ★ **Raw Read Quality and Contamination Control For Genome Assembly** (Score: 100)
  - Tools: 8, Inputs: 4
- ★ **Genome assembly with Flye** (Score: 100)
  - Tools: 4, Inputs: 1
- ★ **Assembly polishing with long reads** (Score: 80)
  - Tools: 8, Inputs: 3
- ★ **Bacterial Genome Assembly using Shovill** (Score: 80)
  - Tools: 5, Inputs: 2

### Genome_Annotation (4 workflows)

- ★ **lncRNAs annotation workflow** (Score: 100)
  - Tools: 5, Inputs: 4
- ★ **Genome annotation with Helixer** (Score: 100)
  - Tools: 7, Inputs: 3
- ★ **Functional annotation of protein sequences** (Score: 100)
  - Tools: 2, Inputs: 1
- ★ **Genome annotation with Maker** (Score: 80)
  - Tools: 8, Inputs: 6

### Imaging (3 workflows)

- ★ **Segmentation and counting of cell nuclei in fluorescence microscopy images** (Score: 100)
  - Tools: 7, Inputs: 1
- ★ **End-to-End Tissue Microarray Analysis** (Score: 100)
  - Tools: 10, Inputs: 3
- ★ **Multiplex Tissue Microarray Analysis** (Score: 80)
  - Tools: 19, Inputs: 4

### Metabolomics (4 workflows)

- ★ **Mass spectrometry: GCMS with metaMS** (Score: 80)
  - Tools: 7, Inputs: 2
- ★ **QCxMS Spectra Prediction from SDF** (Score: 80)
  - Tools: 4, Inputs: 1
- ★ **Mass spectrometry: LC-MS preprocessing with XCMS** (Score: 80)
  - Tools: 12, Inputs: 2
- ★ **Molecular formula assignment and recalibration with MFAssignR package.** (Score: 80)
  - Tools: 9, Inputs: 1

### Microbiome (6 workflows)

- ★ **Metagenome-Assembled Genomes (MAGs) generation** (Score: 100)
  - Tools: 36, Inputs: 18
- ★ **Pathogen Detection PathoGFAIR Samples Aggregation and Visualisation** (Score: 80)
  - Tools: 60, Inputs: 10
- ★ **Gene-based Pathogen Identification** (Score: 80)
  - Tools: 15, Inputs: 1
- ★ **Allele-based Pathogen Identification** (Score: 80)
  - Tools: 23, Inputs: 3
- ○ **Taxonomy Profiling and Visualization with Krona** (Score: 60)
  - Tools: 3, Inputs: 2
- ○ **Nanopore Preprocessing** (Score: 60)
  - Tools: 25, Inputs: 3

### Proteomics (6 workflows)

- ★ **MetaProSIP OpenMS 2.8** (Score: 80)
  - Tools: 8, Inputs: 6
- ★ **Generate a Clinical Metaproteomics Database** (Score: 80)
  - Tools: 3, Inputs: 4
- ★ **Clinical Metaproteomics Data Interpretation** (Score: 80)
  - Tools: 6, Inputs: 5
- ★ **Clinical Metaproteomics Discovery Workflow** (Score: 80)
  - Tools: 24, Inputs: 3
- ★ **Clinical Metaproteomics Verification Workflow** (Score: 80)
  - Tools: 19, Inputs: 4
- ○ **Clinical Metaproteomics Quantitation** (Score: 60)
  - Tools: 7, Inputs: 3

### Repeatmasking (1 workflows)

- ○ **Repeat masking with RepeatModeler and RepeatMasker** (Score: 60)
  - Tools: 2, Inputs: 1

### Sars Cov 2 Variant Calling (7 workflows)

- ★ **COVID-19: variation analysis on WGS PE data** (Score: 100)
  - Tools: 11, Inputs: 2
- ★ **COVID-19: variation analysis on WGS SE data** (Score: 100)
  - Tools: 9, Inputs: 2
- ★ **COVID-19: variation analysis reporting** (Score: 100)
  - Tools: 30, Inputs: 6
- ★ **COVID-19: variation analysis on ARTIC PE data** (Score: 100)
  - Tools: 25, Inputs: 8
- ★ **COVID-19: variation analysis of ARTIC ONT data** (Score: 100)
  - Tools: 22, Inputs: 5
- ★ **COVID-19: consensus construction** (Score: 100)
  - Tools: 17, Inputs: 6
- ★ **SARS-CoV-2 Illumina Amplicon pipeline - iVar based** (Score: 100)
  - Tools: 16, Inputs: 5

### Scrnaseq (8 workflows)

- ★ **Single-Cell RNA-seq Preprocessing: 10X Genomics CellPlex Multiplexed Samples** (Score: 100)
  - Tools: 4, Inputs: 8
- ★ **Single-Cell RNA-seq Preprocessing: 10X Genomics v3 to Seurat and Scanpy Compatible Format** (Score: 100)
  - Tools: 3, Inputs: 5
- ★ **RNA Velocity Analysis: Velocyto for 10X Data with Filtered Barcodes** (Score: 100)
  - Tools: 1, Inputs: 3
- ★ **Single-Cell Mixture Analysis: baredSC 2D Log-Normalized Models** (Score: 100)
  - Tools: 2, Inputs: 7
- ★ **Single-Cell Mixture Analysis: baredSC 1D Log-Normalized Models** (Score: 100)
  - Tools: 2, Inputs: 4
- ★ **Single-Cell RNA-seq Analysis: Scanpy Preprocessing and Clustering** (Score: 80)
  - Tools: 55, Inputs: 13
- ★ **Single-Cell Pseudobulk Differential Expression Analysis with edgeR** (Score: 80)
  - Tools: 13, Inputs: 8
- ★ **RNA Velocity Analysis: Velocyto for 10X Data from Bundled Output** (Score: 80)
  - Tools: 1, Inputs: 3

### Transcriptomics (5 workflows)

- ★ **RNA-Seq Analysis: Paired-End Read Processing and Quantification** (Score: 100)
  - Tools: 12, Inputs: 11
- ★ **BREW3R** (Score: 100)
  - Tools: 5, Inputs: 5
- ★ **RNA-Seq Differential Expression Analysis with Visualization** (Score: 100)
  - Tools: 19, Inputs: 6
- ★ **Gene Ontology and KEGG Pathway Enrichment Analysis** (Score: 100)
  - Tools: 5, Inputs: 5
- ★ **RNA-Seq Analysis: Single-End Read Processing and Quantification** (Score: 100)
  - Tools: 11, Inputs: 10

### Variant Calling (3 workflows)

- ★ **Paired end variant calling in haploid system** (Score: 100)
  - Tools: 13, Inputs: 3
- ★ **Generic variation analysis on WGS PE data** (Score: 100)
  - Tools: 12, Inputs: 3
- ★ **Generic variation analysis reporting** (Score: 100)
  - Tools: 31, Inputs: 4

### Virology (3 workflows)

- ★ **Pox Virus Illumina Amplicon Workflow from half-genomes** (Score: 100)
  - Tools: 40, Inputs: 7
- ★ **Variant calling and consensus construction from paired end short read data of non-segmented viral genomes** (Score: 100)
  - Tools: 23, Inputs: 6
- ★ **Influenza A isolate subtyping and consensus sequence generation** (Score: 80)
  - Tools: 68, Inputs: 2

---

## Quality Scoring Criteria

Each workflow is scored on these criteria (20 points each):

1. **License** - Has a proper license (e.g., MIT)
2. **Creator ORCID** - Creator has ORCID identifier
3. **Annotation** - Meaningful description (>50 chars)
4. **Labeled Inputs** - All inputs have labels
5. **Labeled Outputs** - Workflow outputs are labeled

