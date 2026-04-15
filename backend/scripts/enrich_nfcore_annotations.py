#!/usr/bin/env python3
"""
Enrich sparse nf-core workflow annotations in the SQLite database.

Updates `description` (if < 100 chars) and `annotation` for all nfcore workflows
with description < 150 chars, then rebuilds the FTS index.
"""

import re
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

# ---------------------------------------------------------------------------
# Hand-authored annotations for well-known nf-core pipelines / subworkflows
# ---------------------------------------------------------------------------
KNOWN_ANNOTATIONS: dict[str, dict[str, str]] = {
    "nf-core/fastq_subsample_fq_salmon": {
        "description": "Subsample FASTQ files and estimate transcript expression with Salmon for rapid quality assessment before full alignment",
        "annotation": "FASTQ subsample salmon transcript quantification QC quality assessment rapid expression estimate",
    },
    "nf-core/cageseq": {
        "description": "CAGE-seq (Cap Analysis of Gene Expression) analysis pipeline for transcription start site profiling and promoter activity mapping",
        "annotation": "CAGE-seq transcription start site TSS promoter cap analysis gene expression FASTQ alignment",
    },
    "nf-core/dualrnaseq": {
        "description": "Dual RNA-seq pipeline for simultaneous profiling of host and pathogen transcriptomes from infection experiments",
        "annotation": "dual RNA-seq host pathogen infection transcriptome simultaneous profiling bacteria virus FASTQ",
    },
    "nf-core/clipseq": {
        "description": "CLIP-seq (Crosslinking Immunoprecipitation sequencing) analysis for RNA-protein interaction and binding site identification",
        "annotation": "CLIP-seq HITS-CLIP PAR-CLIP iCLIP RNA-protein interaction binding sites crosslinking immunoprecipitation",
    },
    "nf-core/demo": {
        "description": "Demo pipeline for testing nf-core infrastructure and demonstrating best practices in Nextflow pipeline development",
        "annotation": "demo test nf-core infrastructure example pipeline tutorial",
    },
    "nf-core/metapep": {
        "description": "Metaproteomics peptide analysis pipeline for identifying and quantifying proteins from complex microbiome samples",
        "annotation": "metaproteomics peptide protein identification quantification microbiome mass spectrometry",
    },
    "nf-core/readsimulator": {
        "description": "Simulate sequencing reads (Illumina, Oxford Nanopore, PacBio) from reference genomes for benchmarking and testing",
        "annotation": "read simulation sequencing Illumina Oxford Nanopore PacBio ART badread NanoSim benchmark test",
    },
    "nf-core/seqinspector": {
        "description": "Quality inspection of raw sequencing data across multiple technologies: Illumina, Nanopore, PacBio short and long reads",
        "annotation": "sequencing quality inspection QC raw reads Illumina Nanopore PacBio FastQC MultiQC",
    },
    "nf-core/genomeannotator": {
        "description": "Genome annotation pipeline: predict genes, transposable elements, and non-coding RNA from assembled genomes using MAKER, AUGUSTUS, and RepeatModeler",
        "annotation": "genome annotation gene prediction MAKER AUGUSTUS RepeatModeler transposable elements non-coding RNA assembly",
    },
    "nf-core/coproid": {
        "description": "Ancient coprolite and sediment DNA analysis: identify dietary and microbial content from ancient feces samples using metagenomic approaches",
        "annotation": "ancient DNA coprolite sediment dietary metagenomic paleogenomics paleofeces microbiome archaeology",
    },
    "nf-core/phaseimpute": {
        "description": "Genotype imputation and phasing pipeline: impute missing genotypes and phase haplotypes using GLIMPSE or BEAGLE from low-coverage WGS data",
        "annotation": "genotype imputation phasing haplotype GLIMPSE BEAGLE low-coverage WGS whole genome sequencing missing genotypes",
    },
    "nf-core/references": {
        "description": "Download, prepare, and index reference genomes and annotation files for use with nf-core pipelines",
        "annotation": "reference genome download prepare index FASTA STAR BWA bowtie2 HISAT2 annotation GTF",
    },
    "nf-core/sammyseq": {
        "description": "SAMMY-seq analysis pipeline for chromatin accessibility and nuclear structure profiling using sequential fractionation and sequencing",
        "annotation": "SAMMY-seq chromatin accessibility nuclear structure fractionation lamina-associated domains LADs",
    },
    "nf-core/imcyto": {
        "description": "Imaging Mass Cytometry (IMC) analysis pipeline: segment cells, extract single-cell features, and cluster cell populations from multiplexed tissue images",
        "annotation": "IMC imaging mass cytometry cell segmentation single-cell multiplexed tissue image CellProfiler",
    },
    "nf-core/kmermaid": {
        "description": "K-mer analysis pipeline for sequence diversity estimation, contamination detection, and genome size estimation using MinHash sketches",
        "annotation": "k-mer MinHash mash sourmash genome size estimation contamination detection diversity sequence",
    },
    "nf-core/marsseq": {
        "description": "MARS-seq (Massively parallel RNA single-cell sequencing) analysis pipeline for high-throughput single-cell transcriptomics",
        "annotation": "MARS-seq single-cell transcriptomics high-throughput plate-based RNA-seq cell barcode UMI",
    },
    "nf-core/mnaseseq": {
        "description": "MNase-seq analysis pipeline for nucleosome positioning and chromatin structure profiling from micrococcal nuclease digestion data",
        "annotation": "MNase-seq nucleosome positioning chromatin structure micrococcal nuclease FASTQ alignment peak calling",
    },
    "nf-core/rnavar": {
        "description": "RNA variant calling pipeline: detect SNPs, indels, and fusion events from RNA-seq data using STAR + GATK best practices",
        "annotation": "RNA variant calling SNP indel fusion RNA-seq STAR GATK HaplotypeCaller splice junctions somatic germline",
    },
    "nf-core/nanostring": {
        "description": "NanoString nCounter gene expression analysis pipeline for multiplex profiling of RNA, protein, and miRNA from tissue or cell samples",
        "annotation": "NanoString nCounter gene expression multiplexed profiling RNA protein miRNA normalization",
    },
    "nf-core/cellpainting": {
        "description": "Cell Painting image analysis pipeline for morphological profiling: segment cells, extract features, and identify compound effects from high-content microscopy",
        "annotation": "cell painting morphological profiling high-content microscopy image analysis CellProfiler compound drug discovery phenotype",
    },
    "nf-core/evexplorer": {
        "description": "Extracellular vesicle (EV) proteomics and lipidomics analysis pipeline for EV characterization from mass spectrometry data",
        "annotation": "extracellular vesicle EV exosome proteomics lipidomics mass spectrometry characterization",
    },
    "nf-core/genephylomodeler": {
        "description": "Gene family phylogenetic modeling pipeline: reconstruct ancestral sequences, model evolution, and analyze gene family dynamics",
        "annotation": "gene family phylogenetics ancestral sequence reconstruction evolution modeling protein family",
    },
    "nf-core/mitodetect": {
        "description": "Mitochondrial variant detection pipeline for heteroplasmy analysis, mitochondrial genome assembly, and haplogroup determination",
        "annotation": "mitochondrial variant heteroplasmy mtDNA mitochondrial genome haplogroup assembly chrM",
    },
    "nf-core/radseq": {
        "description": "RADseq (Restriction-site Associated DNA sequencing) analysis for population genetics and phylogenomics from restriction-digest sequencing",
        "annotation": "RADseq restriction-site associated DNA population genetics phylogenomics ddRAD stacks FASTQ",
    },
    "nf-core/hackathon": {
        "description": "Template/skeleton pipeline used during nf-core hackathons for developing new pipelines and testing features",
        "annotation": "hackathon template skeleton development test nf-core",
    },
    "nf-core/pacsomatic": {
        "description": "PacBio HiFi tumor/normal somatic variant calling pipeline for detecting SNVs, indels, and structural variants from long-read sequencing",
        "annotation": "PacBio HiFi long-read somatic variant calling tumor-normal SNV indel structural variant DeepVariant",
    },
    "nf-core/proteinfold": {
        "description": "Protein structure prediction pipeline supporting AlphaFold2, ESMFold, OmegaFold, and RoseTTAFold for 3D structure prediction from protein sequence (FASTA)",
        "annotation": "protein structure prediction AlphaFold2 ESMFold OmegaFold RoseTTAFold FASTA 3D fold structure prediction",
    },
    "nf-core/spatialxe": {
        "description": "10x Xenium spatial transcriptomics analysis pipeline for in-situ gene expression profiling at single-cell resolution from tissue sections",
        "annotation": "Xenium spatial transcriptomics in-situ single-cell tissue section gene expression 10x spatial",
    },
    "nf-core/bacass": {
        "description": "Bacterial genome assembly and annotation pipeline supporting short reads (Illumina), long reads (Nanopore/PacBio), and hybrid assembly approaches",
        "annotation": "bacterial genome assembly annotation Illumina Nanopore PacBio hybrid assembly prokka FASTQ",
    },
    "nf-core/crisprseq": {
        "description": "CRISPR-seq analysis pipeline for quantifying editing efficiency, on-target and off-target effects from amplicon or genome-wide screens",
        "annotation": "CRISPR CRISPR-seq editing efficiency on-target off-target amplicon screen guide RNA indel",
    },
    "nf-core/slamseq": {
        "description": "SLAM-seq (Thiol-linked alkylation for the metabolic sequencing of RNA) analysis for measuring RNA synthesis and degradation rates",
        "annotation": "SLAM-seq RNA synthesis degradation metabolic labeling 4sU thiol-linked alkylation turnover rate",
    },
    "nf-core/vcf_impute_glimpse": {
        "description": "VCF genotype imputation using GLIMPSE for low-coverage whole genome sequencing data to infer missing genotypes",
        "annotation": "VCF genotype imputation GLIMPSE low-coverage WGS missing genotypes phasing",
    },
    "nf-core/fastq_align_dna": {
        "description": "DNA alignment subworkflow: align FASTQ reads to reference genome using BWA-MEM2 or BWA-MEM, sort, and index BAM output",
        "annotation": "DNA alignment FASTQ BWA-MEM2 BWA-MEM reference genome BAM sort index whole genome sequencing",
    },
    "nf-core/bam_sort_stats_samtools": {
        "description": "Sort BAM files by coordinate and compute alignment statistics (flagstat, idxstat, stats) using Samtools",
        "annotation": "BAM sort coordinate Samtools flagstat idxstats alignment statistics",
    },
    "nf-core/fastq_trim_fastp_fastqc": {
        "description": "Trim adapters and low-quality bases from FASTQ reads using fastp and run FastQC quality control",
        "annotation": "FASTQ trimming adapter removal fastp FastQC quality control preprocessing reads",
    },
    "nf-core/fastq_fastqc_umitools_trimgalore": {
        "description": "FASTQ quality control with FastQC, UMI extraction with UMI-tools, and adapter trimming with Trim Galore",
        "annotation": "FASTQ quality control FastQC UMI UMI-tools Trim Galore adapter trimming preprocessing",
    },
    "nf-core/bedgraph_bedclip_bedgraphtobigwig": {
        "description": "Convert bedGraph coverage tracks to BigWig format: clip to chromosome sizes then convert for genome browser visualization",
        "annotation": "bedGraph BigWig coverage track genome browser visualization deepTools clip convert",
    },
    "nf-core/fastq_fastqc_umitools_fastp": {
        "description": "FASTQ quality control with FastQC, UMI extraction with UMI-tools, and adapter trimming with fastp",
        "annotation": "FASTQ quality control FastQC UMI UMI-tools fastp adapter trimming preprocessing",
    },
    "nf-core/vcf_phase_shapeit5": {
        "description": "Phase VCF genotypes using SHAPEIT5 for accurate haplotype phasing from population-scale sequencing data",
        "annotation": "VCF phasing SHAPEIT5 haplotype genotype population sequencing",
    },
    "nf-core/h5ad_removebackground_barcodes_cellbender_anndata": {
        "description": "Remove ambient RNA background from single-cell count matrices using CellBender on h5ad/AnnData files",
        "annotation": "ambient RNA removal CellBender background correction single-cell h5ad AnnData barcode QC",
    },
    "nf-core/bam_markduplicates_samtools": {
        "description": "Mark or remove PCR duplicates from BAM files using Samtools markdup for library complexity assessment",
        "annotation": "BAM duplicate marking samtools markdup PCR duplicates library complexity",
    },
    # Additional well-known nf-core pipelines
    "nf-core/ampliseq": {
        "description": "16S/18S/ITS amplicon sequencing analysis pipeline: DADA2 or QIIME2 for OTU/ASV calling, taxonomic classification, and diversity metrics",
        "annotation": "amplicon sequencing 16S 18S ITS DADA2 QIIME2 OTU ASV taxonomic classification diversity microbiome",
    },
    "nf-core/atacseq": {
        "description": "ATAC-seq open chromatin analysis pipeline: alignment, peak calling (MACS2), FRiP QC, consensus peaks, differential accessibility, and motif enrichment",
        "annotation": "ATAC-seq chromatin accessibility open chromatin peak calling MACS2 FASTQ differential accessibility motif TF binding",
    },
    "nf-core/bamtofastq": {
        "description": "Convert BAM or CRAM files back to FASTQ format, with optional sorting and interleaving for downstream reanalysis",
        "annotation": "BAM CRAM to FASTQ conversion samtools bedtools reanalysis paired-end single-end",
    },
    "nf-core/circrna": {
        "description": "Circular RNA (circRNA) detection and quantification pipeline from RNA-seq data using multiple detection algorithms and miRNA sponge analysis",
        "annotation": "circular RNA circRNA detection quantification RNA-seq back-splice junction miRNA sponge",
    },
    "nf-core/cutandrun": {
        "description": "CUT&RUN and CUT&TAG analysis pipeline for histone modification and transcription factor binding profiling",
        "annotation": "CUT&RUN CUT&TAG histone modification transcription factor binding chromatin profiling antibody FASTQ peaks",
    },
    "nf-core/differentialabundance": {
        "description": "Differential abundance analysis pipeline for RNA-seq, proteomics, and microbiome data using DESeq2, limma, or edgeR to identify statistically significant changes",
        "annotation": "differential abundance differential expression DESeq2 limma edgeR RNA-seq proteomics microbiome statistical testing volcano plot heatmap",
    },
    "nf-core/eager": {
        "description": "Ancient DNA (aDNA) processing and analysis pipeline: adapter trimming, mapping, damage estimation, authentication, and population genetics",
        "annotation": "ancient DNA aDNA paleogenomics damage estimation Mapdamage authentication FASTQ BAM population genetics",
    },
    "nf-core/fetchngs": {
        "description": "Download sequencing data and metadata from public databases (SRA, ENA, DDBJ, GEO, Synapse) given accession IDs",
        "annotation": "download sequencing data SRA ENA DDBJ GEO Synapse accession FASTQ metadata public database",
    },
    "nf-core/hgtseq": {
        "description": "Horizontal gene transfer (HGT) detection pipeline for identifying foreign DNA integration events in host genomes from sequencing data",
        "annotation": "horizontal gene transfer HGT foreign DNA integration detection sequencing FASTQ BAM",
    },
    "nf-core/hic": {
        "description": "Hi-C contact map generation and chromatin 3D structure analysis pipeline: alignment, contact matrix, TAD calling, and compartment analysis",
        "annotation": "Hi-C chromatin 3D structure contact map TAD topological domain compartment FASTQ cooler",
    },
    "nf-core/hicar": {
        "description": "HiCAR (Hi-C on Accessible Regulatory DNA) analysis pipeline for mapping chromatin interaction at open chromatin regions",
        "annotation": "HiCAR Hi-C accessible chromatin regulatory DNA interaction ATAC open chromatin 3D genome",
    },
    "nf-core/isoseq": {
        "description": "PacBio Iso-Seq long-read full-length transcript sequencing pipeline for isoform discovery and quantification",
        "annotation": "Iso-Seq PacBio long-read full-length transcript isoform discovery quantification CCS HiFi",
    },
    "nf-core/mag": {
        "description": "Metagenome assembly and binning pipeline: assemble reads, bin contigs into MAGs, assess completeness with CheckM, and annotate with GTDB-Tk",
        "annotation": "metagenome assembled genome MAG assembly binning CheckM GTDB-Tk completeness contamination taxonomy",
    },
    "nf-core/metatdenovo": {
        "description": "Metatranscriptome de novo assembly pipeline for reconstructing transcripts from environmental RNA samples without a reference genome",
        "annotation": "metatranscriptome de novo assembly environmental RNA Trinity FASTQ transcript reconstruction",
    },
    "nf-core/methylarray": {
        "description": "DNA methylation array analysis pipeline for Illumina EPIC and 450k arrays: normalization, QC, differential methylation, and copy number",
        "annotation": "methylation array Illumina EPIC 450k DNA methylation normalization differential methylation copy number minfi",
    },
    "nf-core/mhcquant": {
        "description": "MHC-peptide quantification pipeline for immunopeptidomics: identify MHC-I/II presented peptides from mass spectrometry data",
        "annotation": "MHC peptide immunopeptidomics HLA mass spectrometry neoantigen vaccine immunotherapy OpenMS",
    },
    "nf-core/microbiomeanalyst": {
        "description": "Comprehensive microbiome analysis pipeline wrapping MicrobiomeAnalyst statistical and functional analysis methods",
        "annotation": "microbiome analysis 16S diversity statistics functional analysis MicrobiomeAnalyst OTU",
    },
    "nf-core/multiplesequencealign": {
        "description": "Multiple sequence alignment pipeline supporting MAFFT, MUSCLE, ClustalOmega, and T-Coffee for protein and nucleotide sequences",
        "annotation": "multiple sequence alignment MSA MAFFT MUSCLE ClustalOmega T-Coffee protein nucleotide FASTA",
    },
    "nf-core/nanoseq": {
        "description": "Oxford Nanopore long-read DNA/RNA sequencing analysis: basecalling, alignment, QC, variant calling, and differential expression",
        "annotation": "Nanopore long-read ONT Oxford Nanopore basecalling alignment QC variant calling differential expression",
    },
    "nf-core/nf-test-datasets": {
        "description": "Test datasets repository for nf-core pipeline CI/CD testing, not a runnable pipeline",
        "annotation": "test datasets CI/CD nf-core testing reference data",
    },
    "nf-core/oncoanalyser": {
        "description": "Comprehensive cancer genome analysis pipeline from Hartwig Medical Foundation: somatic SNV/indel/SV/CNV calling, fusion detection, and HRD/TMB/MSI scoring",
        "annotation": "cancer genome somatic SNV indel SV CNV fusion HRD TMB MSI tumor normal PURPLE AMBER COBALT",
    },
    "nf-core/pangenome": {
        "description": "Pangenome graph construction and analysis pipeline: build variation graphs from multiple assemblies using PanSN-spec and odgi",
        "annotation": "pangenome variation graph PanSN-spec odgi PGGB multiple assemblies genomic variation",
    },
    "nf-core/pgdb": {
        "description": "Proteogenomics database generation pipeline: create customized protein FASTA databases integrating genomic variants for MS/MS searches",
        "annotation": "proteogenomics protein database variant FASTA mass spectrometry MS/MS peptide identification",
    },
    "nf-core/phageannotator": {
        "description": "Bacteriophage genome annotation pipeline: identify, classify, and annotate phage sequences from metagenomic assemblies",
        "annotation": "bacteriophage phage genome annotation classification metagenomic viral sequences",
    },
    "nf-core/phyloplace": {
        "description": "Phylogenetic placement pipeline for assigning query sequences to a reference tree using EPA-ng or pplacer",
        "annotation": "phylogenetic placement reference tree EPA-ng pplacer query sequences taxonomy",
    },
    "nf-core/pixelator": {
        "description": "Molecular Pixelation single-cell spatial proteomics analysis pipeline for antibody-based spatial protein profiling",
        "annotation": "Molecular Pixelation spatial proteomics single-cell antibody protein profiling spatial",
    },
    "nf-core/plantpathsurvey": {
        "description": "Plant pathogen surveillance pipeline for detecting and characterizing plant pathogens from sequencing data",
        "annotation": "plant pathogen surveillance detection characterization sequencing diagnostics",
    },
    "nf-core/quantms": {
        "description": "Quantitative mass spectrometry proteomics pipeline supporting DDA/DIA, TMT/label-free quantification using OpenMS",
        "annotation": "quantitative proteomics mass spectrometry DDA DIA TMT iTRAQ label-free OpenMS protein quantification",
    },
    "nf-core/raredisease": {
        "description": "Rare disease variant analysis pipeline: call and rank germline SNVs/indels/SVs/CNVs from WGS/WES, prioritize candidates with GENMOD/Rank Model",
        "annotation": "rare disease germline variant calling SNV indel SV CNV WGS WES ranking GENMOD clinical exome",
    },
    "nf-core/reportho": {
        "description": "Orthology inference pipeline for identifying orthologous genes across species using OrthoFinder and other tools",
        "annotation": "orthology orthologous genes OrthoFinder comparative genomics species evolution",
    },
    "nf-core/riboseq": {
        "description": "Ribosome profiling (Ribo-seq) analysis pipeline for measuring translation rates and identifying translated ORFs",
        "annotation": "ribosome profiling Ribo-seq translation ribosome footprint ORF detection FASTQ",
    },
    "nf-core/rnafusion": {
        "description": "RNA fusion gene detection pipeline using multiple callers (STAR-Fusion, Arriba, FusionCatcher) with consensus calling and visualization",
        "annotation": "RNA fusion gene detection STAR-Fusion Arriba FusionCatcher consensus cancer translocation FASTQ",
    },
    "nf-core/rnasplice": {
        "description": "Alternative splicing analysis pipeline: detect differential splicing events (exon skipping, intron retention) from RNA-seq using rMATS, DEXSEQ, and edgeR",
        "annotation": "alternative splicing rMATS DEXSEQ edgeR exon skipping intron retention differential splicing RNA-seq",
    },
    "nf-core/scnanoseq": {
        "description": "Single-cell Oxford Nanopore long-read sequencing analysis pipeline for full-length transcript isoform detection at single-cell resolution",
        "annotation": "single-cell Nanopore long-read full-length transcript isoform ONT 10x barcode",
    },
    "nf-core/scrnaseq": {
        "description": "Single-cell RNA-seq analysis pipeline: align reads, generate cell-by-gene count matrices using STARsolo, Alevin, Kallisto/Bustools, or CellRanger",
        "annotation": "single-cell RNA-seq scRNA-seq STARsolo Alevin Kallisto Bustools CellRanger 10x count matrix barcode",
    },
    "nf-core/smrnaseq": {
        "description": "Small RNA-seq analysis pipeline for miRNA discovery, quantification, and isomiR analysis using miRDeep2 and miRBase",
        "annotation": "small RNA miRNA isomiR miRDeep2 miRBase quantification discovery FASTQ short RNA",
    },
    "nf-core/spatialvi": {
        "description": "Visium spatial transcriptomics analysis pipeline: quality control, normalization, clustering, and spatially variable gene detection",
        "annotation": "Visium spatial transcriptomics 10x spot deconvolution clustering spatially variable genes tissue",
    },
    "nf-core/spotyping": {
        "description": "Mycobacterium tuberculosis spoligotyping pipeline for strain typing and lineage determination from sequencing data",
        "annotation": "tuberculosis TB Mycobacterium spoligotyping strain typing lineage FASTQ",
    },
    "nf-core/taxprofiler": {
        "description": "Taxonomic profiling of metagenomic and metatranscriptomic sequencing data using multiple classifiers (Kraken2, Bracken, MetaPhlAn, Centrifuge)",
        "annotation": "taxonomic profiling metagenomics Kraken2 Bracken MetaPhlAn Centrifuge FASTQ microbial community",
    },
    "nf-core/tcellreceptor": {
        "description": "T-cell receptor (TCR) repertoire analysis pipeline for V(D)J recombination profiling from bulk or single-cell immune sequencing",
        "annotation": "T-cell receptor TCR repertoire VDJ recombination immune sequencing bulk single-cell",
    },
    "nf-core/tools": {
        "description": "nf-core helper tools CLI for creating, linting, and managing nf-core pipelines — not a data analysis pipeline",
        "annotation": "nf-core tools CLI helper lint create template management",
    },
    "nf-core/variantbenchmarking": {
        "description": "Variant calling benchmarking pipeline for evaluating SNV, indel, and SV caller performance against truth sets using hap.py and Truvari",
        "annotation": "variant benchmarking truth set hap.py Truvari SNV indel SV evaluation precision recall F1",
    },
    "nf-core/viralintegration": {
        "description": "Viral integration site detection pipeline: identify where viral sequences integrate into host genomes from RNA-seq or DNA-seq data",
        "annotation": "viral integration site detection host genome RNA-seq DNA-seq virus insertion",
    },
    "nf-core/viralrecon": {
        "description": "Viral genome reconstruction pipeline for SARS-CoV-2 and other viruses: assembly, variant calling, lineage classification (Pangolin/Nextclade)",
        "annotation": "viral genome reconstruction SARS-CoV-2 COVID-19 assembly variant calling Pangolin Nextclade lineage",
    },
    "nf-core/vsearchpipeline": {
        "description": "VSEARCH-based amplicon sequencing analysis pipeline for OTU clustering, chimera removal, and community profiling",
        "annotation": "VSEARCH amplicon OTU clustering chimera removal community profiling 16S diversity",
    },
    "nf-core/wgsnano": {
        "description": "Whole-genome sequencing with Oxford Nanopore: alignment, structural variant calling, methylation calling, and phasing from long reads",
        "annotation": "Nanopore whole genome sequencing WGS long-read alignment SV methylation phasing ONT",
    },
    "nf-core/wgsvariantcalling": {
        "description": "Whole genome sequencing variant calling pipeline for short reads: alignment, BQSR, SNV/indel calling, SV calling, and annotation",
        "annotation": "whole genome sequencing WGS variant calling SNV indel SV GATK BQSR annotation short-read",
    },
    "nf-core/chipmentation": {
        "description": "ChIPmentation analysis pipeline for histone modification profiling combining ChIP-seq with transposase-based library preparation",
        "annotation": "ChIPmentation ChIP-seq histone modification transposase Tn5 chromatin profiling antibody FASTQ",
    },
    "nf-core/callingcards": {
        "description": "Calling Cards transposon insertion sequencing analysis for mapping transcription factor binding sites genome-wide",
        "annotation": "Calling Cards transposon insertion transcription factor binding site mapping genome-wide sequencing",
    },
    "nf-core/taxpasta": {
        "description": "Taxonomic profile standardization and merging pipeline for combining outputs from multiple taxonomic profilers into a unified table",
        "annotation": "taxonomic profile standardization merging Kraken2 MetaPhlAn Centrifuge unification table",
    },
    "nf-core/airrflow": {
        "description": "Adaptive immune receptor repertoire (AIRR) analysis pipeline for B-cell and T-cell receptor sequencing data using Immcantation framework",
        "annotation": "AIRR immune repertoire B-cell T-cell receptor Immcantation BCR TCR VDJ clonotype",
    },
    "nf-core/variantcatalogue": {
        "description": "Population-scale variant catalogue generation pipeline for building and annotating large-scale variant databases",
        "annotation": "variant catalogue population-scale variant database annotation large-scale genomics",
    },
    "nf-core/scdownstream": {
        "description": "Single-cell RNA-seq downstream analysis pipeline: clustering, trajectory analysis, cell type annotation, and integration",
        "annotation": "single-cell downstream analysis clustering trajectory annotation integration Seurat Scanpy UMAP",
    },
    "nf-core/epitopeprediction": {
        "description": "MHC epitope prediction pipeline for neoantigen identification using NetMHCpan, Syfpeithi, and FRED2 for immunotherapy applications",
        "annotation": "epitope prediction MHC neoantigen NetMHCpan Syfpeithi FRED2 immunotherapy cancer vaccine HLA",
    },
    "nf-core/methylseq": {
        "description": "Bisulfite sequencing (WGBS/RRBS) methylation analysis pipeline: alignment with Bismark or bwa-meth, CpG/CHH methylation calling and QC",
        "annotation": "bisulfite sequencing WGBS RRBS DNA methylation Bismark bwa-meth CpG methylation calling FASTQ",
    },
    "nf-core/diaproteomics": {
        "description": "Data-independent acquisition (DIA) proteomics analysis pipeline for quantitative proteomics using OpenSWATH and PyProphet",
        "annotation": "DIA proteomics data-independent acquisition OpenSWATH PyProphet quantitative mass spectrometry protein",
    },
    "nf-core/chipseq": {
        "description": "ChIP-seq analysis pipeline: read trimming, alignment (BWA), peak calling (MACS2/MACS3), differential binding, annotation, and motif enrichment",
        "annotation": "ChIP-seq peak calling MACS2 BWA differential binding transcription factor histone mark FASTQ",
    },
    "nf-core/liftover": {
        "description": "Genome coordinate liftover pipeline for converting genomic positions between assembly versions using CrossMap or UCSC liftOver",
        "annotation": "liftover coordinate conversion genome assembly CrossMap UCSC VCF BED GTF",
    },
    "nf-core/bagobugs": {
        "description": "Metagenomic analysis pipeline for profiling microbial communities from shotgun sequencing using reference-based approaches",
        "annotation": "metagenomics shotgun microbial community profiling reference-based classification abundance",
    },
    "nf-core/funcscan": {
        "description": "Functional annotation scan pipeline for predicting antimicrobial resistance genes, biosynthetic gene clusters, and virulence factors",
        "annotation": "functional annotation antimicrobial resistance AMR biosynthetic gene cluster virulence FASTA genome",
    },
    "nf-core/multiomics": {
        "description": "Multi-omics data integration pipeline combining transcriptomics, proteomics, and metabolomics for systems biology analysis",
        "annotation": "multi-omics integration transcriptomics proteomics metabolomics systems biology DIABLO MOFA",
    },
    "nf-core/proteomicslfq": {
        "description": "Label-free quantification (LFQ) proteomics pipeline using OpenMS for peptide/protein identification and quantification from DDA MS data",
        "annotation": "label-free quantification LFQ proteomics OpenMS DDA mass spectrometry peptide protein identification",
    },
    "nf-core/nascent": {
        "description": "Nascent transcription analysis pipeline for GRO-seq, PRO-seq, and TT-seq data to measure RNA synthesis rates genome-wide",
        "annotation": "nascent transcription GRO-seq PRO-seq TT-seq RNA synthesis rates transcription elongation FASTQ",
    },
    "nf-core/nanostat": {
        "description": "Oxford Nanopore sequencing quality control pipeline using NanoStat for read length, quality score, and yield statistics",
        "annotation": "Nanopore QC quality control NanoStat read length quality score yield statistics",
    },
    "nf-core/hlatyping": {
        "description": "HLA allele typing pipeline for determining HLA class I and II alleles from WGS, WES, or RNA-seq data",
        "annotation": "HLA typing allele class I II WGS WES RNA-seq OptiType immunology transplant",
    },
    "nf-core/longread_umi": {
        "description": "Long-read UMI consensus pipeline for error correction of Oxford Nanopore amplicon reads using UMI barcodes",
        "annotation": "long-read UMI consensus Nanopore amplicon error correction barcode sequencing",
    },
    "nf-core/createpanelrefs": {
        "description": "Create reference panel files for structural variant calling, CNV analysis, and panel-of-normals construction",
        "annotation": "reference panel structural variant CNV panel-of-normals PON create build",
    },
    "nf-core/pairgenomealign": {
        "description": "Pairwise genome alignment pipeline using minimap2 or LAST for whole-genome synteny and comparative genomics",
        "annotation": "pairwise genome alignment minimap2 LAST synteny comparative genomics whole genome",
    },
    "nf-core/detaxizer": {
        "description": "Host sequence decontamination pipeline for removing host reads from metagenomic or clinical sequencing samples",
        "annotation": "host decontamination removal metagenomic clinical sequencing human reads filtering",
    },
    "nf-core/demultiplex": {
        "description": "Sequencing data demultiplexing pipeline supporting Illumina BCL conversion and sample sheet-based barcode splitting",
        "annotation": "demultiplexing Illumina BCL barcode splitting sample sheet bcl2fastq",
    },
    "nf-core/bamtools": {
        "description": "BAM file processing utility subworkflow using Bamtools for filtering, sorting, and statistics on alignment files",
        "annotation": "BAM processing Bamtools filter sort statistics alignment utility",
    },
    "nf-core/deepvariant": {
        "description": "DeepVariant short-read germline variant calling pipeline using Google's deep learning approach for SNP and indel calling",
        "annotation": "DeepVariant germline variant calling deep learning SNP indel FASTQ BAM WGS WES",
    },
    "nf-core/spinningjenny": {
        "description": "Automated pipeline for generating nf-core pipeline skeletons and boilerplate code for new pipeline development",
        "annotation": "pipeline skeleton generator boilerplate nf-core development template automation",
    },
    "nf-core/illuminavariantcalling": {
        "description": "Illumina short-read variant calling pipeline for SNP and indel detection using GATK4 best practices with BQSR",
        "annotation": "Illumina short-read variant calling SNP indel GATK4 BQSR best practices",
    },
}


