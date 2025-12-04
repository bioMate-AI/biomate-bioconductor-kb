# Comprehensive Tool List for BioMate Docker Image

**Date**: December 2, 2025
**Docker Image**: `biomate/biotools:comprehensive`
**Status**: Build Successful

---

## Overview

This document provides a detailed inventory of all tools included in the BioMate comprehensive Docker image, organized by source (Biomni, Galaxy, Nextflow) and category.

### Tool Statistics Summary

**IMPORTANT TERMINOLOGY:**
- **Tool**: A software package to install (e.g., `samtools`, `scanpy`)
- **Tool_function**: An atomic operation within a tool (e.g., `samtools_view`, `scanpy.pp.normalize_total`)

| Source | Tool_Functions | Parent Libraries/Tools | Notes |
|--------|----------------|------------------------|-------|
| **Biomni** | 241 | 46 | Python (109), R (58), CLI (74) |
| **Galaxy IWC** | 334 | 219 | From 510 raw tool_id entries |
| **Nextflow nf-core** | 1,651 | 755 | From nf-core/modules repository |
| **TOTAL** | **2,226** | - | All tool_functions |
| **Overlapping libraries** | - | **15** | Core bioinformatics tools |

**Docker Installations:**
- `biomate/biomni-tools:latest` (6.51GB): **344 Python packages** + R packages + CLI tools
- Biomni workflows: **122 workflows** using the 241 tool-functions

### Tools Present in All Three Sources
`bcftools`, `bedtools`, `bowtie2`, `bwa`, `cutadapt`, `deseq2`, `fastqc`, `iqtree`, `kraken2`, `macs2`, `mafft`, `samtools`, `scanpy`, `snpeff`, `trimmomatic`

### Data File
`/home/yzhang/biomate/Biomni/biomni_galaxy/tool_function_index.csv` - Complete mapping of source → tool → tool_function → type (2,226 rows)

---

## 1. Core Tools (In All Three Sources)

These tools appear in Galaxy, Nextflow, AND Biomni - highest priority for inclusion:

| Tool | Version | Type | Category | Installation |
|------|---------|------|----------|--------------|
| **bwa** | latest | CLI | Alignment | git clone + make |
| **bowtie2** | v2.5.3 | CLI | Alignment | git clone + make (needs simde for ARM64) |
| **samtools** | 1.21 | CLI | SAM/BAM | git clone + make (needs htslib) |
| **bedtools** | v2.31.1 | CLI | Region Analysis | git clone + make |
| **fastqc** | v0.12.1 | Java | QC | Pre-built zip |
| **mafft** | 7.526 | CLI | Alignment | Pre-built tarball |

### ARM64 Build Notes for Core Tools

```bash
# Bowtie2 requires simde library for ARM64/Apple Silicon
apt-get install libsimde-dev  # Ubuntu 22.04
git clone bowtie2
cd bowtie2
git clone https://github.com/simd-everywhere/simde.git third_party/simde
make POPCNT_CAPABILITY=0

# BWA-MEM2 may need special flags for ARM64
make -j$(nproc) || echo "BWA-MEM2 may fail on ARM64"

# STAR has ARM64 support in recent versions
# Salmon/kallisto: use pre-built binaries when available
```

---

## 2. Biomni Tools (241 Atomic Functions)

### 2.1 Python Library Functions (109)

| Library | Functions | Domain | Examples |
|---------|-----------|--------|----------|
| **Biopython (Bio)** | 18 | molecular_biology, genomics | SeqIO.read, SeqIO.write, Entrez.efetch, Phylo.read |
| **Scanpy** | 21 | genomics | pp.normalize_total, pp.log1p, tl.umap, tl.leiden |
| **OpenCV (cv2)** | 17 | bioimaging | imread, threshold, findContours, GaussianBlur |
| **scikit-image** | 18 | bioimaging | threshold_otsu, measure.label, morphology |
| **RDKit** | 12 | pharmacology | MolFromSmiles, GetMorganFingerprint |
| **COBRApy** | 6 | systems_biology | read_sbml_model, flux_variability_analysis |
| **gget** | 5 | genomics, database | search, info, seq, enrichr |
| **pandas** | 8 | data processing | DataFrame, read_csv, merge |
| **scipy** | 6 | statistics | stats.ttest_ind, optimize.minimize |
| **torch** | 4 | ML | load, save, nn.Module |

