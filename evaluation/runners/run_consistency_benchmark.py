#!/usr/bin/env python3
"""
run_consistency_benchmark.py — Track 5A: Consistency & Stability Benchmark

Three-tier evaluation:

  Tier 1 — Routing stability (deterministic queries)
    Queries that are specific enough to route directly without clarification.
    BioMate should select the same workflow across K runs.
    Target: ≥95% of deterministic queries fully consistent.

  Tier 2 — Clarification quality (ambiguous queries)
    Queries that lack enough context to route deterministically.
    BioMate SHOULD ask a clarifying question rather than route blindly.
    Two sub-scores:
      - Clarification rate: % of runs where BioMate asks (vs silently routes)
      - Dimension accuracy: does the question target the right ambiguity dimension?
    Target: ≥90% clarification rate on genuinely ambiguous queries.

  Tier 3 — Paraphrase stability (deterministic paraphrase groups)
    Multiple phrasings of the same specific intent should route to the same workflow.
    Target: ≥85% of paraphrase groups consistent.

Design principle:
    BioMate's clarification questions are a FEATURE, not a routing failure.
    Ambiguous queries are annotated with expected clarification dimensions.
    The benchmark rewards asking the right question, not forcing a route.

Usage:
    python runners/run_consistency_benchmark.py
    python runners/run_consistency_benchmark.py --runs-per-query 3 --tier all
    python runners/run_consistency_benchmark.py --tier clarification
"""

import argparse
import json
import re
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient


