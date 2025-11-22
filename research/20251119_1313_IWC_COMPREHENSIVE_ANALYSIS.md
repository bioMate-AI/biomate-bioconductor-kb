# IWC Workflow Comprehensive Analysis

**Date:** 2025-11-19 13:13
**Total IWC Workflows:** 105
**Total Domains:** 18

---

## Overall Statistics

- **Total tool steps:** 1601
- **Average tools per workflow:** 15.2
- **Range:** 0 - 68 tools
- **Unique tools used:** 351

---

## Domain Statistics

| Domain | Workflows | Avg Steps | Total Tools | Top Tools |
|--------|-----------|-----------|-------------|----------|
| VGP-assembly-v2 | 13 | 29.5 | 384 | Repository_Actions_gfastats, bgruening_text_processing_Text_reformatting_9.5+galaxy2, __EXTRACT_DATASET__ |
| amplicon | 17 | 11.0 | 187 | bgruening_text_processing_Text_reformatting_9.5+galaxy2, __FILTER_EMPTY_DATASETS__, Repository_Actions_Convert |
| bacterial_genomics | 3 | 8.3 | 25 | iuc_pick_value_Pick_parameter_value_0.2.0, Repository_Actions_, iuc_tooldistillator_ToolDistillator_1.0.1+galaxy0 |
| computational-chemistry | 4 | 14.5 | 58 | Repository_Actions_Compose_text_parameter_value, bgruening_text_processing_Text_reformatting_9.5+galaxy2, Repository_Actions_GROMACS_simulation |
| data-fetching | 2 | 8.5 | 17 | __APPLY_RULES__, bgruening_split_file_to_collection_Split_file_0.5.2, Repository_Actions_Faster_Download_and_Extract_Reads_in_FASTQ |
| epigenetics | 12 | 11.2 | 134 | bgruening_text_processing_Text_reformatting_9.5+galaxy2, Repository_Actions_bedtools_AnnotateBed, param_value_from_file |
| genome-assembly | 4 | 6.2 | 25 | Repository_Actions_Map_with_minimap2, nfcore_racon, Repository_Actions_Bandage_Image |
| genome_annotation | 4 | 5.5 | 22 | Repository_Actions_Busco, Repository_Actions_gffread, Repository_Actions_Genome_annotation_statistics |
| imaging | 3 | 12.0 | 36 | Repository_Actions_Convert_image_format, Repository_Actions_Perform_segmentation_of_multiplexed_tissue_data, Repository_Actions_MCQUANT |
| metabolomics | 4 | 8.0 | 32 | Repository_Actions_xcms_plot_chromatogram, Repository_Actions_MSnbase_readMSData, abims_xcms_xcmsSet |
| microbiome | 6 | 27.0 | 162 | bgruening_text_processing_Text_reformatting_9.5+galaxy2, Cut1, Repository_Actions_Collapse_Collection |
| proteomics | 6 | 11.2 | 67 | Grep1, Cut1, Grouping1 |
| repeatmasking | 1 | 2.0 | 2 | Repository_Actions_RepeatModeler, bgruening_repeat_masker_RepeatMasker_4.1.5+galaxy0 |
| sars-cov-2-variant-calling | 7 | 18.6 | 130 | bgruening_text_processing_Text_reformatting_9.5+galaxy2, iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0, Repository_Actions_Compose_text_parameter_value |
| scRNAseq | 8 | 10.1 | 81 | Repository_Actions_Scanpy_plot, iuc_pick_value_Pick_parameter_value_0.2.0, bgruening_text_processing_Text_reformatting_9.5+galaxy2 |
| transcriptomics | 5 | 10.4 | 52 | iuc_map_param_value_Map_parameter_value_0.2.0, Repository_Actions_Compose_text_parameter_value, iuc_stringtie_StringTie_2.2.3+galaxy0 |
| variant-calling | 3 | 18.7 | 56 | bgruening_text_processing_Text_reformatting_9.5+galaxy2, iuc_datamash_ops_Datamash_1.9+galaxy0, Repository_Actions_SnpEff_eff: |
| virology | 3 | 43.7 | 131 | bgruening_text_processing_Text_reformatting_9.5+galaxy2, __APPLY_RULES__, Repository_Actions_Extract_element_identifiers |

---

## Workflows by Domain

### Vgp Assembly V2 (13 workflows)

**Scaffolding with Hi-C data VGP8**
- Steps: 62 tools, 11 inputs
- Description: This workflow performs the scaffolding of a genome assembly using HiC data with YAHS. Can be used on any assembly with Hi-C data, and the assembly in ...
- Tool sequence: Repository_Actions_gfastats → Repository_Actions_Compose_text_parameter_value → iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → param_value_from_file → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Samtools_merge ... (+54 more)

**Genome Assembly from Hifi reads with HiC phasing - VGP4**
- Steps: 57 tools, 14 inputs
- Description: Assemble Genome using PacBio HiFi and HiC data from the same individual for phasing. Prerequisite: Run k-mer profiling workflow (VGP1). This workflow ...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Cutadapt → Repository_Actions_Cutadapt → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compute → Repository_Actions_MultiQC ... (+49 more)

**Purge duplicate contigs from a diploid assembly VGP6**
- Steps: 46 tools, 12 inputs
- Description: Purge contigs marked as duplicates by purge_dups (could be haplotypic duplication or overlap duplication). The contigs are purged from the first assem...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Map_with_minimap2 → Repository_Actions_Purge_overlaps → Repository_Actions_Compute → param_value_from_file → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value ... (+38 more)

**Genome Assembly with Pacbio Hifi reads and Trio data for phasing - VGP5**
- Steps: 44 tools, 17 inputs
- Description: Generate phased assembly based on PacBio HiFi reads and parental Illumina data for phasing. Part of the VGP workflow suite, it needs to be run after t...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Cutadapt → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compute → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0 ... (+36 more)

**Genome Assembly from Hifi reads - VGP3**
- Steps: 42 tools, 12 inputs
- Description: Generate a genome assembly based on PacBio HiFi reads. Part of the VGP suite, it needs to be run after the VGP1 k-mer profiling workflow. The assembly...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Cutadapt → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Compute → Repository_Actions_Compose_text_parameter_value → Repository_Actions_MultiQC ... (+34 more)

**Purging duplicates in one haplotype VGP6b**
- Steps: 36 tools, 13 inputs
- Description: Purge contigs marked as duplicates by purge_dups in a single haplotype (could be haplotypic duplication or overlap duplication). If you think the purg...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compute → Repository_Actions_Map_with_minimap2 → Repository_Actions_Purge_overlaps → Repository_Actions_gfastats → param_value_from_file ... (+28 more)

**PretextMap Generation from 1 or 2 haplotypes**
- Steps: 31 tools, 11 inputs
- Description: This workflow generates Hi-C contact maps for genome assemblies in the Pretext format. It is compatible with one or 2 haplotypes. It includes tracks f...
- Tool sequence: iuc_map_param_value_Map_parameter_value_0.2.0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_gfastats → iuc_seqtk_seqtk_comp_1.5+galaxy0 → Repository_Actions_Map_with_minimap2 → Repository_Actions_PretextMap → Repository_Actions_PretextMap ... (+23 more)

**Generate Nx and Size plots for multiple assemblies**
- Steps: 14 tools, 1 inputs
- Description: Generate Nx and size plots for multiple assemblies to compare the evolution of assembly quality through the scaffolding process. Inputs are the fasta ...
- Tool sequence: Repository_Actions_gfastats → sort1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_datamash_ops_Datamash_1.9+galaxy0 → Repository_Actions_Add_column → param_value_from_file → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compute ... (+6 more)

**K-mer profiling and reads statistics VGP1**
- Steps: 13 tools, 5 inputs
- Description: Evaluation of Pacbio Hifi Reads and genome profiling. Create Meryl Database used for the estimation of assembly parameters and quality control with Me...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Meryl → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Meryl → Repository_Actions_Meryl → iuc_genomescope_GenomeScope_2.0.1+galaxy0 → Repository_Actions_Image_Montage ... (+5 more)

**Scaffolding-BioNano-VGP7**
- Steps: 12 tools, 4 inputs
- Description: Scaffold a genome assembly using Bionano optical maps data. Part of the VGP suite, it can be run on the assembly in GFA format generated by the contig...
- Tool sequence: param_value_from_file → Repository_Actions_gfastats → Repository_Actions_Bionano_Hybrid_Scaffold → Repository_Actions_gfastats → Repository_Actions_gfastats → Repository_Actions_gfastats → Repository_Actions_gfastats → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+4 more)