### 2.2 R Package Functions (58)

| Package | Functions | Domain | Examples |
|---------|-----------|--------|----------|
| **DESeq2** | 12 | genomics | DESeqDataSetFromMatrix, DESeq, results, vst |
| **edgeR** | 8 | genomics | DGEList, calcNormFactors, glmFit |
| **limma** | 6 | genomics | lmFit, eBayes, topTable, voom |
| **Seurat** | 10 | genomics | CreateSeuratObject, FindClusters, RunUMAP |
| **clusterProfiler** | 7 | genomics | enrichGO, enrichKEGG, gseGO |
| **WGCNA** | 6 | systems_biology | blockwiseModules, moduleEigengenes |
| **ggplot2** | 6 | visualization | ggplot, geom_point, ggsave |
| **dplyr** | 4 | data processing | filter, select, mutate |

### 2.3 CLI Tool Commands (74)

| Tool | Commands | Domain |
|------|----------|--------|
| **bwa** | mem, index, aln, samse, sampe | alignment |
| **samtools** | view, sort, index, flagstat, stats, merge, mpileup, faidx | SAM/BAM |
| **bcftools** | call, filter, view, stats, merge, annotate | variants |
| **bedtools** | intersect, subtract, coverage, genomecov, getfasta | regions |
| **MACS2** | callpeak, bdgcmp, bdgdiff | ChIP-seq |
| **STAR** | genomeGenerate, alignReads | RNA-seq |
| **salmon** | index, quant | RNA-seq quantification |
| **kallisto** | index, quant | RNA-seq quantification |
| **GATK** | HaplotypeCaller, Mutect2, BaseRecalibrator | variant calling |
| **BLAST** | blastn, blastp, blastx, tblastn, makeblastdb | sequence search |
| **foldseek** | createdb, search, easy-search | structure search |
| **mmseqs** | createdb, search, cluster | sequence clustering |

---

## 3. Biomni Workflows by Domain (122 Main Workflows)

| Domain | Workflows | Tool Types Used | Example Workflows |
|--------|-----------|-----------------|-------------------|
| **genomics** | 28 | Python, R, CLI | variant_calling, rna_seq_analysis, chip_seq_pipeline |
| **bioimaging** | 15 | Python | cell_segmentation, fluorescence_analysis |
| **biochemistry** | 12 | Python | enzyme_kinetics, metabolic_modeling |
| **cell_biology** | 10 | Python | cell_cycle_analysis, migration_tracking |
| **cancer_biology** | 8 | Python, R | tumor_mutation_burden, copy_number_analysis |
| **immunology** | 8 | Python, R | immune_repertoire, t_cell_analysis |
| **genetics** | 7 | Python, CLI | gwas_analysis, linkage_disequilibrium |
| **molecular_biology** | 7 | Python | cloning_design, primer_design |
| **pharmacology** | 6 | Python | drug_response, dose_response |
| **microbiology** | 5 | Python, CLI | metagenomics, 16s_analysis |
| **synthetic_biology** | 4 | Python | circuit_design, part_characterization |
| **pathology** | 4 | Python | histology_analysis, biomarker_detection |
| **physiology** | 3 | Python | signal_processing, homeostasis_modeling |
| **biophysics** | 2 | Python | molecular_dynamics, binding_affinity |
| **bioengineering** | 2 | Python | bioreactor_optimization |
| **glycoengineering** | 1 | Python | glycan_analysis |

---

## 4. Galaxy IWC Workflow Tools (334 Unique)

> **Verification**: Extracted from 510 raw `tool_id` entries across all `.ga` workflow files in IWC repository.
> File: `/tmp/galaxy_tools_names.txt` contains the complete deduplicated list.

### 4.1 Complete Tool List by Category