# ---------------------------------------------------------------------------
# Tier 1 — Deterministic queries
# Each entry: (query, expected_category)
# These are specific enough that BioMate should route directly every run.
# ---------------------------------------------------------------------------
DETERMINISTIC_QUERIES = [
    # RNA-seq / bulk
    ("Run RNA-seq differential expression analysis on human tumor vs normal samples", "rnaseq"),
    ("RNA-seq with STAR aligner and DESeq2 for cancer transcriptomics", "rnaseq"),
    # Variant calling / WGS
    ("Perform GATK germline variant calling on WGS data from patient with Lynch syndrome", "variant_calling"),
    ("Variant calling with GATK HaplotypeCaller on whole genome sequencing data", "variant_calling"),
    # ATAC-seq / ChIP-seq / open chromatin
    ("Run ATAC-seq analysis to identify open chromatin regions in mouse T cells", "atac_seq"),
    ("ChIP-seq peak calling for H3K27ac histone mark in mouse embryonic stem cells", "chip_seq"),
    ("CUT&RUN chromatin profiling for transcription factor binding in HEK293 cells", "chip_seq"),
    ("Open chromatin peak calling from ATAC-seq data", "atac_seq"),
    # Methylation
    ("Bisulfite sequencing analysis for DNA methylation profiling", "bisulfite_seq"),
    ("WGBS bisulfite sequencing methylation analysis across CpG sites", "bisulfite_seq"),
    # Drug discovery
    ("ADMET prediction for a small molecule SMILES string CC(=O)Oc1ccccc1C(=O)O", "admet"),
    ("Run molecular docking with AutoDock Vina on a protein-ligand complex", "molecular_docking"),
    ("AlphaFold structure prediction for a novel protein sequence", "alphafold"),
    ("AMBER molecular dynamics simulation for a solvated protein system", "molecular_dynamics"),
    # Proteomics
    ("DIA-NN proteomics analysis from data-independent acquisition mass spec data", "proteomics_dia"),
    ("Run DIA proteomics with DIA-NN on raw Thermo data files", "proteomics_dia"),
    ("Label-free quantification proteomics analysis with MaxQuant", "proteomics_lfq"),
    # Single cell
    ("Single-cell RNA-seq clustering and cell type annotation with Seurat", "scrna_seq"),
    ("scRNA-seq trajectory analysis to study T cell differentiation with 10x Genomics data", "scrna_seq"),
    # Metagenomics
    ("16S rRNA amplicon sequencing analysis for gut microbiome profiling", "metagenomics"),
    ("Shotgun metagenomics taxonomic classification with Kraken2", "metagenomics"),
    # Structural biology
    ("CryoEM single particle analysis from raw micrograph movies", "cryo_em"),
    ("Cryo-EM helical reconstruction for filament proteins", "cryo_em"),
    ("X-ray crystallography structure determination from diffraction data", "xray_crystallography"),

    # ── RNA-seq variants ──────────────────────────────────────────────────
    ("lncRNA quantification and differential expression from total RNA-seq with ribo-depletion", "rnaseq"),
    ("miRNA-seq small RNA sequencing analysis to identify differentially expressed microRNAs", "rnaseq"),
    ("Strand-specific RNA-seq analysis with dUTP library protocol on mouse liver samples", "rnaseq"),
    ("Total RNA-seq with Ribo-Zero depletion for transcriptome profiling including non-coding RNA", "rnaseq"),
    ("Isoform-level differential expression from RNA-seq using Salmon and DEXSeq", "rnaseq"),
    ("Ribosome profiling Ribo-seq analysis for translation efficiency quantification", "rnaseq"),

    # ── Somatic / structural variant calling ─────────────────────────────
    ("Somatic variant calling from tumor-normal paired WGS samples using GATK Mutect2", "variant_calling"),
    ("Tumor-normal somatic SNV and indel calling pipeline with Mutect2 and Strelka2", "variant_calling"),
    ("Structural variant detection from WGS data using DELLY and Manta callers", "variant_calling"),
    ("Copy number variation analysis from whole exome sequencing data", "variant_calling"),
    ("Joint genotyping of multiple WGS samples with GATK GenotypeGVCFs", "variant_calling"),

    # ── scRNA-seq variants ────────────────────────────────────────────────
    ("Multi-sample scRNA-seq integration and batch correction with Harmony or BBKNN", "scrna_seq"),
    ("Doublet detection and removal from single-cell RNA-seq data using Scrublet", "scrna_seq"),
    ("Single-nucleus RNA-seq snRNA-seq analysis of frozen brain tissue from 10x Chromium", "scrna_seq"),
    ("CITE-seq multimodal single-cell analysis integrating RNA and protein ADT data", "scrna_seq"),
    ("scRNA-seq velocity analysis with scVelo to study dynamic gene expression", "scrna_seq"),
    ("Single-cell RNA-seq cell-cell communication analysis using CellChat or NicheNet", "scrna_seq"),

    # ── Spatial transcriptomics ───────────────────────────────────────────
    ("10x Visium spatial transcriptomics analysis to map gene expression in tissue sections", "spatial_transcriptomics"),
    ("Spatial transcriptomics data analysis with Seurat for tissue region identification", "spatial_transcriptomics"),
    ("MERFISH spatial transcriptomics single-molecule FISH data analysis pipeline", "spatial_transcriptomics"),

    # ── Long-read sequencing ──────────────────────────────────────────────
    ("Oxford Nanopore long-read sequencing assembly and variant calling pipeline", "long_read_seq"),
    ("PacBio HiFi CCS reads genome assembly and polishing with Canu and Medaka", "long_read_seq"),
    ("Nanopore direct RNA sequencing for full-length transcript isoform detection", "long_read_seq"),
    ("Long-read structural variant calling from Oxford Nanopore WGS data with Sniffles", "long_read_seq"),

    # ── CRISPR screen ─────────────────────────────────────────────────────
    ("MAGeCK CRISPR pooled screen analysis to identify essential genes from sgRNA counts", "crispr_screen"),
    ("CRISPR screen differential enrichment analysis with MAGeCK MLE on dropout screen data", "crispr_screen"),
    ("Genome-wide CRISPR knockout screen analysis using CRISPResso2 and MAGeCK", "crispr_screen"),

    # ── Hi-C / 3D chromatin ───────────────────────────────────────────────
    ("Hi-C chromatin conformation capture analysis for 3D genome organization", "hic"),
    ("TAD topologically associating domain calling from in-situ Hi-C data", "hic"),
    ("Micro-C high-resolution chromatin contact map analysis with deeptools", "hic"),

    # ── Proteomics (additional) ───────────────────────────────────────────
    ("Phosphoproteomics analysis with TiO2 enriched samples using MaxQuant and Perseus", "proteomics_phospho"),
    ("TMT-labeled isobaric quantification proteomics analysis from multiplexed mass spec data", "proteomics_tmt"),
    ("Proteomics data analysis with Fragpipe MSFragger for DDA shotgun proteomics", "proteomics_lfq"),

    # ── Drug discovery (additional) ───────────────────────────────────────
    ("REINVENT4 generative de novo drug design to produce novel drug-like molecules", "generative_design"),
    ("IVIVE in vitro to in vivo extrapolation pharmacokinetics modeling for drug candidates", "pharmacokinetics"),
    ("Virtual screening and lead optimization with REINVENT4 scaffold hopping", "generative_design"),
    ("CYP450 drug-drug interaction panel analysis for ADME profiling", "admet"),

    # ── Cryo-EM / Cryo-ET ─────────────────────────────────────────────────
    ("Cryo-EM subtomogram averaging from cryo-electron tomography tilt series", "cryo_em"),
    ("CryoSPARC Ab initio model building from cryo-EM single particle images", "cryo_em"),
    ("Cryo-EM helical filament reconstruction for amyloid fiber structure determination", "cryo_em"),
    ("RELION SPA cryo-EM data processing from motion-corrected micrographs", "cryo_em"),

    # ── Metabolomics ──────────────────────────────────────────────────────
    ("Untargeted metabolomics LC-MS data processing with XCMS for metabolite identification", "metabolomics"),
    ("Targeted metabolomics MRM panel quantification from triple-quadrupole mass spec", "metabolomics"),
    ("NMR metabolomics data processing and statistical analysis for biomarker discovery", "metabolomics"),

    # ── Metagenomics (additional) ─────────────────────────────────────────
    ("HUMAnN2 functional profiling of shotgun metagenomics data for pathway abundance", "metagenomics"),
    ("Metagenome-assembled genomes MAGs binning with MetaBAT2 from shotgun metagenomics", "metagenomics"),
    ("Strain-level metagenomics analysis with StrainPhlAn for microbial strain tracking", "metagenomics"),

    # ── GWAS / eQTL ───────────────────────────────────────────────────────
    ("GWAS genome-wide association study analysis with PLINK2 for complex trait genetics", "gwas"),
    ("eQTL expression quantitative trait locus mapping with tensorQTL on RNA-seq data", "gwas"),
    ("Polygenic risk score calculation and GWAS summary statistics analysis", "gwas"),

    # ── Additional assorted specific queries ─────────────────────────────
    ("ChIP-seq H3K4me3 active promoter histone mark analysis in primary human T cells", "chip_seq"),
    ("Single-cell ATAC-seq scATAC-seq chromatin accessibility analysis with ArchR", "atac_seq"),
    ("CircRNA circular RNA detection from total RNA-seq with CIRI2 and find_circ", "rnaseq"),
    ("Bulk RNA-seq co-expression network analysis with WGCNA", "rnaseq"),
    ("WES whole exome sequencing variant calling and annotation with VEP Ensembl", "variant_calling"),
    ("TCR repertoire V(D)J sequencing analysis from 10x Genomics immune profiling", "scrna_seq"),
    ("DIA proteomics spectral library building with Spectronaut from data-independent acquisition", "proteomics_dia"),
    ("GROMACS protein-ligand molecular dynamics free energy calculation with MM-GBSA", "molecular_dynamics"),

    # ── Additional coverage to reach 100 ─────────────────────────────────
    ("Differential chromatin accessibility analysis between two cell states with ATAC-seq", "atac_seq"),
    ("Genome-wide DNA methylation profiling by RRBS reduced representation bisulfite sequencing", "bisulfite_seq"),
    ("Single-cell multiome ATAC plus gene expression analysis using 10x Multiome kit", "scrna_seq"),
    ("Long-read full-length 16S rRNA amplicon sequencing on Oxford Nanopore for microbiome", "metagenomics"),
    ("CUT&TAG chromatin profiling for H3K4me3 histone mark genome-wide mapping", "chip_seq"),
    ("Proteome-wide phosphorylation site analysis from EGF-stimulated HeLa cells mass spec data", "proteomics_phospho"),
    ("Molecular docking with DiffDock neural network-based pose prediction for drug candidates", "molecular_docking"),
    ("CRISPR base editing screen analysis to quantify guide efficiency from amplicon sequencing", "crispr_screen"),
    ("Oxford Nanopore RNA direct sequencing for m6A RNA modification detection with m6anet", "long_read_seq"),
    ("ChIP-seq signal normalization and differential binding analysis with DiffBind", "chip_seq"),
    ("Allele-specific methylation analysis from WGBS data in imprinted genomic regions", "bisulfite_seq"),
    ("Cryo-EM tilt-series alignment and 3D reconstruction for cryo-electron tomography", "cryo_em"),
    ("scRNA-seq ambient RNA decontamination with SoupX followed by doublet removal", "scrna_seq"),
    ("Label-free proteomics with Fragpipe and MSstats for statistical differential analysis", "proteomics_lfq"),

    # ── Final 4 to reach 100 ─────────────────────────────────────────────
    ("Spatial transcriptomics analysis with 10x Visium to identify spatially variable genes", "spatial_transcriptomics"),
    ("Hi-C data processing for TAD calling and chromatin loop annotation with Juicer", "hic"),
    ("Targeted metabolomics absolute quantification from HILIC-MS data using internal standards", "metabolomics"),
    ("GWAS imputation quality filtering and fine-mapping with SuSiE from summary statistics", "gwas"),
]