# ---------------------------------------------------------------------------
# Auto-annotation generation for pipelines NOT in the lookup table
# ---------------------------------------------------------------------------

# Known genomics/bioinformatics data types and associated labels
DATA_TYPE_MAP = {
    "fastq": "FASTQ reads",
    "fq": "FASTQ reads",
    "bam": "BAM alignment files",
    "cram": "CRAM alignment files",
    "vcf": "VCF variant files",
    "gvcf": "gVCF variant files",
    "bed": "BED interval files",
    "bigwig": "BigWig coverage tracks",
    "bedgraph": "bedGraph coverage files",
    "gtf": "GTF annotation",
    "gff": "GFF annotation",
    "fasta": "FASTA sequences",
    "fa": "FASTA sequences",
    "h5ad": "h5ad/AnnData single-cell matrices",
    "hic": "Hi-C contact data",
    "maf": "MAF mutation annotation",
    "pdb": "PDB structure files",
    "csv": "CSV tables",
    "tsv": "TSV tables",
    "sam": "SAM alignment files",
}

# Known tools and their short labels
TOOL_MAP = {
    "samtools": "Samtools",
    "bwa": "BWA",
    "bowtie": "Bowtie2",
    "bowtie2": "Bowtie2",
    "star": "STAR",
    "hisat2": "HISAT2",
    "salmon": "Salmon",
    "kallisto": "Kallisto",
    "rsem": "RSEM",
    "gatk": "GATK",
    "picard": "Picard",
    "fastp": "fastp",
    "fastqc": "FastQC",
    "multiqc": "MultiQC",
    "trimgalore": "Trim Galore",
    "trimmomatic": "Trimmomatic",
    "macs2": "MACS2",
    "macs3": "MACS3",
    "deeptools": "deepTools",
    "bismark": "Bismark",
    "minimap2": "minimap2",
    "bedtools": "bedtools",
    "bcftools": "BCFtools",
    "snpeff": "SnpEff",
    "vep": "VEP",
    "annovar": "ANNOVAR",
    "prokka": "Prokka",
    "bustools": "Bustools",
    "cellranger": "CellRanger",
    "umitools": "UMI-tools",
    "shapeit": "SHAPEIT",
    "glimpse": "GLIMPSE",
    "beagle": "BEAGLE",
    "freebayes": "FreeBayes",
    "strelka": "Strelka2",
    "mutect": "Mutect2",
    "varscan": "VarScan2",
    "manta": "Manta",
    "delly": "Delly",
    "lumpy": "LUMPY",
    "svaba": "SvABA",
    "cnvkit": "CNVkit",
    "mosdepth": "mosdepth",
    "qualimap": "Qualimap",
    "nanostat": "NanoStat",
    "guppy": "Guppy",
    "dorado": "Dorado",
    "cellbender": "CellBender",
    "seurat": "Seurat",
    "scanpy": "Scanpy",
    "mafft": "MAFFT",
    "muscle": "MUSCLE",
    "raxml": "RAxML",
    "iqtree": "IQ-TREE",
    "kraken": "Kraken2",
    "bracken": "Bracken",
    "metaphlan": "MetaPhlAn",
    "checkm": "CheckM",
    "prodigal": "Prodigal",
    "spades": "SPAdes",
    "megahit": "MEGAHIT",
    "flye": "Flye",
    "medaka": "Medaka",
    "pepper": "PEPPER",
    "deepvariant": "DeepVariant",
    "cellprofiler": "CellProfiler",
    "openms": "OpenMS",
    "msfragger": "MSFragger",
}