#### Alignment & Mapping (14 tools)
`bwa`, `bwa_mem2`, `bowtie2`, `minimap2`, `rgrnastar`, `rna_starsolo`, `mafft`, `clustalw`

#### RNA-seq & Transcriptomics (18 tools)
`featurecounts`, `stringtie`, `cufflinks`, `deseq2`, `edger`, `deg_annotate`, `goseq`, `rseqc`, `feelnc`, `brew3r_r`

#### Variant Calling & Analysis (22 tools)
`bcftools_annotate`, `bcftools_consensus`, `bcftools_norm`, `freebayes`, `lofreq_call`, `lofreq_filter`, `lofreq_indelqual`, `lofreq_viterbi`, `snpeff`, `snpeff_sars_cov_2`, `snpsift`, `snpfreqplot`, `ivar_consensus`, `ivar_trim`, `ivar_variants`, `ivar_removereads`, `clair3`, `vcfvcfintersect`

#### Quality Control & Preprocessing (18 tools)
`fastqc`, `multiqc`, `fastp`, `cutadapt`, `trimmomatic`, `prinseq`, `porechop`, `fastq_dl`, `fastq_filter`, `fastqtofasta`, `qualimap_bamqc`, `nanoplot`, `genomescope`

#### SAM/BAM Processing (12 tools)
`samtools_view`, `samtools_sort`, `samtools_merge`, `samtools_stats`, `samtools_coverage`, `samtools_depth`, `samtools_fastx`, `samtools_idxstats`, `samtool_filter2`, `bamtools_filter`, `bamtools_split_mapped`, `bamtools_split_ref`, `picard`

#### Assembly & Scaffolding (18 tools)
`flye`, `hifiasm`, `megahit`, `metaspades`, `shovill`, `racon`, `medaka_consensus`, `medaka_consensus_pipeline`, `medaka_variant`, `quast`, `busco`, `compleasm`, `omark`, `gfastats`, `meryl`, `meryl_count_kmers`, `meryl_groups_kmers`, `meryl_histogram_kmers`, `merqury`, `purge_dups`, `yahs`, `bionano_scaffold`

#### Metagenomics & Microbiome (28 tools)
`kraken2`, `bracken`, `krakentools_extract_kraken_reads`, `krakentools_kreport2krona`, `taxonomy_krona_chart`, `recentrifuge`, `metabat2`, `metabat2_jgi_summarize_bam_contig_depths`, `maxbin2`, `concoct`, `concoct_coverage_table`, `concoct_cut_up_fasta`, `concoct_extract_fasta_bins`, `concoct_merge_cut_up_clustering`, `binette`, `semibin`, `drep_dereplicate`, `gtdbtk_classify_wf`, `checkm2`, `checkm_lineage_wf`, `coverm_genome`

#### Single-cell RNA-seq (18 tools)
`scanpy_cluster_reduce_dimension`, `scanpy_filter`, `scanpy_inspect`, `scanpy_normalize`, `scanpy_plot`, `scanpy_remove_confounders`, `anndata_import`, `anndata_inspect`, `anndata_manipulate`, `anndata_ops`, `cite_seq_count`, `dropletutils`, `velocyto_cli`, `decoupler_pseudobulk`, `baredsc_1d`, `baredsc_2d`, `baredsc_combine_1d`, `baredsc_combine_2d`

#### Annotation & Gene Prediction (14 tools)
`bakta`, `maker`, `maker_map_ids`, `helixer`, `repeat_masker`, `repeatmodeler`, `gffread`, `jcvi_gff_stats`, `eggnog_mapper`, `interproscan`, `abricate`, `amrfinderplus`, `staramr`, `plasmidfinder`, `integron_finder`, `isescan`

#### Phylogenetics (6 tools)
`fasttree`, `iqtree`, `newick_utils`

#### Imaging & Spatial (22 tools)
`basic_illumination`, `ashlar`, `coreograph`, `mesmer`, `scimap_mcmicro_to_anndata`, `scimap_phenotyping`, `scimap_plotting`, `squidpy_scatter`, `squidpy_spatial`, `vitessce_spatial`, `2d_auto_threshold`, `2d_histogram_equalization`, `2d_simple_filter`, `binary2labelimage`, `bfconvert`, `count_objects`, `intensity_checks`, `overlay_images`, `rename_tiff_channels`, `graphicsmagick_image_montage`, `imagemagick_image_montage`, `backsub`