# ---------------------------------------------------------------------------
# Tier 2 — Ambiguous queries
# Each entry: (query, [expected_clarification_dimensions])
# BioMate should ask about at least one of the listed dimensions.
# Routing directly without clarification = failure.
# ---------------------------------------------------------------------------
AMBIGUOUS_QUERIES = [
    (
        "Analyze sequencing data from my cancer samples",
        ["sequencing type", "data type", "analysis type", "what kind", "type of sequencing",
         "dna", "rna", "wgs", "wes", "atac", "chip", "what analysis"],
        "Should ask: What type of sequencing? (WGS/WES/RNA-seq/ATAC/ChIP-seq?)"
    ),
    (
        "Help me process my mass spec data",
        ["acquisition", "dia", "dda", "proteomics", "metabolomics", "type of mass",
         "data-dependent", "data-independent", "targeted", "what instrument"],
        "Should ask: DDA or DIA? Proteomics or metabolomics?"
    ),
    (
        "I need to run a bioinformatics workflow on my data",
        ["what data", "what type", "what analysis", "what kind", "data type",
         "analysis goal", "fastq", "sequencing", "describe"],
        "Should ask: What data type and analysis goal?"
    ),
    (
        "Analyze my genomics data",
        ["sequencing type", "what type", "what kind", "dna", "rna", "wgs", "chip",
         "data type", "analysis type"],
        "Should ask: What type of genomics data and analysis?"
    ),
    (
        "Run an analysis on my biological samples",
        ["what type", "what data", "what analysis", "sample type", "what kind",
         "sequencing", "proteomics", "describe your"],
        "Should ask: What type of biological data and analysis?"
    ),
    (
        "I have some NGS data I need to process",
        ["what type", "what kind", "rna", "dna", "atac", "chip", "wgs", "wes",
         "sequencing type", "analysis goal"],
        "Should ask: What type of NGS data? (RNA-seq, WGS, ATAC-seq?)"
    ),
    (
        "Help me analyze my omics data",
        ["what type", "what kind", "genomics", "proteomics", "metabolomics",
         "transcriptomics", "which omics", "data type"],
        "Should ask: Which omics type? (genomics/proteomics/transcriptomics?)"
    ),
    (
        "Process my sequencing reads",
        ["what type", "what kind", "rna", "dna", "analysis", "wgs", "amplicon",
         "sequencing type", "what analysis"],
        "Should ask: What type of sequencing and analysis goal?"
    ),

    # ── Data type clear, analysis goal ambiguous ──────────────────────────
    (
        "I have RNA-seq data from mouse brain tissue",
        ["what analysis", "differential", "trajectory", "single cell", "bulk",
         "goal", "what do you want to do", "analysis type", "what would you like"],
        "Should ask: What analysis do you want? (DE, trajectory, splicing, co-expression?)"
    ),
    (
        "I have ChIP-seq peaks and I want to find regulatory targets",
        ["motif", "target gene", "nearby gene", "annotation", "enrichment",
         "what tool", "method", "approach", "homer", "great", "meme"],
        "Should ask: Motif enrichment, nearest-gene annotation, or pathway enrichment?"
    ),
    (
        "Run differential analysis on my sequencing data",
        ["what type", "rna", "atac", "chip", "dna methylation", "protein",
         "sequencing type", "what kind of data", "data type"],
        "Should ask: What type of sequencing data? (RNA-seq, ATAC-seq, ChIP-seq?)"
    ),
    (
        "Analyze my tissue samples for disease biomarkers",
        ["sequencing", "proteomics", "metabolomics", "histology", "what type",
         "data type", "how were", "sample prep", "assay", "platform"],
        "Should ask: What data type? (RNA-seq, proteomics, metabolomics, imaging?)"
    ),

    # ── Multiple applicable workflows ─────────────────────────────────────
    (
        "Analyze my ChIP-seq peaks for motif enrichment and gene targets",
        ["motif", "nearest gene", "annotation", "homer", "meme", "great",
         "separate", "both", "which", "order", "workflow"],
        "Should ask: Run motif enrichment only, target gene annotation only, or both?"
    ),
    (
        "I need to process and quantify my mass spec proteomics data",
        ["dia", "dda", "data-independent", "data-dependent", "label free",
         "tmt", "itraq", "acquisition mode", "instrument", "raw file format"],
        "Should ask: DDA or DIA acquisition? Label-free or isobaric labeling (TMT)?"
    ),
    (
        "Identify variants from my cancer sequencing data",
        ["somatic", "germline", "tumor-normal", "paired", "single sample",
         "wgs", "wes", "panel", "exome", "tumor only", "what type"],
        "Should ask: Somatic (tumor-normal) or germline? WGS, WES, or targeted panel?"
    ),
    (
        "Run a metagenomics analysis on my samples",
        ["16s", "shotgun", "amplicon", "whole metagenome", "taxonomic",
         "functional", "what type", "sequencing strategy", "v3-v4"],
        "Should ask: 16S amplicon or shotgun whole-metagenome sequencing?"
    ),

    # ── Tool / method preference unclear ─────────────────────────────────
    (
        "I want to cluster my single-cell data and find cell types",
        ["seurat", "scanpy", "monocle", "tool", "software", "python",
         "r", "which", "preference", "platform"],
        "Should ask: Seurat (R) or Scanpy (Python)? Any reference atlas for annotation?"
    ),
    (
        "Predict protein structure from my FASTA sequence",
        ["alphafold", "rosettafold", "esm", "esmfold", "single sequence",
         "multiple sequence alignment", "msa", "tool preference", "which model"],
        "Should ask: AlphaFold2 (with MSA) or ESMFold (single-sequence, faster)?"
    ),
    (
        "I want to do GWAS analysis on my cohort data",
        ["sample size", "ancestry", "imputation", "phenotype", "continuous",
         "binary", "plink", "regenie", "tool", "what phenotype"],
        "Should ask: Binary or quantitative phenotype? Imputed or directly-genotyped data?"
    ),
    (
        "Perform genome assembly from my sequencing data",
        ["short read", "long read", "illumina", "nanopore", "pacbio",
         "hybrid", "organism size", "ploidy", "sequencing technology"],
        "Should ask: Short-read (Illumina), long-read (Nanopore/PacBio), or hybrid assembly?"
    ),

    # ── Sample type creates ambiguity ─────────────────────────────────────
    (
        "Process my tissue samples from a clinical study",
        ["what assay", "sequencing", "proteomics", "histology", "what data",
         "what type", "platform", "rna", "dna", "how processed"],
        "Should ask: What assay was performed? (RNA-seq, proteomics, histology, DNA-seq?)"
    ),
    (
        "Analyze data from my mouse model experiment",
        ["what data", "what assay", "rna-seq", "chip-seq", "wgs", "proteomics",
         "what type", "sequencing", "platform", "goal"],
        "Should ask: What type of data from the mouse experiment? What analysis goal?"
    ),
    (
        "I need to characterize the immune landscape of my tumor samples",
        ["scrna", "bulk rna", "flow cytometry", "cytof", "multiplex ihc",
         "deconvolution", "what data", "platform", "sequencing"],
        "Should ask: scRNA-seq, bulk RNA-seq deconvolution, CyTOF, or multiplex imaging?"
    ),
    (
        "Quantify gene expression in my samples",
        ["bulk rna", "single cell", "scrna", "plate based", "droplet",
         "10x", "smart-seq", "what platform", "how many cells", "tissue"],
        "Should ask: Bulk RNA-seq or single-cell RNA-seq? What sequencing platform?"
    ),
    (
        "Run pathway analysis on my data",
        ["what data", "rna-seq", "proteomics", "metabolomics", "gene list",
         "what input", "differentially expressed", "upstream", "downstream"],
        "Should ask: What input data? (DE gene list, proteomics fold-changes, metabolomics?)"
    ),
    (
        "I have multi-omics data and want to integrate it",
        ["what types", "rna", "atac", "protein", "methylation", "which omics",
         "layers", "integration method", "mofa", "diablo", "mixomics"],
        "Should ask: Which omics layers? (RNA+ATAC? RNA+protein? RNA+methylation?)"
    ),
    (
        "Perform epigenomics analysis on my samples",
        ["atac", "chip", "cut and run", "wgbs", "rrbs", "mnase",
         "what type", "histone mark", "dna methylation", "chromatin"],
        "Should ask: ATAC-seq, ChIP-seq, CUT&RUN, or bisulfite methylation sequencing?"
    ),
    (
        "I want to study chromatin accessibility in my cells",
        ["atac", "cut and run", "mnase", "single cell", "bulk",
         "what cells", "protocol", "platform", "10x multiome"],
        "Should ask: Bulk ATAC-seq, single-cell scATAC-seq, or CUT&RUN? What cell type?"
    ),

    # ── Two more to reach 30 ─────────────────────────────────────────────
    (
        "I have long-read sequencing data from my samples",
        ["nanopore", "pacbio", "oxford", "hifi", "assembly", "variant",
         "what analysis", "what goal", "genome assembly", "isoform", "methylation"],
        "Should ask: Oxford Nanopore or PacBio? Genome assembly, variant calling, or isoform detection?"
    ),
    (
        "Analyze drug candidates from my virtual screening run",
        ["docking", "admet", "molecular dynamics", "what next step",
         "what analysis", "binding affinity", "pkpd", "prioritize", "rank"],
        "Should ask: Which analysis step? Docking poses, ADMET filtering, or MD simulation?"
    ),
]