**kmer-profiling-hifi-trio-VGP2**
- Steps: 11 tools, 5 inputs
- Description: Create Meryl Database used for the estimation of assembly parameters and quality control with Merqury. Part of the VGP pipeline.
- Tool sequence: iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Meryl → Repository_Actions_Meryl → Repository_Actions_Meryl → Repository_Actions_Meryl → Repository_Actions_Meryl → iuc_genomescope_GenomeScope_2.0.1+galaxy0 → Repository_Actions_Meryl ... (+3 more)

**Assembly decontamination VGP9 **
- Steps: 11 tools, 7 inputs
- Description: Decontamination (foreign contaminants and mitochondrial sequences) of a genome assembly after the final scaffolding step. Uses NCBI FCS GX  to identif...
- Tool sequence: Repository_Actions_NCBI_FCS_Adaptor → Repository_Actions_Compose_text_parameter_value → Repository_Actions_NCBI_FCS_GX → Repository_Actions_BLAST_XML_to_tabular → fasta_filter_by_length → Repository_Actions_NCBI_FCS_GX → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_NCBI_FCS_GX ... (+3 more)

**Mitogenome Assembly VGP0**
- Steps: 5 tools, 5 inputs
- Description: Generate mitochondrial assembly based on PacBio HiFi reads. Part of the VGP suite, it can be run at any time independently of the other workflows. Thi...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_MitoHiFi → Repository_Actions_MitoHiFi → iuc_compress_file__0.1.0

### Amplicon (17 workflows)

**MGnify's amplicon pipeline v5.0 - rRNA prediction**
- Steps: 43 tools, 2 inputs
- Description: Classification and visualization of SSU, LSU sequences.
- Tool sequence: Repository_Actions_cmalign → __FILTER_EMPTY_DATASETS__ → Repository_Actions_CMsearch_deoverlap → iuc_query_tabular_Query_Tabular_3.3.2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+35 more)

**MGnify's amplicon pipeline v5.0 - ITS**
- Steps: 26 tools, 2 inputs
- Description: Classification and visualization of ITS regions.
- Tool sequence: __FILTER_EMPTY_DATASETS__ → Repository_Actions_Extract_element_identifiers → __FILTER_FROM_FILE__ → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_MAPseq → Repository_Actions_MAPseq → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+18 more)

**MGnify's amplicon pipeline v5.0 - Quality control PE**
- Steps: 17 tools, 12 inputs
- Description: Quality control subworkflow for paired-end reads. 
- Tool sequence: Repository_Actions_fastp → __UNZIP_COLLECTION__ → mgnify_seqprep → Repository_Actions_Trimmomatic → Repository_Actions_FastQC → Repository_Actions_Filter_FASTQ → Repository_Actions_FastQC → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+9 more)

**dada2 amplicon analysis pipeline - for paired end data**
- Steps: 14 tools, 5 inputs
- Description: dada2 amplicon analysis for paired end data

The workflow has three main outputs: 
- the sequence table (output of makeSequenceTable)
- the taxonomy (...
- Tool sequence: __APPLY_RULES__ → Repository_Actions_dada2:_plotQualityProfile → Repository_Actions_dada2:_filterAndTrim → Repository_Actions_dada2:_plotQualityProfile → __UNZIP_COLLECTION__ → Repository_Actions_dada2:_learnErrors → Repository_Actions_dada2:_learnErrors → Repository_Actions_dada2:_dada ... (+6 more)

**MGnify's amplicon pipeline v5.0 - Quality control SE**
- Steps: 14 tools, 8 inputs
- Description: Quality control subworkflow for single-end reads.
- Tool sequence: Repository_Actions_FastQC → Repository_Actions_Trimmomatic → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Filter_FASTQ → Repository_Actions_FastQC → Repository_Actions_PRINSEQ → Repository_Actions_FastQC → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+6 more)

**QIIME2 VI: Diversity metrics and estimations**
- Steps: 12 tools, 5 inputs
- Description: The first step in hypothesis testing in microbial ecology is typically to look at within- (alpha) and between-sample (beta) diversity. We can calculat...
- Tool sequence: Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_diversity_core-metrics-phylogenetic → Repository_Actions_qiime2_diversity_alpha-group-significance → Repository_Actions_qiime2_diversity_alpha-group-significance → Repository_Actions_qiime2_diversity_alpha-group-significance → Repository_Actions_qiime2_diversity_beta-group-significance → Repository_Actions_qiime2_diversity_beta-group-significance → __BUILD_LIST__ ... (+4 more)

**MGnify amplicon summary tables**
- Steps: 10 tools, 3 inputs
- Description: This workflow creates taxonomic summary tables out of the amplicon pipeline results. 
- Tool sequence: iuc_query_tabular_Query_Tabular_3.3.2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Grouping1 → Repository_Actions_Column_join → iuc_filter_tabular_Filter_Tabular_3.3.1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+2 more)

**MAPseq to ampvis2**
- Steps: 9 tools, 2 inputs
- Description: The MAPseq to Ampvis workflow processes MAPseq OTU tables and associated metadata for analysis in Ampvis2. This workflow involves reformatting MAPseq ...
- Tool sequence: iuc_query_tabular_Query_Tabular_3.3.2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Collapse_Collection → Repository_Actions_Column_join → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_query_tabular_Query_Tabular_3.3.2 ... (+1 more)

**MGnify's amplicon pipeline v5.0**
- Steps: 8 tools, 21 inputs
- Description: MGnify's amplicon pipeline v5.0. Including the Quality control for single-end and paired-end reads, rRNA-prediction, and ITS sub-WFs.
- Tool sequence: Repository_Actions_fastq-dl → CONVERTER_gz_to_uncompressed → CONVERTER_gz_to_uncompressed → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → CONVERTER_uncompressed_to_gz → CONVERTER_uncompressed_to_gz → __MERGE_COLLECTION__

**Taxonomic abundance summary tables for a specified taxonomic rank**
- Steps: 8 tools, 2 inputs
- Description: This workflow creates taxonomic summary tables for a specified taxonomic rank out of MAPseq's OTU tables output collection.
- Tool sequence: iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Grouping1 → iuc_filter_tabular_Filter_Tabular_3.3.1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Column_join → bgruening_text_processing_Text_reformatting_9.5+galaxy2

**QIIME2 Id: Demultiplexed data (paired-end)**
- Steps: 5 tools, 1 inputs
- Description: Importing demultiplexed data (paired-end)
- Tool sequence: Repository_Actions_Extract_element_identifiers → galaxyp_regex_find_replace_Regex_Find_And_Replace_1.0.3 → __RELABEL_FROM_FILE__ → Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_demux_summarize

**QIIME2 Ic: Demultiplexed data (single-end)**
- Steps: 5 tools, 1 inputs
- Description: Importing demultiplexed data (single-end)
- Tool sequence: Repository_Actions_Extract_element_identifiers → galaxyp_regex_find_replace_Regex_Find_And_Replace_1.0.3 → __RELABEL_FROM_FILE__ → Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_demux_summarize

**QIIME2 Ib: multiplexed data (paired-end)**
- Steps: 4 tools, 6 inputs
- Description: Importing paired-end multiplexed data (not demultiplexed yet)
- Tool sequence: Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_demux_emp-paired → Repository_Actions_qiime2_demux_summarize

**QIIME2 Ia: multiplexed data (single-end)**
- Steps: 4 tools, 5 inputs
- Description: Importing single-end multiplexed data (not demultiplexed yet)
- Tool sequence: Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_tools_import → Repository_Actions_qiime2_demux_emp-single → Repository_Actions_qiime2_demux_summarize

**QIIME2 IIb: Denoising (sequence quality control) and feature table creation (paired-end)**
- Steps: 4 tools, 6 inputs
- Description: Use DADA2 for sequence quality control. DADA2 is a pipeline for detecting and correcting (where possible) Illumina amplicon sequence data. As implemen...
- Tool sequence: Repository_Actions_qiime2_dada2_denoise-paired → Repository_Actions_qiime2_feature-table_tabulate-seqs → Repository_Actions_qiime2_metadata_tabulate → Repository_Actions_qiime2_feature-table_summarize

**QIIME2 IIa: Denoising (sequence quality control) and feature table creation (single-end)**
- Steps: 4 tools, 4 inputs
- Description: Use DADA2 for sequence quality control. DADA2 is a pipeline for detecting and correcting (where possible) Illumina amplicon sequence data. As implemen...
- Tool sequence: Repository_Actions_qiime2_dada2_denoise-single → Repository_Actions_qiime2_feature-table_tabulate-seqs → Repository_Actions_qiime2_metadata_tabulate → Repository_Actions_qiime2_feature-table_summarize