#### Metabolomics & Mass Spec (22 tools)
`xcms_xcmsset`, `xcms_group`, `xcms_retcor`, `xcms_fillpeaks`, `xcms_merge`, `xcms_plot_chromatogram`, `camera_annotate`, `msnbase_readmsdata`, `metams_rungc`, `mfassignr_findrecalseries`, `mfassignr_histnoise`, `mfassignr_isofiltr`, `mfassignr_kmdnoise`, `mfassignr_mfassign`, `mfassignr_mfassigncho`, `mfassignr_recal`, `mfassignr_recallist`, `mfassignr_snplot`, `maxquant`, `msconvert`, `pepquery2`, `peptideshaker`, `msstatstmt`

#### Proteomics (12 tools)
`openms_decoydatabase`, `openms_falsediscoveryrate`, `openms_featurefindermultiplex`, `openms_idmapper`, `openms_metaprosip`, `openms_msgfplusadapter`, `openms_peptideindexer`, `unipept`, `uniprotxml_downloader`, `metanovo`

#### Molecular Dynamics & Docking (18 tools)
`gmx_setup`, `gmx_editconf`, `gmx_solvate`, `gmx_makendx`, `gmx_merge_topology_files`, `gmx_em`, `gmx_sim`, `mmpbsa_mmgbsa`, `parmconv`, `ambertools_acpype`, `ambertools_antechamber`, `rxdock_rbcavity`, `rxdock_rbdock`, `rdock_sort_filter`, `sucos_docking_scoring`, `ctb_frankenstein_ligand`, `ctb_rdkit_descriptors`, `openbabel_compound_convert`, `enumerate_charges`

#### Sequence Utilities (22 tools)
`fasta_compute_length`, `fasta_filter_by_length`, `fasta_formatter`, `fasta_merge_files_and_filter_unique_sequences`, `fasta_stats`, `fasta_to_contig2bin`, `fasta_to_tabular`, `tabular_to_fasta`, `seqtk`, `emboss_5`, `ncbi_blast_plus`, `ncbi_fcs_adaptor`, `ncbi_fcs_gx`, `infernal`, `cmsearch_deoverlap`

#### Hi-C & Chromatin (10 tools)
`cooler_balance`, `cooler_cload_tabix`, `cooler_csort_tabix`, `cooler_makebins`, `pairtools_dedup`, `pairtools_parse`, `hicup_hicup`, `hicup2juicer`, `pretext_graph`, `pretext_map`, `pretext_snapshot`, `pygenometracks`, `pe_histogram`

#### Viral & COVID-19 (8 tools)
`pangolin`, `nextclade`, `vapor`, `snipit`

#### Data Manipulation (32 tools)
`datamash_ops`, `text_processing`, `column_maker`, `column_remove_by_header`, `filter_tabular`, `query_tabular`, `table_compute`, `merge`, `subtract`, `concat`, `concatenate_multiple_datasets`, `split_file_on_column`, `split_file_to_collection`, `collapse_collections`, `collection_column_join`, `collection_element_identifiers`, `add_input_name_as_column`, `add_line_to_file`, `add_value`, `replace_column_by_key_value_file`, `regex_find_replace`, `compress_file`, `biom_convert`, `reshape2_melt`, `checkformat`, `dbbuilder`, `get_online_data`, `sra_tools`

#### Visualization (10 tools)
`ggplot2_heatmap`, `ggplot2_heatmap2`, `ggplot2_point`, `volcanoplot`, `jbrowse`, `bandage`

#### Workflow Utilities (12 tools)
`pick_value`, `map_param_value`, `compose_text_param`, `calculate_numeric_param`, `tooldistillator`, `tooldistillator_summarize`