# Common bioinformatics operations and their descriptions
OPERATION_MAP = {
    "align": "align reads",
    "alignment": "align reads",
    "sort": "sort",
    "index": "index",
    "markdup": "mark duplicates in",
    "markduplicates": "mark duplicates in",
    "dedup": "deduplicate",
    "trim": "trim adapters from",
    "qc": "quality control",
    "stats": "compute statistics for",
    "convert": "convert",
    "filter": "filter",
    "merge": "merge",
    "split": "split",
    "subsample": "subsample",
    "downsample": "downsample",
    "phase": "phase",
    "impute": "impute",
    "genotype": "genotype",
    "call": "call variants in",
    "annotate": "annotate",
    "assemble": "assemble",
    "map": "map",
    "quantify": "quantify",
    "count": "count",
    "cluster": "cluster",
    "classify": "classify",
    "predict": "predict",
    "removebackground": "remove background from",
    "normalize": "normalize",
    "peak": "call peaks in",
    "pileup": "generate pileup from",
}


def _infer_annotation_from_name(
    name: str,
    existing_desc: str,
    tags: str,
    input_types: str,
    output_types: str,
) -> dict[str, str]:
    """
    Infer a description and annotation from the pipeline name and existing metadata
    for pipelines not in KNOWN_ANNOTATIONS.
    """
    # Strip the nf-core/ prefix
    short = name.replace("nf-core/", "").lower()
    parts = re.split(r"[_\-]", short)

    # Detect data types in the name
    found_types = []
    for part in parts:
        if part in DATA_TYPE_MAP:
            found_types.append(DATA_TYPE_MAP[part])

    # Detect tools in the name
    found_tools = []
    for part in parts:
        if part in TOOL_MAP:
            found_tools.append(TOOL_MAP[part])

    # Detect operations
    found_ops = []
    for part in parts:
        if part in OPERATION_MAP:
            found_ops.append(OPERATION_MAP[part])

    # Use existing description if it's decent
    use_existing_desc = existing_desc and len(existing_desc) >= 20

    # Build human-readable name from parts (capitalise meaningfully)
    readable = " ".join(p.upper() if p in DATA_TYPE_MAP else p for p in parts)

    # Build description
    if use_existing_desc and len(existing_desc) >= 60:
        description = existing_desc
    else:
        parts_desc = []
        if found_ops and found_types:
            parts_desc.append(
                f"{found_ops[0].capitalize()} {', '.join(found_types[:2])}"
            )
        elif found_types and found_tools:
            parts_desc.append(
                f"Process {', '.join(found_types[:2])} using {', '.join(found_tools[:2])}"
            )
        elif found_tools:
            parts_desc.append(
                f"Bioinformatics analysis pipeline using {', '.join(found_tools[:3])}"
            )
        elif found_types:
            parts_desc.append(
                f"Process and analyze {', '.join(found_types[:2])} data"
            )
        else:
            # Fall back to a generic cleaned-up description
            parts_desc.append(
                f"{readable.title()} nf-core pipeline"
            )
        if found_tools and found_ops:
            parts_desc.append(f"using {', '.join(found_tools[:3])}")
        description = " ".join(parts_desc)
        # Append the existing short description if it adds something
        if use_existing_desc and existing_desc not in description:
            description = f"{description}. {existing_desc.rstrip('.')}"

    # Build annotation (keyword-rich)
    annotation_parts = (
        [short.replace("_", " ").replace("-", " ")]
        + found_types
        + found_tools
        + [p for p in parts if len(p) > 2 and p not in DATA_TYPE_MAP and p not in TOOL_MAP]
    )
    # Add tags
    if tags:
        try:
            import json
            tag_list = json.loads(tags)
            annotation_parts += [str(t) for t in tag_list if isinstance(t, str)]
        except Exception:
            pass
    # Deduplicate while preserving order
    seen: set[str] = set()
    unique_parts = []
    for p in annotation_parts:
        key = p.lower()
        if key not in seen:
            seen.add(key)
            unique_parts.append(p)

    annotation = " ".join(unique_parts)
    return {"description": description, "annotation": annotation}