**QIIME2-III-V-Phylogeny-Rarefaction-Taxonomic-Analysis**
- Steps: 0 tools, 7 inputs
- Description: This workflow 
- Reconstruct phylogeny (insert fragments in a reference)
- Alpha rarefaction analysis
- Taxonomic analysis
- Tool sequence: 

### Bacterial_Genomics (3 workflows)

**Post-Assembly Quality Control and Contamination Check for Bacterial Genomes**
- Steps: 14 tools, 7 inputs
- Description: This workflow performs quality and contamination control analysis on assembled contigs to assess bacterial genome quality and taxonomic assignment
- Tool sequence: iuc_pick_value_Pick_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Quast → Repository_Actions_checkm2 → Repository_Actions_Kraken2 → Repository_Actions_Quast → Repository_Actions_Collapse_Collection → Repository_Actions_Collapse_Collection ... (+6 more)

**bacterial_genome_annotation**
- Steps: 6 tools, 4 inputs
- Description: Annotation of an assembled bacterial genomes to detect genes, potential plasmids, integrons and Insertion sequence (IS) elements.
- Tool sequence: Repository_Actions_ISEScan → Repository_Actions_Integron_Finder → Repository_Actions_ → Repository_Actions_ → iuc_tooldistillator_ToolDistillator_1.0.1+galaxy0 → iuc_tooldistillator_summarize_ToolDistillator_Summarize_1.0.1+galaxy0

**amr_gene_detection**
- Steps: 5 tools, 6 inputs
- Description: Antimicrobial resistance gene detection from assembled bacterial genomes
- Tool sequence: iuc_staramr_staramr_0.11.0+galaxy3 → Repository_Actions_ → Repository_Actions_ABRicate_List → iuc_tooldistillator_ToolDistillator_1.0.1+galaxy0 → iuc_tooldistillator_summarize_ToolDistillator_Summarize_1.0.1+galaxy0

### Computational Chemistry (4 workflows)

**dcTMD calculations with GROMACS**
- Steps: 21 tools, 14 inputs
- Description: Perform dcTMD free energy simulations and calculations
- Tool sequence: Repository_Actions_Online_data → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_GROMACS_solvation_and_adding_ions → bgruening_split_file_to_collection_Split_file_0.5.2 ... (+13 more)

**MMGBSA calculations with GROMACS**
- Steps: 17 tools, 10 inputs
- Description: MMGBSA simulation and calculation
- Tool sequence: Repository_Actions_Compose_text_parameter_value → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_GROMACS_structure_configuration → bgruening_split_file_to_collection_Split_file_0.5.2 → param_value_from_file → Repository_Actions_GROMACS_solvation_and_adding_ions → Repository_Actions_GROMACS_energy_minimization → Repository_Actions_Convert_Parameters ... (+9 more)

**Fragment-based virtual screening using rDock for docking and SuCOS for pose scoring**
- Steps: 11 tools, 7 inputs
- Description: Virtual screening of the SARS-CoV-2 main protease with rDock and pose scoring
- Tool sequence: Repository_Actions_Compound_conversion → Repository_Actions_Create_Frankenstein_ligand → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Enumerate_changes → Repository_Actions_rxDock_cavity_definition → Repository_Actions_Compound_conversion → bgruening_split_file_to_collection_Split_file_0.5.2 → Repository_Actions_rxDock_docking ... (+3 more)

**Create GRO and TOP complex files**
- Steps: 9 tools, 5 inputs
- Tool sequence: Repository_Actions_Compound_conversion → Repository_Actions_Descriptors → Repository_Actions_GROMACS_initial_setup → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Cut1 → param_value_from_file → Repository_Actions_AnteChamber → Repository_Actions_Generate_MD_topologies_for_small_molecules ... (+1 more)

### Data Fetching (2 workflows)