# ---------------------------------------------------------------------------
# Tier 3 — Paraphrase groups (deterministic only)
# All variants of each group should route to the same workflow category.
# ---------------------------------------------------------------------------
PARAPHRASE_GROUPS = [
    {
        "expected_category": "rnaseq",
        "queries": [
            "Run RNA-seq differential expression analysis on human cancer samples",
            "I have RNA-seq reads from tumor and normal tissue, find differentially expressed genes",
            "Perform bulk RNA sequencing gene expression analysis with DESeq2",
        ],
    },
    {
        "expected_category": "variant_calling",
        "queries": [
            "Germline variant calling on whole genome sequencing data",
            "GATK HaplotypeCaller variant calling pipeline for WGS samples",
            "Identify SNPs and indels from WGS data using GATK best practices",
        ],
    },
    {
        "expected_category": "admet",
        "queries": [
            "ADMET properties for a drug-like small molecule CC(=O)Oc1ccccc1C(=O)O",
            "Predict absorption, distribution, metabolism, excretion, and toxicity for my compound",
            "Check pharmacokinetics of SMILES CC(C)Cc1ccc(cc1)C(=O)O — ADMET analysis",
        ],
    },
    {
        "expected_category": "proteomics_dia",
        "queries": [
            "DIA proteomics analysis from Thermo mass spectrometry raw files using DIA-NN",
            "Run DIA-NN on my data-independent acquisition proteomics dataset",
            "Data-independent acquisition proteomics — quantify proteins with DIA-NN software",
        ],
    },
    {
        "expected_category": "alphafold",
        "queries": [
            "Predict the 3D structure of my protein using AlphaFold",
            "Run AlphaFold2 protein structure prediction from a FASTA sequence file",
            "I need a protein 3D structure model from an amino acid sequence — use AlphaFold",
        ],
    },
    {
        "expected_category": "scrna_seq",
        "queries": [
            "Single-cell RNA-seq analysis of PBMCs using Seurat",
            "scRNA-seq clustering and cell type annotation for 10x Genomics data",
            "Perform single cell transcriptomics analysis to identify cell populations",
        ],
    },

    # ── New paraphrase groups ─────────────────────────────────────────────
    {
        "expected_category": "metagenomics",
        "queries": [
            "16S rRNA amplicon sequencing analysis for gut microbiome community profiling",
            "Amplicon-based 16S metagenomics pipeline for microbiome diversity analysis",
            "Analyze gut microbiome composition from 16S rRNA sequencing reads using QIIME2",
        ],
    },
    {
        "expected_category": "cryo_em",
        "queries": [
            "CryoEM single particle analysis to reconstruct protein structure at near-atomic resolution",
            "Process cryo-EM micrographs with CTF correction and particle picking for SPA",
            "Run cryoSPARC single particle reconstruction from raw movie frames",
        ],
    },
    {
        "expected_category": "scrna_seq",
        "queries": [
            "scRNA-seq trajectory inference to study hematopoietic differentiation",
            "Single-cell RNA sequencing analysis with RNA velocity and Monocle pseudotime",
            "Reconstruct developmental trajectory from 10x Genomics single-cell data",
        ],
    },
    {
        "expected_category": "bisulfite_seq",
        "queries": [
            "WGBS whole genome bisulfite sequencing analysis for DNA methylation mapping",
            "Bisulfite sequencing pipeline with Bismark for CpG methylation profiling",
            "Whole-genome methylation analysis from paired-end bisulfite-converted FASTQ reads",
        ],
    },
    {
        "expected_category": "chip_seq",
        "queries": [
            "ChIP-seq analysis for H3K27me3 polycomb repressive mark in differentiated cells",
            "ChIP-seq peak calling pipeline for broad histone mark H3K27me3",
            "Identify H3K27me3 enriched regions from ChIP-seq data using MACS2 broad mode",
        ],
    },
    {
        "expected_category": "atac_seq",
        "queries": [
            "ATAC-seq open chromatin analysis to map regulatory elements in T cells",
            "Assay for transposase-accessible chromatin ATAC-seq pipeline for peak calling",
            "Run nf-core/atacseq to identify accessible chromatin regions from FASTQ reads",
        ],
    },
    {
        "expected_category": "molecular_dynamics",
        "queries": [
            "GROMACS molecular dynamics simulation of protein in explicit solvent",
            "Run MD simulation for protein-ligand complex using AMBER force field",
            "Protein molecular dynamics 100 ns simulation with GROMACS for stability analysis",
        ],
    },
    {
        "expected_category": "proteomics_lfq",
        "queries": [
            "Label-free quantification proteomics with MaxQuant on DDA mass spectrometry data",
            "MaxQuant LFQ proteomics analysis from Thermo Orbitrap raw files",
            "Shotgun proteomics label-free quantification pipeline for differential protein expression",
        ],
    },
    {
        "expected_category": "variant_calling",
        "queries": [
            "Somatic mutation calling from matched tumor-normal WGS pair with GATK Mutect2",
            "Tumor-normal paired somatic variant detection pipeline using nf-core/sarek",
            "Identify somatic SNVs and indels in cancer WGS data with matched normal control",
        ],
    },
    {
        "expected_category": "generative_design",
        "queries": [
            "REINVENT4 de novo drug design to generate novel small molecules with target activity",
            "Generative molecular design with REINVENT4 reinforcement learning for lead optimization",
            "Run REINVENT4 scaffold decoration to produce drug-like analogs around a core scaffold",
        ],
    },
    {
        "expected_category": "admet",
        "queries": [
            "Predict ADMET properties and drug-likeness for a series of small molecule candidates",
            "ADMET screening pipeline for absorption, distribution, metabolism, excretion, and toxicity",
            "Run in silico pharmacokinetics ADME prediction for my compound library SMILES",
        ],
    },
    {
        "expected_category": "crispr_screen",
        "queries": [
            "MAGeCK CRISPR screen analysis to rank essential genes from pooled dropout screen",
            "Analyze CRISPR knockout screen with MAGeCK MLE to find fitness genes",
            "CRISPR pooled library screen pipeline: trim sgRNA reads, count, and run MAGeCK",
        ],
    },
    {
        "expected_category": "rnaseq",
        "queries": [
            "lncRNA differential expression analysis from ribo-depleted total RNA-seq data",
            "Long non-coding RNA quantification and DE analysis with nf-core/rnaseq",
            "Total RNA-seq with Ribo-Zero for lncRNA and mRNA co-analysis using DESeq2",
        ],
    },
    {
        "expected_category": "gwas",
        "queries": [
            "GWAS genome-wide association study on my cohort genotype data with PLINK2",
            "Run PLINK2 genome-wide association analysis for a binary disease phenotype",
            "Identify genetic loci associated with BMI from my genotype array data using PLINK",
        ],
    },
]