def main() -> None:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute(
        """
        SELECT id, name, description, annotation, tags, input_types, output_types
        FROM workflows
        WHERE source = 'nfcore'
          AND length(description) < 150
        """
    )
    rows = cur.fetchall()
    print(f"Found {len(rows)} nfcore workflows with short descriptions")

    updated = 0
    skipped = 0
    used_known = 0
    used_auto = 0

    for row in rows:
        wf_id = row["id"]
        name = row["name"] or ""
        existing_desc = row["description"] or ""
        existing_annot = row["annotation"] or ""
        tags = row["tags"] or "[]"
        input_types = row["input_types"] or "[]"
        output_types = row["output_types"] or "[]"

        if name in KNOWN_ANNOTATIONS:
            data = KNOWN_ANNOTATIONS[name]
            new_desc = data["description"]
            new_annot = data["annotation"]
            used_known += 1
        else:
            data = _infer_annotation_from_name(
                name, existing_desc, tags, input_types, output_types
            )
            new_desc = data["description"]
            new_annot = data["annotation"]
            used_auto += 1

        # Only update description if the current one is genuinely short
        update_desc = len(existing_desc) < 100
        # Always update annotation (the FTS-searchable field)
        update_annot = True

        if not update_desc and len(existing_annot) > len(new_annot):
            # Existing annotation is already richer — skip
            skipped += 1
            continue

        try:
            if update_desc:
                cur.execute(
                    "UPDATE workflows SET description = ?, annotation = ? WHERE id = ?",
                    (new_desc, new_annot, wf_id),
                )
            else:
                cur.execute(
                    "UPDATE workflows SET annotation = ? WHERE id = ?",
                    (new_annot, wf_id),
                )
            updated += 1
        except Exception as exc:
            print(f"  ERROR updating {name} (id={wf_id}): {exc}")

    conn.commit()

    # Rebuild FTS index
    print("Rebuilding FTS index...")
    try:
        cur.execute("INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')")
        conn.commit()
        print("FTS rebuild complete.")
    except Exception as exc:
        print(f"FTS rebuild warning: {exc}")

    conn.close()

    print(f"\nSummary:")
    print(f"  Total candidates : {len(rows)}")
    print(f"  Updated          : {updated}")
    print(f"  Skipped (rich)   : {skipped}")
    print(f"  Used lookup table: {used_known}")
    print(f"  Auto-generated   : {used_auto}")


if __name__ == "__main__":
    main()