#### Other Specialized (18 tools)
`qiime2_core__tools__import`, `qiime2__dada2__denoise_paired`, `qiime2__dada2__denoise_single`, `qiime2__demux__emp_paired`, `qiime2__demux__emp_single`, `qiime2__demux__summarize`, `qiime2__diversity__alpha_group_significance`, `qiime2__diversity__alpha_rarefaction`, `qiime2__diversity__beta_group_significance`, `qiime2__diversity__core_metrics_phylogenetic`, `qiime2__feature_classifier__classify_sklearn`, `qiime2__feature_table__summarize`, `qiime2__feature_table__tabulate_seqs`, `qiime2__fragment_insertion__sepp`, `qiime2__metadata__tabulate`, `qiime2__taxa__barplot`, `dada2_*` (8 tools), `ampvis2_load`, `mapseq`, `mash_*` (3 tools), `mgnify_seqprep`, `rdeval`, `mitohifi`, `parse_mito_blast`, `qcxms_*` (3 tools), `biomd_neqgamma`, `multivariate`, `quantification`

---

## 5. Nextflow nf-core Modules (755 Tools, 1,651 Tool_Functions)

> **Source**: `/home/yzhang/biomate/backend/nf-core-modules/modules/nf-core/`

### 5.1 nf-core Module Statistics

| Metric | Count |
|--------|-------|
| Unique Tools | 755 |
| Tool_Functions (processes) | 1,651 |
| Avg functions per tool | 2.2 |

### 5.2 Sample Tool → Tool_Functions Mapping

| Tool | Tool_Functions | Example Functions |
|------|----------------|-------------------|
| samtools | 32 | view, sort, merge, index, stats, flagstat |
| bcftools | 21 | call, filter, view, annotate, merge, norm |
| gatk4 | 45 | haplotypecaller, mutect2, baserecalibrator |
| bwa | 3 | mem, index, aln |
| star | 4 | align, genomegenerate |
| salmon | 3 | index, quant |

### 5.3 Major Categories

| Category | Tools | Examples |
|----------|-------|----------|
| **Alignment** | ~50 | bwa, bowtie2, star, hisat2, minimap2 |
| **RNA-seq** | ~60 | salmon, kallisto, rsem, stringtie, featurecounts |
| **Variant Calling** | ~50 | bcftools, gatk4, freebayes, deepvariant |
| **QC & Trimming** | ~40 | fastqc, multiqc, fastp, cutadapt |
| **Metagenomics** | ~80 | kraken2, bracken, metaphlan, kaiju |
| **Single-cell** | ~45 | cellranger, scanpy, seurat |
| **Assembly** | ~35 | spades, megahit, flye, canu |
| **Annotation** | ~30 | prokka, bakta, interproscan |
| **Structure** | ~25 | alphafold, esmfold, foldseek |
| **Phylogenetics** | ~20 | mafft, muscle, raxml, iqtree |
| **Other** | ~320 | Various specialized tools |

---

## 6. Docker Image Layers

### Layer 1: System Dependencies (Debian/Ubuntu)
```dockerfile
apt-get install -y \
    build-essential gcc g++ gfortran cmake make \
    zlib1g libbz2-1.0 liblzma5 libcurl4 libssl3 \
    libncurses6 libncursesw6 libtbb12 libgomp1 \
    libpng-dev libjpeg-dev libtiff-dev \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libhdf5-dev pkg-config \
    libopenblas-dev liblapack-dev \
    default-jre-headless perl libgsl-dev bedtools
```

### Layer 2: Core Python Packages
```bash
pip install numpy scipy pandas matplotlib seaborn \
    biopython requests aiohttp h5py anndata \
    scikit-learn pydantic python-dotenv tqdm rich
```

### Layer 3: Domain-Specific Python
```bash
# Bioimaging
pip install scikit-image opencv-python-headless Pillow nibabel SimpleITK

# Genomics
pip install scanpy gseapy gget pybedtools pybiomart pysam pyfaidx pyvcf3

# Pharmacology
pip install rdkit pubchempy statsmodels

# Systems Biology
pip install cobra networkx python-libsbml

# Flow Cytometry
pip install flowio flowkit FlowCytometryTools
```