# ---------------------------------------------------------------------------
# Category extraction (same as before)
# ---------------------------------------------------------------------------
_WORKFLOW_CATEGORY_MAP = [
    # Single-cell before generic RNA-seq to avoid false matches
    (["scrna", "single-cell", "seurat", "scanpy", "umap", "cell cluster", "single cell",
      "cite-seq", "snrna", "single nucleus", "10x chromium", "scrublet", "cellchat"], "scrna_seq"),
    (["sarek", "haplotypecaller", "gatk", "germline variant", "variant calling", "snp", "indel",
      "mutect2", "strelka", "structural variant", "copy number", "delly", "manta"], "variant_calling"),
    (["rnaseq", "rna-seq", "differential expression", "deseq2", "rna seq", "star aligner",
      "lncrna", "mirna", "ribosome profiling", "ribo-seq", "circrna", "wgcna"], "rnaseq"),
    (["spatial transcriptomics", "visium", "merfish", "slide-seq", "spatially variable",
      "tissue section", "spatial gene expression"], "spatial_transcriptomics"),
    (["hi-c", "hic ", "topologically associating", "tad", "micro-c", "chromatin contact",
      "3d genome", "juicer", "hicpro"], "hic"),
    (["atac-seq", "atac seq", "open chromatin", "atacseq", "scatac"], "atac_seq"),
    (["chip-seq", "chipseq", "h3k27ac", "peak calling", "chip seq", "cut&run", "cutrun",
      "cut&tag", "cuttag", "h3k4me3", "h3k27me3", "diffbind"], "chip_seq"),
    (["bisulfite", "methylation", "wgbs", "cpg", "rrbs", "allele-specific methylation"], "bisulfite_seq"),
    (["crispr screen", "mageck", "crispresso", "pooled screen", "sgrna count",
      "base editing screen", "crispr knockout screen"], "crispr_screen"),
    (["nanopore", "pacbio", "oxford nanopore", "long-read", "long read", "hifi",
      "direct rna sequencing", "full-length transcript", "sniffles", "m6anet"], "long_read_seq"),
    (["metabolomics", "xcms", "mrm", "hilic-ms", "nmr metabol", "lc-ms metabol",
      "metabolite identification", "triple-quadrupole"], "metabolomics"),
    (["gwas", "genome-wide association", "eqtl", "polygenic risk", "plink", "regenie",
      "fine-mapping", "susie", "imputation quality"], "gwas"),
    (["phosphoproteomic", "phosphoproteomics", "tio2 enriched", "phosphorylation site",
      "proteome-wide phospho"], "proteomics_phospho"),
    (["tmt-labeled", "tmt proteomics", "isobaric quantification", "itraq", "tmt"], "proteomics_tmt"),
    (["autodock", "docking", "vina", "molecular docking", "diffdock"], "molecular_docking"),
    (["admet", "pharmacokinetic", "absorption, distribution", "cyp450", "cyp ddi",
      "in silico pharmacokinetics"], "admet"),
    (["ivive", "in vitro to in vivo", "pkpd", "pharmacokinetics model"], "pharmacokinetics"),
    (["alphafold", "protein structure prediction", "protein 3d structure", "structure prediction",
      "rosettafold", "esmfold"], "alphafold"),
    (["amber", "gromacs", "molecular dynamics", "md simulation", "pmemd", "mm-gbsa"], "molecular_dynamics"),
    (["dia-nn", "diaproteomics", "dia proteomics", "data-independent acquisition", "dia-ms",
      "spectronaut", "openswath"], "proteomics_dia"),
    (["maxquant", "label-free", "label free quantification", "lfq proteomics",
      "fragpipe", "msfragger", "msstats"], "proteomics_lfq"),
    (["cryosparc", "cryo-em", "cryo em", "cryoem", "single particle", "micrograph",
      "subtomogram", "relion", "ctf correction"], "cryo_em"),
    (["helical reconstruction", "filament", "cryo-et", "cryoet", "tilt-series",
      "cryo-electron tomography"], "cryo_em"),
    (["x-ray", "crystallography", "diffraction"], "xray_crystallography"),
    (["kraken", "metagenom", "metaphlan", "16s", "microbiome", "amplicon",
      "humann", "metabat", "strainphlan", "mag binning"], "metagenomics"),
    (["blast", "hmmer", "pfam", "protein family", "sequence homology"], "sequence_analysis"),
    (["reinvent", "generative design", "de novo drug", "scaffold decoration", "scaffold hopping"], "generative_design"),
]