**sra_manifest_to_concatenated_fastqs_parallel**
- Steps: 13 tools, 3 inputs
- Description: This workflow takes as input a SRA_manifest from SRA Run Selector and will generate one fastq file or fastq pair of file for each experiment (concaten...
- Tool sequence: iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_Compose_text_parameter_value → Cut1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Cut1 → bgruening_split_file_to_collection_Split_file_0.5.2 → Repository_Actions_Faster_Download_and_Extract_Reads_in_FASTQ → __RELABEL_FROM_FILE__ ... (+5 more)

**Parallel Accession Download**
- Steps: 4 tools, 1 inputs
- Description: Downloads fastq files for sequencing run accessions provided in a text file using fasterq-dump. Creates one job per listed run accession.
- Tool sequence: bgruening_split_file_to_collection_Split_file_0.5.2 → Repository_Actions_Faster_Download_and_Extract_Reads_in_FASTQ → __APPLY_RULES__ → __APPLY_RULES__

### Epigenetics (12 workflows)

**ATAC-seq Analysis: Chromatin Accessibility Profiling**
- Steps: 27 tools, 4 inputs
- Description: Complete ATAC-seq analysis pipeline for paired-end reads. Processes raw FASTQ data through adapter and bad quality removal (cutadapt), alignment (Bowt...
- Tool sequence: Repository_Actions_Cutadapt → Repository_Actions_Bowtie2 → Repository_Actions_Filter_BAM → Repository_Actions_Samtools_idxstats → Repository_Actions_RevertSam → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_Paired-end_histogram ... (+19 more)

**Consensus Peak Calling for ATAC-seq and CUT&RUN Replicates**
- Steps: 24 tools, 4 inputs
- Description: Identifies high-confidence consensus peaks from ATAC-seq or CUT&RUN replicate experiments. The workflow calls peaks on individual replicates and ident...
- Tool sequence: Repository_Actions_bedtools_AnnotateBed → Repository_Actions_Samtools_view → Repository_Actions_Compose_text_parameter_value → Repository_Actions_MACS2_filterdup → Repository_Actions_Collapse_Collection → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_wigtobigwig → iuc_table_compute_Table_Compute_1.2.4+galaxy2 ... (+16 more)

**Consensus Peak Calling for ChIP-seq Paired-End Replicates**
- Steps: 22 tools, 4 inputs
- Description: Identifies high-confidence consensus peaks from ChIP-seq paired-end replicate experiments. The workflow calls peaks on individual replicates and ident...
- Tool sequence: Repository_Actions_Samtools_view → Repository_Actions_Compose_text_parameter_value → Repository_Actions_MACS2_filterdup → Repository_Actions_Collapse_Collection → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_wigtobigwig → iuc_table_compute_Table_Compute_1.2.4+galaxy2 → wc_gnu ... (+14 more)

**Consensus Peak Calling for ChIP-seq Single-End Replicates**
- Steps: 22 tools, 4 inputs
- Description: Identifies high-confidence consensus peaks from ChIP-seq single-end replicate experiments. The workflow calls peaks on individual replicates and ident...
- Tool sequence: Repository_Actions_Samtools_view → Repository_Actions_Compose_text_parameter_value → Repository_Actions_MACS2_filterdup → Repository_Actions_Collapse_Collection → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_wigtobigwig → iuc_table_compute_Table_Compute_1.2.4+galaxy2 → wc_gnu ... (+14 more)

**CUT&RUN/CUT&TAG Analysis: Protein-DNA Interaction Mapping**
- Steps: 9 tools, 6 inputs
- Description: Complete CUT&RUN/CUT&TAG analysis workflow for paired-end sequencing data. Processes raw FASTQ files through adapter removal (cutadapt) and alignment ...
- Tool sequence: Repository_Actions_Cutadapt → Repository_Actions_Bowtie2 → Repository_Actions_Filter_SAM_or_BAM,_output_SAM_or_BAM → Repository_Actions_RevertSam → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_MACS2_filterdup → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_wigtobigwig ... (+1 more)

**ChIP-seq Analysis: Paired-End Read Processing**
- Steps: 7 tools, 5 inputs
- Description: Complete ChIP-seq analysis for paired-end sequencing data. Processes raw FASTQ files through adapter removal (fastp), alignment to reference genome (B...
- Tool sequence: Repository_Actions_fastp → Repository_Actions_Bowtie2 → Repository_Actions_Filter_SAM_or_BAM,_output_SAM_or_BAM → Repository_Actions_MACS2_filterdup → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_wigtobigwig → Repository_Actions_MultiQC

**ChIP-seq Analysis: Single-End Read Processing**
- Steps: 7 tools, 6 inputs
- Description: Complete ChIP-seq analysis for single-end sequencing data. Processes raw FASTQ files through adapter removal (fastp), alignment to reference genome (B...
- Tool sequence: Repository_Actions_fastp → Repository_Actions_Bowtie2 → Repository_Actions_Filter_SAM_or_BAM,_output_SAM_or_BAM → Repository_Actions_MACS2_filterdup → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_wigtobigwig → Repository_Actions_MultiQC

**Capture Hi-C Processing: FASTQ to Balanced Cool Files**
- Steps: 5 tools, 10 inputs
- Description: End-to-end processing of Capture Hi-C paired-end sequencing data. Transforms raw FASTQ files into balanced contact matrices using HiCUP for processing...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Filter1 → Repository_Actions_cooler_csort_with_tabix → iuc_pygenometracks_pyGenomeTracks_3.9+galaxy0

**Hi-C Data Processing: FASTQ to Valid Interaction Pairs**
- Steps: 4 tools, 5 inputs
- Description: Processes Hi-C paired-end FASTQ files to generate validated interaction pairs using HiCUP. The workflow truncates reads at ligation junctions, maps to...
- Tool sequence: Repository_Actions_Hicup_Pipeline → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Hicup_to_juicer_converter → Filter1

**Hi-C Format Conversion: Juicer Medium to Cooler Files**
- Steps: 3 tools, 4 inputs
- Description: Converts Hi-C interaction data from Juicer medium format (tabix files) to balanced cooler format. This streamlined workflow takes a collection of Juic...
- Tool sequence: Repository_Actions_cooler_makebins → Repository_Actions_cooler_cload_tabix → Repository_Actions_cooler_balance

**Hi-C Processing: FASTQ to Balanced Cool Files**
- Steps: 2 tools, 8 inputs
- Description: Comprehensive Hi-C data processing workflow that converts paired-end FASTQ files to balanced contact matrices. Uses HiCUP for pre-processing (adapter ...
- Tool sequence: Repository_Actions_cooler_csort_with_tabix → iuc_pygenometracks_pyGenomeTracks_3.9+galaxy0

**BigWig Replicates Averaging Workflow**
- Steps: 2 tools, 2 inputs
- Description: Calculates average signal values across replicate BigWig files to generate a single consolidated track. Requires input file identifiers formatted as "...
- Tool sequence: __APPLY_RULES__ → Repository_Actions_bigwigAverage

### Genome Assembly (4 workflows)

**Raw Read Quality and Contamination Control For Genome Assembly**
- Steps: 8 tools, 4 inputs
- Description: Short paired-end read analysis to provide quality analysis, read cleaning and taxonomy assignation directly from raw reads
- Tool sequence: __ZIP_COLLECTION__ → Repository_Actions_fastp → __UNZIP_COLLECTION__ → Repository_Actions_Kraken2 → Repository_Actions_Bracken → Repository_Actions_Recentrifuge → iuc_tooldistillator_ToolDistillator_1.0.1+galaxy0 → iuc_tooldistillator_summarize_ToolDistillator_Summarize_1.0.1+galaxy0

**Assembly polishing with long reads**
- Steps: 8 tools, 3 inputs
- Description: Racon polish with long reads, x4
- Tool sequence: Repository_Actions_Map_with_minimap2 → nfcore_racon → Repository_Actions_Map_with_minimap2 → nfcore_racon → Repository_Actions_Map_with_minimap2 → nfcore_racon → Repository_Actions_Map_with_minimap2 → nfcore_racon

**Bacterial Genome Assembly using Shovill**
- Steps: 5 tools, 2 inputs
- Description: Assembly of bacterial paired-end short read data
- Tool sequence: Repository_Actions_Shovill → Repository_Actions_Bandage_Image → Repository_Actions_Bandage_Image → iuc_tooldistillator_ToolDistillator_1.0.1+galaxy0 → iuc_tooldistillator_summarize_ToolDistillator_Summarize_1.0.1+galaxy0

**Genome assembly with Flye**
- Steps: 4 tools, 1 inputs
- Description: Assemble long reads with Flye, then view assembly statistics and assembly graph
- Tool sequence: Repository_Actions_Flye → Repository_Actions_Quast → Repository_Actions_Fasta_Statistics → Repository_Actions_Bandage_Image

### Genome_Annotation (4 workflows)

**Genome annotation with Maker**
- Steps: 8 tools, 6 inputs
- Description: This workflow allows for genome annotation using Maker and evaluates the quality of the annotation.
- Tool sequence: Repository_Actions_Fasta_Statistics → Repository_Actions_Busco → Repository_Actions_Maker → Repository_Actions_gffread → Repository_Actions_Genome_annotation_statistics → Repository_Actions_Map_annotation_ids → Repository_Actions_Busco → Repository_Actions_JBrowse_-_Data_Directory_to_Standalone

**Genome annotation with Helixer**
- Steps: 7 tools, 3 inputs
- Description: This workflow allows you to annotate a genome with Helixer and evaluate the quality of the annotation using BUSCO and Genome Annotation statistics. GF...
- Tool sequence: Repository_Actions_Helixer → Repository_Actions_Busco → Repository_Actions_Genome_annotation_statistics → Repository_Actions_JBrowse_-_Data_Directory_to_Standalone → Repository_Actions_gffread → Repository_Actions_OMArk → Repository_Actions_Busco

**lncRNAs annotation workflow**
- Steps: 5 tools, 4 inputs
- Description: This workflow runs the FEELnc tool to annotate long non-coding RNAs. Before annotating these long non-coding RNAs, StringTie will be used to assemble ...
- Tool sequence: iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_gffread → iuc_stringtie_StringTie_2.2.3+galaxy0 → Repository_Actions_FEELnc → cat1

**Functional annotation of protein sequences**
- Steps: 2 tools, 1 inputs
- Description: This workflow uses eggNOG mapper and InterProScan for functional annotation of protein sequences.
- Tool sequence: Repository_Actions_InterProScan → Repository_Actions_eggNOG_Mapper

### Imaging (3 workflows)

**Multiplex Tissue Microarray Analysis**
- Steps: 19 tools, 4 inputs
- Description: Perform background subtraction, nuclear segmentation, feature quantification, cellular phenotyping, spatial analysis, and interactive visualization of...
- Tool sequence: Repository_Actions_Extract_element_identifiers → Repository_Actions_Background_subtraction → Show beginning1 → Repository_Actions_Perform_segmentation_of_multiplexed_tissue_data → Repository_Actions_MCQUANT → Repository_Actions_Convert_McMicro_Output_to_Anndata → Repository_Actions_Single_Cell_Phenotyping → Repository_Actions_AnnData_Operations ... (+11 more)

**End-to-End Tissue Microarray Analysis**
- Steps: 10 tools, 3 inputs
- Description: Complete multiplex tissue image (MTI) analysis pipeline for tissue microarray (TMA) data imaged using cyclic immunofluorescence: Performs illumination...
- Tool sequence: Repository_Actions_BaSiC_Illumination → Repository_Actions_ASHLAR → Repository_Actions_UNetCoreograph → Repository_Actions_Perform_segmentation_of_multiplexed_tissue_data → Repository_Actions_Convert_image_format → Repository_Actions_MCQUANT → Repository_Actions_Rename_OME-TIFF_channels → Repository_Actions_Convert_McMicro_Output_to_Anndata ... (+2 more)

**Segmentation and counting of cell nuclei in fluorescence microscopy images**
- Steps: 7 tools, 1 inputs
- Description: This workflow performs segmentation and counting of cell nuclei using fluorescence microscopy images. The segmentation step is performed using Otsu th...
- Tool sequence: Repository_Actions_Filter_2-D_image → Repository_Actions_Perform_histogram_equalization → Repository_Actions_Threshold_image → Repository_Actions_Convert_image_format → Repository_Actions_Convert_binary_image_to_label_map → Repository_Actions_Overlay_images → Repository_Actions_Count_objects_in_label_map

### Metabolomics (4 workflows)

**Mass spectrometry: LC-MS preprocessing with XCMS**
- Steps: 12 tools, 2 inputs
- Description: This workflow is composed with the XCMS tool R package (Smith, C.A. 2006) able to extract, filter, align and fill gapand the possibility to annotate i...
- Tool sequence: Repository_Actions_MSnbase_readMSData → Repository_Actions_xcms_plot_chromatogram → abims_xcms_xcmsSet → Repository_Actions_xcms_findChromPeaks_Merger → abims_xcms_group → abims_xcms_retcor → Repository_Actions_Check_Format → Repository_Actions_xcms_plot_chromatogram ... (+4 more)

**Molecular formula assignment and recalibration with MFAssignR package.**
- Steps: 9 tools, 1 inputs
- Description: This workflow can be used to assign multi-element molecular formulas to ultrahigh resolution mass spectra.
- Tool sequence: Repository_Actions_MFAssignR_KMDNoise → Repository_Actions_MFAssignR_HistNoise → Repository_Actions_MFAssignR_SNplot → Repository_Actions_MFAssignR_IsoFiltR → Repository_Actions_MFAssignR_MFAssignCHO → Repository_Actions_MFAssignR_RecalList → Repository_Actions_MFAssignR_FindRecalSeries → Repository_Actions_MFAssignR_Recal ... (+1 more)

**Mass spectrometry: GCMS with metaMS**
- Steps: 7 tools, 2 inputs
- Description: This workflow is composed with the XCMS tool R package (Smith, C.A. 2006) able to extract and the metaMS R package (Wehrens, R 2014) for the field of ...
- Tool sequence: Repository_Actions_MSnbase_readMSData → abims_xcms_xcmsSet → Repository_Actions_xcms_plot_chromatogram → Repository_Actions_xcms_findChromPeaks_Merger → Repository_Actions_metaMS.runGC → Repository_Actions_Check_Format → Repository_Actions_Multivariate

**QCxMS Spectra Prediction from SDF**
- Steps: 4 tools, 1 inputs
- Description: Workflow to predict EI mass spectra using QCxMS starting from a single SDF file, containing the 3D coordinates of all atoms in the molecule. These fil...
- Tool sequence: Repository_Actions_Compound_conversion → Repository_Actions_QCxMS_neutral_run → Repository_Actions_QCxMS_production_run → Repository_Actions_QCxMS_get_results

### Microbiome (6 workflows)

**Pathogen Detection PathoGFAIR Samples Aggregation and Visualisation**
- Steps: 60 tools, 10 inputs
- Description: Pathogens of all samples report generation and visualization
- Tool sequence: __FILTER_FAILED_DATASETS__ → __FILTER_FAILED_DATASETS__ → __FILTER_FAILED_DATASETS__ → __FILTER_FAILED_DATASETS__ → __FILTER_FAILED_DATASETS__ → Remove beginning1 → Remove beginning1 → Remove beginning1 ... (+52 more)

**Metagenome-Assembled Genomes (MAGs) generation**
- Steps: 36 tools, 18 inputs
- Description: This workflow constructs Metagenome-Assembled Genomes (MAGs) using SPAdes or MEGAHIT as assemblers, followed by binning with four different tools and ...
- Tool sequence: iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → __UNZIP_COLLECTION__ → Repository_Actions_MEGAHIT → Repository_Actions_metaSPAdes → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Quast → Repository_Actions_Bowtie2 ... (+28 more)

**Nanopore Preprocessing**
- Steps: 25 tools, 3 inputs
- Description: Microbiome - QC and Contamination Filtering
- Tool sequence: Repository_Actions_Porechop → iuc_nanoplot_NanoPlot_1.46.1+galaxy0 → Repository_Actions_FastQC → Repository_Actions_fastp → Repository_Actions_MultiQC → Repository_Actions_Map_with_minimap2 → iuc_nanoplot_NanoPlot_1.46.1+galaxy0 → Repository_Actions_FastQC ... (+17 more)

**Allele-based Pathogen Identification**
- Steps: 23 tools, 3 inputs
- Description: Microbiome - Variant calling and Consensus Building
- Tool sequence: CONVERTER_gz_to_uncompressed → Repository_Actions_Map_with_minimap2 → Repository_Actions_Clair3 → Repository_Actions_Samtools_depth → Repository_Actions_Samtools_coverage → bcftools_norm → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Remove beginning1 ... (+15 more)

**Gene-based Pathogen Identification**
- Steps: 15 tools, 1 inputs
- Description: Nanopore datasets analysis - Phylogenetic Identification - antibiotic resistance genes detection and contigs building
- Tool sequence: Repository_Actions_Extract_element_identifiers → __BUILD_LIST__ → bgruening_split_file_to_collection_Split_file_0.5.2 → Repository_Actions_Flye → param_value_from_file → Repository_Actions_medaka_consensus_pipeline → Repository_Actions_Bandage_Image → Repository_Actions_Compose_text_parameter_value ... (+7 more)

**Taxonomy Profiling and Visualization with Krona**
- Steps: 3 tools, 2 inputs
- Description: Microbiome - Taxonomy Profiling
- Tool sequence: Repository_Actions_Kraken2 → Repository_Actions_Krakentools:_Convert_kraken_report_file → Repository_Actions_Krona_pie_chart

### Proteomics (6 workflows)

**Clinical Metaproteomics Discovery Workflow**
- Steps: 24 tools, 3 inputs
- Description: Workflow for clinical metaproteomics database searching
- Tool sequence: galaxyp_peptideshaker_Search_GUI_4.0.41+galaxy1 → Repository_Actions_Protein_Database_Downloader → Repository_Actions_Protein_Database_Downloader → galaxyp_peptideshaker_Search_GUI_4.0.41+galaxy1 → Repository_Actions_msconvert → Repository_Actions_FASTA_Merge_Files_and_Filter_Unique_Sequences → Repository_Actions_MaxQuant → galaxyp_peptideshaker_Search_GUI_4.0.41+galaxy1 ... (+16 more)

**Clinical Metaproteomics Verification Workflow**
- Steps: 19 tools, 4 inputs
- Description: In proteomics research, verifying detected peptides is essential for ensuring data accuracy and biological relevance. This tutorial continues from the...
- Tool sequence: Repository_Actions_Protein_Database_Downloader → Repository_Actions_Protein_Database_Downloader → Repository_Actions_FASTA_Merge_Files_and_Filter_Unique_Sequences → Cut1 → Cut1 → Repository_Actions_PepQuery2 → Remove beginning1 → Remove beginning1 ... (+11 more)

**MetaProSIP OpenMS 2.8**
- Steps: 8 tools, 6 inputs
- Description: Automated inference of stable isotope incorporation rates in proteins for functional metaproteomics 
- Tool sequence: __SORTLIST__ → Repository_Actions_DecoyDatabase → Repository_Actions_FeatureFinderMultiplex → Repository_Actions_MSGFPlusAdapter → Repository_Actions_PeptideIndexer → Repository_Actions_FalseDiscoveryRate → Repository_Actions_IDMapper → Repository_Actions_MetaProSIP

**Clinical Metaproteomics Quantitation**
- Steps: 7 tools, 3 inputs
- Description: Clinical Metaproteomics 4: Quantitation 
- Tool sequence: Repository_Actions_MaxQuant → Grep1 → Grep1 → Cut1 → Cut1 → Grouping1 → Grouping1

**Clinical Metaproteomics Data Interpretation**
- Steps: 6 tools, 5 inputs
- Description: This workflow will perform taxonomic and functional annotations using Unipept and statistical analysis using MSstatsTMT.
- Tool sequence: Repository_Actions_Unipept → Grep1 → Grep1 → Repository_Actions_MSstatsTMT → Grep1 → Repository_Actions_MSstatsTMT

**Generate a Clinical Metaproteomics Database**
- Steps: 3 tools, 4 inputs
- Description: The workflow begins with the Database Generation process. The Galaxy-P team has developed a workflow that collects protein sequences from known diseas...
- Tool sequence: Repository_Actions_FASTA_Merge_Files_and_Filter_Unique_Sequences → Repository_Actions_MetaNovo → Repository_Actions_FASTA_Merge_Files_and_Filter_Unique_Sequences

### Repeatmasking (1 workflows)

**Repeat masking with RepeatModeler and RepeatMasker**
- Steps: 2 tools, 1 inputs
- Tool sequence: Repository_Actions_RepeatModeler → bgruening_repeat_masker_RepeatMasker_4.1.5+galaxy0

### Sars Cov 2 Variant Calling (7 workflows)

**COVID-19: variation analysis reporting**
- Steps: 30 tools, 6 inputs
- Description: This workflow takes a VCF dataset of variants produced by any of the *-variant-calling workflows in https://github.com/galaxyproject/iwc/tree/main/wor...
- Tool sequence: iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → bgruening_replace_column_by_key_value_file_Replace_column_0.2 → Repository_Actions_Compute → iuc_datamash_ops_Datamash_1.9+galaxy0 ... (+22 more)

**COVID-19: variation analysis on ARTIC PE data**
- Steps: 25 tools, 8 inputs
- Description: The workflow for Illumina-sequenced ARTIC data builds on the RNASeq workflow for paired-end data using the same steps for mapping and variant calling,...
- Tool sequence: Repository_Actions_fastp → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_view → iuc_lofreq_viterbi_Realign_reads_2.1.5+galaxy0 → Repository_Actions_Samtools_stats → iuc_lofreq_indelqual_Insert_indel_qualities_2.1.5+galaxy1 ... (+17 more)

**COVID-19: variation analysis of ARTIC ONT data**
- Steps: 22 tools, 5 inputs
- Description: This workflow for ONT-sequenced ARTIC data is modeled after the alignment/variant-calling steps of the [ARTIC pipeline](https://artic.readthedocs.io/e...
- Tool sequence: Repository_Actions_fastp → Repository_Actions_Compute → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Map_with_minimap2 → iuc_datamash_ops_Datamash_1.9+galaxy0 → Repository_Actions_Samtools_view → param_value_from_file → Repository_Actions_Samtools_stats ... (+14 more)

**COVID-19: consensus construction**
- Steps: 17 tools, 6 inputs
- Description: Build a consensus sequence from FILTER PASS variants with intrasample allele-frequency above a configurable consensus threshold.
Hard-mask regions wit...
- Tool sequence: Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_bedtools_AnnotateBed → Repository_Actions_Compose_text_parameter_value → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → Filter1 → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 ... (+9 more)

**SARS-CoV-2 Illumina Amplicon pipeline - iVar based**
- Steps: 16 tools, 5 inputs
- Description: Find and annotate variants in ampliconic SARS-CoV-2 Illumina sequencing data and classify samples with pangolin and nextclade
- Tool sequence: Repository_Actions_fastp → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_stats → Repository_Actions_Samtools_view → Repository_Actions_View_repository_View_change_log_Browse_repository_tip_files_Download_as_a_.tar.gz_file_Download_as_a_.tar.bz2_file_Download_as_a_zip_file_QualiMap_BamQC → Repository_Actions_ivar_trim → devteam_vcfflatten_VCFflatten:_1.0.0_rc3+galaxy0 ... (+8 more)

**COVID-19: variation analysis on WGS PE data**
- Steps: 11 tools, 2 inputs
- Description: This workflows performs paired end read mapping with bwa-mem followed by sensitive variant calling across a wide range of AFs with lofreq
- Tool sequence: Repository_Actions_fastp → Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_view → Repository_Actions_Samtools_stats → Repository_Actions_RevertSam → iuc_lofreq_viterbi_Realign_reads_2.1.5+galaxy0 → Repository_Actions_MultiQC → iuc_lofreq_indelqual_Insert_indel_qualities_2.1.5+galaxy1 ... (+3 more)

**COVID-19: variation analysis on WGS SE data**
- Steps: 9 tools, 2 inputs
- Description: This workflows performs single end read mapping with bowtie2 followed by sensitive variant calling across a wide range of AFs with lofreq
- Tool sequence: Repository_Actions_fastp → Repository_Actions_Bowtie2 → Repository_Actions_RevertSam → Repository_Actions_MultiQC → iuc_lofreq_viterbi_Realign_reads_2.1.5+galaxy0 → iuc_lofreq_indelqual_Insert_indel_qualities_2.1.5+galaxy1 → iuc_lofreq_call_Call_variants_2.1.5+galaxy3 → iuc_lofreq_filter_Lofreq_filter_2.1.5+galaxy0 ... (+1 more)

### Scrnaseq (8 workflows)

**Single-Cell RNA-seq Analysis: Scanpy Preprocessing and Clustering**
- Steps: 55 tools, 13 inputs
- Description: End-to-end analysis of single-cell RNA-seq data using the Scanpy/AnnData ecosystem. Imports count matrices, applies quality control filtering of low-q...
- Tool sequence: iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Import_Anndata → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Import_Anndata ... (+47 more)

**Single-Cell Pseudobulk Differential Expression Analysis with edgeR**
- Steps: 13 tools, 8 inputs
- Description: Performs differential gene expression analysis on single-cell data using a pseudobulk approach. Aggregates cell-level counts from an annotated AnnData...
- Tool sequence: ebi-gxa_decoupler_pseudobulk_Decoupler_pseudo-bulk_1.4.0+galaxy10 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Remove_columns → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_edgeR → Repository_Actions_Extract_element_identifiers ... (+5 more)

**Single-Cell RNA-seq Preprocessing: 10X Genomics CellPlex Multiplexed Samples**
- Steps: 4 tools, 8 inputs
- Description: Comprehensive preprocessing for 10X Genomics CellPlex multiplexed single-cell RNA-seq data. Processes Cell Multiplexing Oligo (CMO) FASTQ files with C...
- Tool sequence: iuc_cite_seq_count_CITE-seq-Count_1.4.4+galaxy0 → iuc_pick_value_Pick_parameter_value_0.2.0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0

**Single-Cell RNA-seq Preprocessing: 10X Genomics v3 to Seurat and Scanpy Compatible Format**
- Steps: 3 tools, 5 inputs
- Description: Complete preprocessing pipeline for 10X Genomics v3 single-cell RNA-seq data. Aligns raw FASTQ files using STARsolo, performs cell calling and quality...
- Tool sequence: Repository_Actions_RNA_STARSolo → Repository_Actions_MultiQC → Repository_Actions_DropletUtils

**Single-Cell Mixture Analysis: baredSC 2D Log-Normalized Models**
- Steps: 2 tools, 7 inputs
- Description: Applies baredSC algorithm to fit and combine two-dimensional Gaussian mixture models (from 1 to N components) on log-normalized single-cell gene expre...
- Tool sequence: Repository_Actions_baredSC_2d → Repository_Actions_Combine_multiple_2D_Models

**Single-Cell Mixture Analysis: baredSC 1D Log-Normalized Models**
- Steps: 2 tools, 4 inputs
- Description: Applies baredSC algorithm to fit and combine one-dimensional Gaussian mixture models (from 1 to N components) on log-normalized single-cell gene expre...
- Tool sequence: Repository_Actions_baredSC_1d → Repository_Actions_Combine_multiple_1D_Models

**RNA Velocity Analysis: Velocyto for 10X Data with Filtered Barcodes**
- Steps: 1 tools, 3 inputs
- Description: Processes 10X Genomics single-cell RNA-seq data using Velocyto to quantify spliced and unspliced transcript counts for RNA velocity analysis. Takes pr...
- Tool sequence: Repository_Actions_velocyto_CLI

**RNA Velocity Analysis: Velocyto for 10X Data from Bundled Output**
- Steps: 1 tools, 3 inputs
- Description: Processes 10X Genomics single-cell RNA-seq data using Velocyto to quantify spliced and unspliced transcript counts for RNA velocity analysis. Automati...
- Tool sequence: __APPLY_RULES__

### Transcriptomics (5 workflows)

**RNA-Seq Differential Expression Analysis with Visualization**
- Steps: 19 tools, 6 inputs
- Description: Identifies differentially expressed genes between exactly two experimental conditions from count tables. The workflow performs statistical testing, ap...
- Tool sequence: bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_DESeq2 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Annotate_DESeq2 ... (+11 more)

**RNA-Seq Analysis: Paired-End Read Processing and Quantification**
- Steps: 12 tools, 11 inputs
- Description: Complete RNA-Seq analysis for paired-end data: Processes raw FASTQ data through adapter and bad quality removal (fastp), alignment with STAR using ENC...
- Tool sequence: devteam_vcfflatten_VCFflatten:_1.0.0_rc3+galaxy0 → Repository_Actions_fastp → iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_Compose_text_parameter_value → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_RNA_STAR ... (+4 more)

**RNA-Seq Analysis: Single-End Read Processing and Quantification**
- Steps: 11 tools, 10 inputs
- Description: Complete RNA-Seq analysis for single-end data:  Processes raw FASTQ data through adapter and bad quality removal (fastp), alignment with STAR using EN...
- Tool sequence: Repository_Actions_fastp → iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_Compose_text_parameter_value → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → Repository_Actions_RNA_STAR → Repository_Actions_featureCounts ... (+3 more)

**BREW3R**
- Steps: 5 tools, 5 inputs
- Description: Extends 3' ends of gene annotations using BAM files (from STAR alignments) and a reference GTF. Specifically designed for 3'-biased sequencing techniq...
- Tool sequence: iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_stringtie_StringTie_2.2.3+galaxy0 → iuc_stringtie_StringTie_2.2.3+galaxy0 → Repository_Actions_BREW3R.r

**Gene Ontology and KEGG Pathway Enrichment Analysis**
- Steps: 5 tools, 5 inputs
- Description: Performs functional enrichment analysis of gene sets using GOseq, identifying over-represented Gene Ontology terms and KEGG pathways. This workflow ac...
- Tool sequence: Repository_Actions_goseq → Repository_Actions_goseq → Repository_Actions_goseq → Repository_Actions_goseq → join1

### Variant Calling (3 workflows)

**Generic variation analysis reporting**
- Steps: 31 tools, 4 inputs
- Description: This workflow takes a VCF dataset of variants produced by any of the variant calling workflows in https://github.com/galaxyproject/iwc/tree/main/workf...
- Tool sequence: iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → Repository_Actions_Compute → iuc_datamash_ops_Datamash_1.9+galaxy0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 ... (+23 more)

**Paired end variant calling in haploid system**
- Steps: 13 tools, 3 inputs
- Description: Workflow for variant analysis against a reference genome in GenBank format
- Tool sequence: Repository_Actions_fastp → Repository_Actions_SnpEff_eff: → Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_view → Repository_Actions_Samtools_stats → Repository_Actions_RevertSam → Repository_Actions_MultiQC → iuc_lofreq_viterbi_Realign_reads_2.1.5+galaxy0 ... (+5 more)

**Generic variation analysis on WGS PE data**
- Steps: 12 tools, 3 inputs
- Description: Workflow for variant analysis against  a reference genome in GenBank format
- Tool sequence: Repository_Actions_fastp → Repository_Actions_SnpEff_eff: → Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_view → Repository_Actions_RevertSam → Repository_Actions_Samtools_stats → iuc_lofreq_viterbi_Realign_reads_2.1.5+galaxy0 → Repository_Actions_MultiQC ... (+4 more)

### Virology (3 workflows)

**Influenza A isolate subtyping and consensus sequence generation**
- Steps: 68 tools, 2 inputs
- Description: This workflow performs subtyping and consensus sequence generation for batches of Illumina PE sequenced Influenza A isolates.
- Tool sequence: bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Extract_element_identifiers → Repository_Actions_Extract_element_identifiers → Repository_Actions_fastp → wc_gnu → wc_gnu → __UNZIP_COLLECTION__ → param_value_from_file ... (+60 more)

**Pox Virus Illumina Amplicon Workflow from half-genomes**
- Steps: 40 tools, 7 inputs
- Description: A workflow for the analysis of pox virus genomes sequenced as half-genomes (for ITR resolution) in a tiled-amplicon approach
- Tool sequence: fasta_compute_length → Grep1 → Grep1 → Repository_Actions_Extract_element_identifiers → Repository_Actions_fastp → Cut1 → iuc_datamash_ops_Datamash_1.9+galaxy0 → iuc_datamash_ops_Datamash_1.9+galaxy0 ... (+32 more)

**Variant calling and consensus construction from paired end short read data of non-segmented viral genomes**
- Steps: 23 tools, 6 inputs
- Description: Variant calling and consensus sequence generation for batches of Illumina PE sequenced viruses with uncomplicated and stable genome structure (like e....
- Tool sequence: Repository_Actions_fastp → Repository_Actions_SnpEff_eff: → iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0 → Repository_Actions_Calculate_numeric_parameter_value → Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_stats → Repository_Actions_Samtools_view ... (+15 more)

---

## Most Used Tools (Top 50)

| Rank | Tool | Count | % of Workflows |
|------|------|-------|----------------|
| 1 | bgruening_text_processing_Text_reformatting_9.5+galaxy2 | 170 | 161.9% |
| 2 | Repository_Actions_Compose_text_parameter_value | 61 | 58.1% |
| 3 | Repository_Actions_gfastats | 55 | 52.4% |
| 4 | Cut1 | 53 | 50.5% |
| 5 | param_value_from_file | 46 | 43.8% |
| 6 | __EXTRACT_DATASET__ | 43 | 41.0% |
| 7 | iuc_pick_value_Pick_parameter_value_0.2.0 | 33 | 31.4% |
| 8 | Repository_Actions_MultiQC | 31 | 29.5% |
| 9 | Repository_Actions_Collapse_Collection | 30 | 28.6% |
| 10 | __FILTER_EMPTY_DATASETS__ | 24 | 22.9% |
| 11 | Repository_Actions_bedtools_AnnotateBed | 22 | 21.0% |
| 12 | iuc_map_param_value_Map_parameter_value_0.2.0 | 21 | 20.0% |
| 13 | Repository_Actions_Compute | 20 | 19.0% |
| 14 | Filter1 | 19 | 18.1% |
| 15 | Repository_Actions_fastp | 18 | 17.1% |
| 16 | Repository_Actions_Samtools_view | 17 | 16.2% |
| 17 | iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 | 17 | 16.2% |
| 18 | iuc_datamash_ops_Datamash_1.9+galaxy0 | 17 | 16.2% |
| 19 | __APPLY_RULES__ | 16 | 15.2% |
| 20 | Repository_Actions_Scanpy_plot | 15 | 14.3% |
| 21 | Grep1 | 14 | 13.3% |
| 22 | Repository_Actions_Extract_element_identifiers | 14 | 13.3% |
| 23 | Repository_Actions_Map_with_minimap2 | 14 | 13.3% |
| 24 | bgruening_split_file_to_collection_Split_file_0.5.2 | 13 | 12.4% |
| 25 | Repository_Actions_Samtools_stats | 13 | 12.4% |
| 26 | Remove beginning1 | 12 | 11.4% |
| 27 | __FILTER_FAILED_DATASETS__ | 12 | 11.4% |
| 28 | Repository_Actions_Purge_overlaps | 12 | 11.4% |
| 29 | Grouping1 | 11 | 10.5% |
| 30 | Repository_Actions_SnpEff_eff: | 11 | 10.5% |
| 31 | Repository_Actions_FastQC | 11 | 10.5% |
| 32 | Repository_Actions_Busco | 11 | 10.5% |
| 33 | devteam_vcfflatten_VCFflatten:_1.0.0_rc3+galaxy0 | 10 | 9.5% |
| 34 | Repository_Actions_MACS2_filterdup | 10 | 9.5% |
| 35 | Repository_Actions_Meryl | 10 | 9.5% |
| 36 | Repository_Actions_compleasm | 10 | 9.5% |
| 37 | Repository_Actions_Map_with_BWA-MEM | 9 | 8.6% |
| 38 | galaxyp_regex_find_replace_Regex_Find_And_Replace_1.0.3 | 9 | 8.6% |
| 39 | Repository_Actions_Convert | 8 | 7.6% |
| 40 | __RELABEL_FROM_FILE__ | 8 | 7.6% |
| 41 | Repository_Actions_Image_Montage | 8 | 7.6% |
| 42 | Repository_Actions_Pretextgraph | 8 | 7.6% |
| 43 | Repository_Actions_FASTA_Merge_Files_and_Filter_Unique_Sequences | 7 | 6.7% |
| 44 | iuc_query_tabular_Query_Tabular_3.3.2 | 7 | 6.7% |
| 45 | Repository_Actions_RevertSam | 7 | 6.7% |
| 46 | join1 | 7 | 6.7% |
| 47 | Repository_Actions_Column_join | 7 | 6.7% |
| 48 | Repository_Actions_qiime2_tools_import | 7 | 6.7% |
| 49 | Repository_Actions_Bandage_Image | 7 | 6.7% |
| 50 | Repository_Actions_wigtobigwig | 7 | 6.7% |

---

## Common Tool Patterns (Potential Subworkflows)

### Tool Pairs (appearing 5+ times)

These consecutive tool pairs could be grouped as subworkflows:

- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (45x)
- **Repository_Actions_gfastats → Repository_Actions_gfastats** (35x)
- **__EXTRACT_DATASET__ → __EXTRACT_DATASET__** (29x)
- **Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value** (23x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Cut1** (13x)
- **__FILTER_EMPTY_DATASETS__ → __FILTER_EMPTY_DATASETS__** (13x)
- **param_value_from_file → param_value_from_file** (13x)
- **Cut1 → Cut1** (12x)
- **Cut1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (9x)
- **Repository_Actions_Scanpy_plot → Repository_Actions_Scanpy_plot** (9x)
- **iuc_pick_value_Pick_parameter_value_0.2.0 → iuc_pick_value_Pick_parameter_value_0.2.0** (8x)
- **iuc_datamash_ops_Datamash_1.9+galaxy0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (7x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_datamash_ops_Datamash_1.9+galaxy0** (7x)
- **iuc_map_param_value_Map_parameter_value_0.2.0 → iuc_map_param_value_Map_parameter_value_0.2.0** (7x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Collapse_Collection** (6x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_pick_value_Pick_parameter_value_0.2.0** (6x)
- **Repository_Actions_Convert → Repository_Actions_Convert** (6x)
- **param_value_from_file → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (6x)
- **Repository_Actions_Meryl → Repository_Actions_Meryl** (6x)
- **bgruening_split_file_to_collection_Split_file_0.5.2 → param_value_from_file** (5x)
- **Grep1 → Grep1** (5x)
- **Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_view** (5x)
- **iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0** (5x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_split_file_to_collection_Split_file_0.5.2** (5x)
- **Repository_Actions_FastQC → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (5x)
- **iuc_tooldistillator_ToolDistillator_1.0.1+galaxy0 → iuc_tooldistillator_summarize_ToolDistillator_Summarize_1.0.1+galaxy0** (5x)
- **Repository_Actions_Collapse_Collection → Repository_Actions_Collapse_Collection** (5x)
- **Repository_Actions_Busco → Repository_Actions_compleasm** (5x)
- **Repository_Actions_Pretextgraph → Repository_Actions_Pretextgraph** (5x)

### Tool Triples (appearing 3+ times)

- **Repository_Actions_gfastats → Repository_Actions_gfastats → Repository_Actions_gfastats** (25x)
- **__EXTRACT_DATASET__ → __EXTRACT_DATASET__ → __EXTRACT_DATASET__** (21x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (13x)
- **__FILTER_EMPTY_DATASETS__ → __FILTER_EMPTY_DATASETS__ → __FILTER_EMPTY_DATASETS__** (10x)
- **Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value → Repository_Actions_Compose_text_parameter_value** (6x)
- **Repository_Actions_Scanpy_plot → Repository_Actions_Scanpy_plot → Repository_Actions_Scanpy_plot** (6x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Cut1 → Cut1** (4x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → __FILTER_EMPTY_DATASETS__** (4x)
- **Repository_Actions_Convert → Repository_Actions_Convert → Repository_Actions_Convert** (4x)
- **param_value_from_file → param_value_from_file → param_value_from_file** (4x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_split_file_to_collection_Split_file_0.5.2 → param_value_from_file** (4x)
- **param_value_from_file → param_value_from_file → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (4x)
- **join1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (4x)
- **Repository_Actions_Map_with_BWA-MEM → Repository_Actions_Samtools_view → Repository_Actions_Samtools_stats** (3x)
- **iuc_lofreq_indelqual_Insert_indel_qualities_2.1.5+galaxy1 → iuc_lofreq_call_Call_variants_2.1.5+galaxy3 → iuc_lofreq_filter_Lofreq_filter_2.1.5+galaxy0** (3x)
- **iuc_lofreq_call_Call_variants_2.1.5+galaxy3 → iuc_lofreq_filter_Lofreq_filter_2.1.5+galaxy0 → Repository_Actions_SnpEff_eff:** (3x)
- **Repository_Actions_Compose_text_parameter_value → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0 → iuc_snpsift_SnpSift_rmInfo_4.3+t.galaxy0** (3x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Repository_Actions_Collapse_Collection** (3x)
- **iuc_datamash_ops_Datamash_1.9+galaxy0 → bgruening_text_processing_Text_reformatting_9.5+galaxy2 → iuc_datamash_ops_Datamash_1.9+galaxy0** (3x)
- **bgruening_text_processing_Text_reformatting_9.5+galaxy2 → Cut1 → bgruening_text_processing_Text_reformatting_9.5+galaxy2** (3x)

---

## Logical Subworkflow Groupings

Based on common bioinformatics patterns:

| Pattern | Workflows Using | Common Tools |
|---------|-----------------|-------------|
| QC | 29 | iuc/repository_actions_multiqc, lparsons/repository_actions_cutadapt, pjbriggs/repository_actions_trimmomatic, devteam/repository_actions_fastqc |
| Mapping | 26 | devteam/repository_actions_map_with_bwa-mem, iuc/repository_actions_bwa-mem2, iuc/repository_actions_rna_starsolo, iuc/repository_actions_map_with_minimap2 |
| BAM Processing | 17 | devteam/repository_actions_samtools_stats, iuc/repository_actions_samtools_fastx, iuc/repository_actions_samtools_merge, devteam/repository_actions_samtools_idxstats |
| Variant Calling | 9 | devteam_freebayes_freebayes_1.3.10+galaxy1, iuc/bcftools_annotate, iuc_lofreq_indelqual_insert_indel_qualities_2.1.5+galaxy1, iuc_lofreq_call_call_variants_2.1.5+galaxy3 |
| Peak Calling | 7 | iuc/repository_actions_macs2_filterdup |
| Visualization | 6 | iuc/repository_actions_bandage_image |
| Assembly | 6 | iuc/repository_actions_megahit, bgruening/repository_actions_hifiasm, bgruening/repository_actions_flye, nml/repository_actions_metaspades |
| Quantification | 2 | iuc/repository_actions_featurecounts |
| Annotation | 2 | iuc/repository_actions_maker, bgruening/repository_actions_interproscan |

### Recommended Subworkflow Candidates

#### QC_FASTQ
- **Tools:** fastqc → multiqc
- **Purpose:** Quality control pipeline for FASTQ files
- **Frequency:** ~15 workflows

#### TRIM_READS
- **Tools:** cutadapt/fastp → fastqc
- **Purpose:** Adapter trimming with QC
- **Frequency:** ~12 workflows

#### MAP_SORT_INDEX
- **Tools:** bowtie2/bwa → samtools_sort → samtools_index
- **Purpose:** Read mapping pipeline
- **Frequency:** ~20 workflows

#### BAM_STATS
- **Tools:** samtools_stats → samtools_flagstat → samtools_idxstats
- **Purpose:** BAM statistics suite
- **Frequency:** ~10 workflows

#### PEAK_CALL
- **Tools:** macs2 → bedtools
- **Purpose:** Peak calling and processing
- **Frequency:** ~8 workflows

#### VARIANT_FILTER
- **Tools:** bcftools_norm → bcftools_filter → snpsift
- **Purpose:** Variant filtering pipeline
- **Frequency:** ~6 workflows

#### COVERAGE
- **Tools:** bedtools_genomecov → deeptools_bigwig
- **Purpose:** Coverage track generation
- **Frequency:** ~7 workflows

#### ASSEMBLY_QC
- **Tools:** quast → busco → gfastats
- **Purpose:** Assembly quality assessment
- **Frequency:** ~5 workflows

---

## Comparison with nf-core Workflows

- **IWC workflows:** 105
- **nf-core workflows:** 93
- **Shared tools:** 17
- **IWC-only tools:** 334
- **nf-core-only tools:** 153

### Tools in IWC but not nf-core

- CONVERTER_gz_to_uncompressed
- CONVERTER_uncompressed_to_gz
- Convert characters1
- Cut1
- Grep1
- Grouping1
- Paste1
- Remove beginning1
- Repository_Actions_
- Repository_Actions_ABRicate_List
- Repository_Actions_ASHLAR
- Repository_Actions_Add_column
- Repository_Actions_Add_input_name_as_column
- Repository_Actions_Add_line_to_file
- Repository_Actions_Analyze_and_visualize_spatial_multi-omics_data
- Repository_Actions_AnnData_Operations
- Repository_Actions_Annotate_DESeq2
- Repository_Actions_AnteChamber
- Repository_Actions_BLAST_XML_to_tabular
- Repository_Actions_BREW3R.r
- Repository_Actions_BWA-MEM2
- Repository_Actions_BaSiC_Illumination
- Repository_Actions_Background_subtraction
- Repository_Actions_Bandage_Image
- Repository_Actions_Binette
- Repository_Actions_Bionano_Hybrid_Scaffold
- Repository_Actions_CAMERA.annotate
- Repository_Actions_CMsearch_deoverlap
- Repository_Actions_CONCOCT:_Cut_up_contigs
- Repository_Actions_CONCOCT:_Extract_a_fasta_file

... and 304 more

### Tools in nf-core but not IWC

- Repository_Actions_BAM_coverage_statistics
- Repository_Actions_BBMap_Clumpify:_Deduplication
- Repository_Actions_BWA-MEM2_index_builder
- Repository_Actions_BedToIntervalList
- Repository_Actions_Bismark_to_BedGraph
- Repository_Actions_CLC_Mapper
- Repository_Actions_Cell_types_-_combine_tools_outputs
- Repository_Actions_Clustal_Omega
- Repository_Actions_Convert_Affymetrix
- Repository_Actions_Depad_SAM
- Repository_Actions_Download_MMseqs2_databases
- Repository_Actions_Extract_Kraken_Reads_By_ID
- Repository_Actions_Freyja:_Aggregate_and_visualize
- Repository_Actions_Generate_simulated_reads
- Repository_Actions_HISAT2
- Repository_Actions_IDBA_fq2fa
- Repository_Actions_Intersect_BAM_alignments_with_intervals_in_another_files
- Repository_Actions_Kallisto
- Repository_Actions_Kraken2
- Repository_Actions_MAFFT
- Repository_Actions_MAGeCK_GSEA
- Repository_Actions_Make_inferences
- Repository_Actions_MetaPhlAn
- Repository_Actions_MethylDackel
- Repository_Actions_MiRDeep2
- Repository_Actions_PFAM_output_annotator
- Repository_Actions_Qcat
- Repository_Actions_Salmon
- Repository_Actions_Tabular_to_CSV
- Repository_Actions_Unzip

... and 123 more