### Layer 4: ML/Deep Learning
```bash
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install transformers accelerate sentencepiece
```

---

## 7. Building for Different Architectures

### x86_64 (AMD64) - Default
```bash
docker build -t biomate/biotools:comprehensive \
    -f Dockerfile.comprehensive .
```

### ARM64 (Apple Silicon, AWS Graviton)

Key modifications needed:

1. **Add simde library** for Bowtie2:
```dockerfile
RUN apt-get install -y libsimde-dev
```

2. **Build Bowtie2 with simde**:
```dockerfile
RUN git clone bowtie2 && \
    cd bowtie2 && \
    git clone https://github.com/simd-everywhere/simde.git third_party/simde && \
    make POPCNT_CAPABILITY=0
```

3. **Use ARM-compatible binaries** where available:
```dockerfile
# Salmon - check for ARM64 release
# kallisto - may need to compile from source
# stringtie - compile from source
```

4. **Skip x86-specific tools**:
```dockerfile
# MMseqs2 AVX2 version won't work
# Use generic or ARM-compiled versions
```

### Build from Scratch Checklist

1. **Pre-requisites**:
   - Docker 20.10+
   - 16GB+ RAM recommended
   - 50GB+ disk space

2. **Required Build Tools** (in builder stage):
```bash
build-essential cmake autoconf automake libtool git wget curl
zlib1g-dev libbz2-dev liblzma-dev libcurl4-openssl-dev libssl-dev
libncurses5-dev libncursesw5-dev libtbb-dev libhdf5-dev default-jdk
```

3. **Order of Tool Building**:
   - htslib (dependency for samtools/bcftools)
   - samtools
   - bcftools
   - bwa
   - bowtie2 (needs simde on ARM)
   - bedtools
   - Other aligners (STAR, hisat2, minimap2)
   - Quantification tools (salmon, kallisto)
   - Variant callers (freebayes, GATK)
   - Search tools (HMMER, MMseqs2, foldseek)

4. **Python Environment**:
   - Python 3.11+
   - pip install in dependency order
   - Handle optional packages with `|| true`

---

## 8. Tool Type Distribution in Database

### galaxy_ai_tools.db Statistics

| Tool Type | Count | Source |
|-----------|-------|--------|
| CLI | 7,267 | Galaxy ToolShed, Nextflow modules |
| Python | 524 | Biomni, Galaxy wrappers |
| R | 207 | Galaxy wrappers, Biomni |
| Unknown | 97 | Missing metadata |
| **Total** | **8,095** | All sources |

### Biomni-Specific Distribution

| Type | Count | Examples |
|------|-------|----------|
| Python | 109 | scanpy, Bio, cv2 |
| R | 58 | DESeq2, Seurat, ggplot2 |
| CLI | 74 | samtools, bwa, blast |
| **Total** | **241** | Atomic tool-functions |

---

## 9. Version Information

| Tool | Version | Source |
|------|---------|--------|
| Python | 3.11 | Base image |
| samtools | 1.21 | htslib |
| bcftools | 1.21 | htslib |
| bwa | latest | github |
| bowtie2 | 2.5.3 | github |
| bedtools | 2.31.1 | github |
| STAR | 2.7.11b | github |
| salmon | 1.10.3 | pre-built |
| kallisto | 0.50.1 | pre-built |
| GATK | 4.5.0.0 | pre-built |
| picard | 3.1.1 | pre-built |
| FastQC | 0.12.1 | pre-built |
| HMMER | 3.4 | source |
| SPAdes | 4.0.0 | pre-built |

---

## 10. References

- **Biomni Documentation**: `biomni_galaxy/20251201_2110_BIOMNI_GALAXY_TOOL_INDEX_COMPLETE.md`
- **Architecture**: `biomni_galaxy/20251201_2130_BIOMNI_GALAXY_COMPREHENSIVE_ARCHITECTURE.md`
- **Dockerfile**: `biomni_galaxy/docker/Dockerfile.comprehensive`
- **Database**: `biomni_tools_v2.db` (tool_functions table)

---

*Generated by Claude Code on December 2, 2025*