def _extract_workflow_category(response_text: str) -> str:
    r = response_text.lower()
    for keywords, category in _WORKFLOW_CATEGORY_MAP:
        if any(kw in r for kw in keywords):
            return category
    return "none"


def _is_clarification_response(response_text: str) -> bool:
    """
    Return True if BioMate responded with a clarifying question rather than
    routing directly to a workflow.

    BioMate clarification responses contain "**Missing:**" preamble AND a "?"
    question directed at the user. A pure routing response contains
    "**Running:** workflow" and a named workflow card.
    """
    r = response_text.lower()
    has_question = "?" in response_text
    has_missing_block = "**missing:" in r or "missing:" in r
    has_routing_preamble = "**running:**" in r and "workflow" in r
    # Workflow card: response contains a bold workflow name with "—" description
    has_workflow_card = bool(re.search(r"\*\*[A-Z][^*]{5,50}[A-Z][^*]*\*\*\s*[—\-]", response_text))

    # Clarification: asks a question AND does NOT commit to a specific workflow
    if has_question and not has_workflow_card:
        return True
    if has_missing_block and has_question:
        return True
    return False


def _clarification_hits_dimension(response_text: str, dimensions: list[str]) -> bool:
    """
    Return True if the clarification question addresses at least one of the
    expected ambiguity dimensions.
    """
    r = response_text.lower()
    return any(dim.lower() in r for dim in dimensions)


def _run_query(client, query: str) -> tuple[str, str]:
    """Return (raw_response_text, workflow_category)."""
    try:
        response = client.ask(query)
        text = response.text if hasattr(response, "text") else str(response)
        return text, _extract_workflow_category(text)
    except Exception as exc:
        return f"error:{exc}", "error"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Consistency Benchmark (3-tier)")
    parser.add_argument("--output", default="results/consistency_benchmark/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--runs-per-query", type=int, default=3,
                        help="Runs per deterministic query (default: 3)")
    parser.add_argument("--tier", choices=["routing", "clarification", "paraphrase", "all"],
                        default="all", help="Which tier(s) to run")
    parser.add_argument("--max-queries", type=int, default=None,
                        help="Limit deterministic queries (for quick runs)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    det_queries = DETERMINISTIC_QUERIES
    if args.max_queries:
        det_queries = det_queries[:args.max_queries]

    if args.dry_run:
        n_routing = len(det_queries) * args.runs_per_query if args.tier in ("routing", "all") else 0
        n_clarify = len(AMBIGUOUS_QUERIES) * 2 if args.tier in ("clarification", "all") else 0
        n_para = sum(len(g["queries"]) for g in PARAPHRASE_GROUPS) if args.tier in ("paraphrase", "all") else 0
        print(f"Consistency Benchmark (3-tier) — dry run")
        print(f"  Tier 1 routing:       {n_routing} calls  ({len(det_queries)} queries × {args.runs_per_query} runs)")
        print(f"  Tier 2 clarification: {n_clarify} calls  ({len(AMBIGUOUS_QUERIES)} queries × 2 runs)")
        print(f"  Tier 3 paraphrase:    {n_para} calls  ({len(PARAPHRASE_GROUPS)} groups)")
        print(f"  Total: {n_routing + n_clarify + n_para} API calls")
        return

    client = BioMateEvalClient.from_config(config)
    concurrency = config.get("concurrency", {}).get("max_parallel_tasks", 8)
    report = {}

    # ── Tier 1: Routing stability ──────────────────────────────────────────
    if args.tier in ("routing", "all"):
        print(f"\n── Tier 1: Routing stability ({len(det_queries)} queries × {args.runs_per_query} runs) ──")
        run_results: dict[str, list[str]] = {f"q{i:02d}": [] for i in range(len(det_queries))}
        expected_map = {f"q{i:02d}": cat for i, (_, cat) in enumerate(det_queries)}

        tasks = [
            (f"q{i:02d}", query, run_idx)
            for i, (query, _) in enumerate(det_queries)
            for run_idx in range(args.runs_per_query)
        ]
        completed = 0
        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = {
                pool.submit(_run_query, client, query): (qid, run_idx, query)
                for qid, query, run_idx in tasks
            }
            for future in as_completed(futures):
                qid, run_idx, query = futures[future]
                _, category = future.result()
                run_results[qid].append(category)
                completed += 1
                print(f"  [{completed:3d}/{len(tasks)}] {qid} run{run_idx+1}: {category}")

        # Score routing stability
        consistent_count = 0
        wrong_workflow = 0
        routing_details = {}
        for qid, categories in sorted(run_results.items()):
            valid = [c for c in categories if c != "error"]
            expected = expected_map[qid]
            all_same = len(set(valid)) <= 1 and len(valid) == args.runs_per_query
            # Check if consistent but wrong workflow
            dominant = Counter(valid).most_common(1)[0][0] if valid else "none"
            correct_workflow = dominant == expected or (
                # Allow partial matches for closely related categories
                (expected == "chip_seq" and dominant in ("chip_seq", "atac_seq")) or
                (expected == "cryo_em" and dominant == "cryo_em")
            )
            if all_same:
                consistent_count += 1
            if not correct_workflow and all_same:
                wrong_workflow += 1
            routing_details[qid] = {
                "query": det_queries[int(qid[1:])][0],
                "expected": expected,
                "results": valid,
                "consistent": all_same,
                "dominant": dominant,
                "correct_workflow": correct_workflow,
            }

        consistency_rate = consistent_count / len(det_queries) if det_queries else 0
        report["routing_stability"] = {
            "n_queries": len(det_queries),
            "runs_per_query": args.runs_per_query,
            "n_consistent": consistent_count,
            "consistency_rate": consistency_rate,
            "n_wrong_workflow_consistent": wrong_workflow,
            "details": routing_details,
        }

        print(f"\nRouting stability: {consistent_count}/{len(det_queries)} = {consistency_rate:.1%}")
        if wrong_workflow:
            print(f"  Note: {wrong_workflow} queries route consistently but to wrong workflow")

        # Print inconsistencies
        for qid, d in routing_details.items():
            if not d["consistent"]:
                print(f"  INCONSISTENT {qid}: {d['query'][:55]}")
                print(f"    expected={d['expected']}  results={d['results']}")
            elif not d["correct_workflow"]:
                print(f"  WRONG WORKFLOW {qid}: {d['query'][:55]}")
                print(f"    expected={d['expected']}  got={d['dominant']} (consistent but wrong)")

    # ── Tier 2: Clarification quality ─────────────────────────────────────
    if args.tier in ("clarification", "all"):
        print(f"\n── Tier 2: Clarification quality ({len(AMBIGUOUS_QUERIES)} ambiguous queries × 2 runs) ──")
        clarification_results = []
        clarify_tasks = [
            (i, query, dims, note, run_idx)
            for i, (query, dims, note) in enumerate(AMBIGUOUS_QUERIES)
            for run_idx in range(2)
        ]
        completed = 0
        raw_responses: dict[int, list[str]] = {i: [] for i in range(len(AMBIGUOUS_QUERIES))}

        with ThreadPoolExecutor(max_workers=min(concurrency, len(AMBIGUOUS_QUERIES))) as pool:
            futures = {
                pool.submit(_run_query, client, query): (i, query, dims, note, run_idx)
                for i, query, dims, note, run_idx in clarify_tasks
            }
            for future in as_completed(futures):
                i, query, dims, note, run_idx = futures[future]
                text, category = future.result()
                raw_responses[i].append(text)
                is_clarify = _is_clarification_response(text)
                completed += 1
                print(f"  [{completed:2d}/{len(clarify_tasks)}] q{i} run{run_idx+1}: "
                      f"{'ASKED ?' if is_clarify else f'ROUTED→{category}'}")

        for i, (query, dims, note) in enumerate(AMBIGUOUS_QUERIES):
            texts = raw_responses[i]
            clarify_runs = sum(1 for t in texts if _is_clarification_response(t))
            dim_hits = sum(1 for t in texts if _clarification_hits_dimension(t, dims))
            clarification_results.append({
                "query": query,
                "note": note,
                "n_runs": len(texts),
                "clarification_rate": clarify_runs / len(texts) if texts else 0,
                "dimension_accuracy": dim_hits / len(texts) if texts else 0,
                "n_clarified": clarify_runs,
                "n_on_target": dim_hits,
            })
            status = "✅" if clarify_runs == len(texts) else ("⚠️" if clarify_runs > 0 else "❌")
            print(f"  {status} [{clarify_runs}/{len(texts)} asked] [{dim_hits}/{len(texts)} on-target] "
                  f"{query[:55]}")

        n_full_clarify = sum(1 for r in clarification_results if r["clarification_rate"] == 1.0)
        n_any_clarify = sum(1 for r in clarification_results if r["clarification_rate"] > 0)
        overall_clarify_rate = sum(r["clarification_rate"] for r in clarification_results) / len(clarification_results)
        overall_dim_rate = sum(r["dimension_accuracy"] for r in clarification_results) / len(clarification_results)

        report["clarification_quality"] = {
            "n_queries": len(AMBIGUOUS_QUERIES),
            "n_always_clarifies": n_full_clarify,
            "n_sometimes_clarifies": n_any_clarify,
            "overall_clarification_rate": overall_clarify_rate,
            "overall_dimension_accuracy": overall_dim_rate,
            "details": clarification_results,
        }

        print(f"\nClarification rate: {overall_clarify_rate:.1%}  "
              f"(always={n_full_clarify}/{len(AMBIGUOUS_QUERIES)}, "
              f"sometimes={n_any_clarify}/{len(AMBIGUOUS_QUERIES)})")
        print(f"Dimension accuracy: {overall_dim_rate:.1%}  "
              f"(question targets the right ambiguity)")

    # ── Tier 3: Paraphrase stability ───────────────────────────────────────
    if args.tier in ("paraphrase", "all"):
        print(f"\n── Tier 3: Paraphrase stability ({len(PARAPHRASE_GROUPS)} groups) ──")
        paraphrase_results = []
        para_tasks = [
            (gi, query, group["expected_category"])
            for gi, group in enumerate(PARAPHRASE_GROUPS)
            for query in group["queries"]
        ]
        para_responses: dict[int, list[str]] = {gi: [] for gi in range(len(PARAPHRASE_GROUPS))}

        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = {
                pool.submit(_run_query, client, query): (gi, query, exp_cat)
                for gi, query, exp_cat in para_tasks
            }
            for future in as_completed(futures):
                gi, query, exp_cat = futures[future]
                _, category = future.result()
                para_responses[gi].append(category)
                print(f"  group={PARAPHRASE_GROUPS[gi]['expected_category']}: {query[:45]:45} → {category}")

        for gi, group in enumerate(PARAPHRASE_GROUPS):
            categories = para_responses[gi]
            exp = group["expected_category"]
            valid = [c for c in categories if c != "error"]
            counts = Counter(valid)
            dominant = counts.most_common(1)[0][0] if counts else "none"
            all_same = len(set(valid)) <= 1
            all_correct = all(c == exp for c in valid)
            paraphrase_results.append({
                "expected_category": exp,
                "results": valid,
                "consistent": all_same,
                "correct": all_correct,
                "dominant": dominant,
            })
            status = "✅" if all_correct else ("⚠️" if all_same else "❌")
            print(f"  {status} {exp}: {valid}  (expected={exp})")

        n_consistent = sum(1 for r in paraphrase_results if r["consistent"])
        n_correct = sum(1 for r in paraphrase_results if r["correct"])
        report["paraphrase_stability"] = {
            "n_groups": len(PARAPHRASE_GROUPS),
            "n_consistent": n_consistent,
            "n_correct": n_correct,
            "details": paraphrase_results,
        }
        print(f"\nParaphrase: consistent={n_consistent}/{len(PARAPHRASE_GROUPS)}  "
              f"correct={n_correct}/{len(PARAPHRASE_GROUPS)}")

    # ── Save and summarise ─────────────────────────────────────────────────
    report_path = output_dir / "consistency_report.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved to: {report_path}")

    print(f"\n{'='*60}")
    print("CONSISTENCY BENCHMARK SUMMARY (3-tier)")
    print(f"{'='*60}")
    if "routing_stability" in report:
        rs = report["routing_stability"]
        print(f"  Tier 1 — Routing stability:    {rs['consistency_rate']:.1%} "
              f"(target ≥95%)  [{rs['n_consistent']}/{rs['n_queries']}]")
    if "clarification_quality" in report:
        cq = report["clarification_quality"]
        print(f"  Tier 2 — Clarification rate:   {cq['overall_clarification_rate']:.1%} "
              f"(target ≥90%)  [{cq['n_always_clarifies']}/{cq['n_queries']} always ask]")
        print(f"         — Dimension accuracy:   {cq['overall_dimension_accuracy']:.1%} "
              f"(target ≥80%)  [question targets right ambiguity]")
    if "paraphrase_stability" in report:
        ps = report["paraphrase_stability"]
        print(f"  Tier 3 — Paraphrase stability: {ps['n_correct']/ps['n_groups']:.1%} "
              f"(target ≥85%)  [{ps['n_correct']}/{ps['n_groups']}]")


if __name__ == "__main__":
    main()
