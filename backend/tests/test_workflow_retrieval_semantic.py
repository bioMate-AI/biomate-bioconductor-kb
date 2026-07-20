"""
Semantic Workflow Retrieval — Use-Case Test Suite

Each test case captures a real failure mode of the current FTS/BM25 retrieval:
  - Paraphrase: user's vocabulary ≠ workflow name
  - Input-format discrimination: same analysis goal, different input → different workflow
  - Function boundary: similar-sounding workflows with different purposes
  - Multi-hop inference: user describes outcome, not process

Each case is a dict:
  query           — natural language user request (as typed in the chat box)
  correct         — expected top-1 workflow name (ground truth)
  confusable      — workflow(s) the current FTS retriever commonly returns instead
  failure_mode    — category of failure (paraphrase / input_format / function_boundary / multi_hop / log_regression)
  notes           — why this is a hard case

failure_mode values:
  paraphrase       — user vocabulary ≠ workflow name/description keywords
  input_format     — same goal, different input format → different workflow
  function_boundary — similar-sounding workflows with different experimental purposes
  multi_hop        — user describes outcome, retriever must infer the method
  semantic         — cases where semantic description should beat keyword matching
  log_regression   — documented production failures from evaluation runs, evaluation docs,
                     or inline comments in unified_workflow_search.py; these MUST pass

Run with:
  pytest tests/test_workflow_retrieval_semantic.py -v
  pytest tests/test_workflow_retrieval_semantic.py -v -k "hard"    # only hard cases
  pytest tests/test_workflow_retrieval_semantic.py --retrieval-only  # skip LLM-generated query step

To run P@1 evaluation across all cases:
  python tests/test_workflow_retrieval_semantic.py --eval
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
sys.path.insert(0, str(ROOT))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402


# ──────────────────────────────────────────────────────────────────────────────
# Ground-truth cases
# ──────────────────────────────────────────────────────────────────────────────

CASES = [

    # ── Input-format discrimination ──────────────────────────────────────────
    # These are the most common real failure: the right workflow depends on what
    # the user *already has*, not just what they want to do.

    {
        "id": "rnaseq_from_fastq",
        "query": "I have paired-end FASTQ files from bulk RNA-seq, align them and get gene counts",
        "correct": "nf-core/rnaseq",
        "confusable": ["nf-core/differentialabundance"],
        "failure_mode": "input_format",
        "notes": "User has FASTQ. differentialabundance requires a count matrix as input.",
    },
    {
        "id": "de_from_count_matrix",
        "query": "I already have a count matrix from RNA-seq. I want to find differentially expressed genes between two conditions.",
        "correct": "nf-core/differentialabundance",
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "input_format",
        "notes": "User already has counts. rnaseq starts from FASTQ. FTS scores rnaseq higher because 'RNA-seq' dominates keywords.",
    },
    {
        "id": "scrna_from_fastq",
        "query": "Process my 10X Genomics single-cell RNA-seq FASTQ files and produce a cell-by-gene count matrix",
        "correct": "nf-core/scrnaseq",
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "input_format",
        "notes": "Single-cell FASTQ → scrnaseq, not bulk rnaseq. Both take FASTQ+samplesheet, FTS can confuse them.",
    },
    {
        "id": "methylation_wgbs",
        "query": "I have bisulfite-converted whole genome sequencing reads, analyse CpG methylation",
        "correct": "nf-core/methylseq",
        "confusable": ["nf-core/methylarray"],
        "failure_mode": "input_format",
        "notes": "WGBS FASTQ → methylseq. methylarray is for Illumina EPIC/450k array data (.idat), not sequencing reads.",
    },
    {
        "id": "methylation_array",
        "query": "I ran the Illumina EPIC methylation array. Analyze my IDAT files for differentially methylated regions.",
        "correct": "nf-core/methylarray",
        "confusable": ["nf-core/methylseq"],
        "failure_mode": "input_format",
        "notes": "Illumina array (.idat) → methylarray. methylseq only processes sequencing (FASTQ) data.",
    },
    {
        "id": "bam_to_fastq",
        "query": "Convert my aligned BAM file back to FASTQ so I can re-align with a different reference",
        "correct": "nf-core/bamtofastq",
        "confusable": ["nf-core/rnaseq", "nf-core/sarek"],
        "failure_mode": "input_format",
        "notes": "Input is BAM, not FASTQ. Output is FASTQ. FTS may score alignment pipelines higher on 're-align' keyword.",
    },
    {
        "id": "bcl_demux",
        "query": "I got the raw BCL output from the Illumina sequencer, I need FASTQ files for each sample",
        "correct": "nf-core/bcl_demultiplex",
        "confusable": ["nf-core/demultiplex"],
        "failure_mode": "input_format",
        "notes": "Input is BCL flowcell directory, not FASTQ. This is a sequencer-output conversion step, not analysis.",
    },

    # ── Function boundary ─────────────────────────────────────────────────────
    # Workflows with overlapping names/domains but fundamentally different purposes.

    {
        "id": "atacseq_no_antibody",
        "query": "Open chromatin profiling using Tn5 transposase — no antibody used, just ATAC-seq",
        "correct": "nf-core/atacseq",
        "confusable": ["nf-core/chipseq", "nf-core/cutandrun"],
        "failure_mode": "function_boundary",
        "notes": "ATAC-seq: Tn5 transposase, no antibody. ChIP-seq: antibody IP. CUT&RUN: antibody + pA-MNase. All are chromatin profiling.",
    },
    {
        "id": "chipseq_antibody",
        "query": "I did a ChIP experiment with an H3K27ac antibody, now I have FASTQ files and want peak calling",
        "correct": "nf-core/chipseq",
        "confusable": ["nf-core/atacseq", "nf-core/cutandrun"],
        "failure_mode": "function_boundary",
        "notes": "Antibody-based ChIP → chipseq. The word 'peak calling' appears in all three; antibody presence is the discriminator.",
    },
    {
        "id": "cutandrun_antibody",
        "query": "CUT&RUN experiment with antibody against H3K4me3, process my reads and call peaks",
        "correct": "nf-core/cutandrun",
        "confusable": ["nf-core/chipseq", "nf-core/atacseq"],
        "failure_mode": "function_boundary",
        "notes": "CUT&RUN uses pA-MNase, not sonication. Different from ChIP-seq. The pipeline is also different (SEACR vs MACS2).",
    },
    {
        "id": "hic_conformation",
        "query": "3D genome organization analysis — I have Hi-C data and want TAD boundaries and contact maps",
        "correct": "nf-core/hic",
        "confusable": ["nf-core/atacseq", "nf-core/chipseq"],
        "failure_mode": "function_boundary",
        "notes": "Hi-C = chromatin conformation capture, not open chromatin or protein-DNA binding. Different biology entirely.",
    },
    {
        "id": "somatic_variant_tumor_normal",
        "query": "Call somatic mutations from matched tumor and normal WGS samples",
        "correct": "nf-core/sarek",
        "acceptable": ["Detect And Annotate Somatic Mutations"],
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "function_boundary",
        "notes": "Tumor-normal somatic variant calling → sarek. BioMate's 'Detect And Annotate Somatic Mutations' is also a valid answer.",
    },
    {
        "id": "tcr_bcr_repertoire",
        "query": "Analyze T-cell receptor and B-cell receptor repertoires from my VDJ sequencing data",
        "correct": "nf-core/airrflow",
        "confusable": ["nf-core/rnaseq", "nf-core/scrnaseq"],
        "failure_mode": "function_boundary",
        "notes": "AIRR/VDJ repertoire analysis is distinct from general RNA-seq. FTS may score rnaseq/scrnaseq higher on 'sequencing'.",
    },
    {
        "id": "amplicon_16s",
        "query": "16S rRNA amplicon sequencing — characterize gut microbiome composition and diversity",
        "correct": "nf-core/ampliseq",
        "confusable": ["nf-core/taxprofiler", "nf-core/mag"],
        "failure_mode": "function_boundary",
        "notes": "16S amplicon → ampliseq (ASV/OTU). taxprofiler is for shotgun metagenomics reads. mag is for assembly+binning.",
    },
    {
        "id": "shotgun_metagenomics_taxa",
        "query": "Taxonomic profiling of shotgun metagenomic reads — what species are present in my sample?",
        "correct": "nf-core/taxprofiler",
        "confusable": ["nf-core/ampliseq", "nf-core/mag"],
        "failure_mode": "function_boundary",
        "notes": "Shotgun taxa profiling → taxprofiler. ampliseq is for amplicon (16S) data. mag assembles + bins, doesn't profile.",
    },
    {
        "id": "metagenome_assembly",
        "query": "Assemble metagenomic reads into contigs, bin them into MAGs, and assess completeness",
        "correct": "nf-core/mag",
        "confusable": ["nf-core/taxprofiler", "nf-core/ampliseq"],
        "failure_mode": "function_boundary",
        "notes": "Assembly + binning → mag. taxprofiler classifies but doesn't assemble. FTS may score all three similarly on 'metagenomics'.",
    },
    {
        "id": "crispr_screen",
        "query": "I did a CRISPR knockout screen, analyze editing efficiency and identify on-target indels",
        "correct": "nf-core/crisprseq",
        "confusable": ["nf-core/sarek"],
        "failure_mode": "function_boundary",
        "notes": "CRISPR editing analysis (indels at guide sites) ≠ somatic variant calling. Different biology, different pipeline.",
    },
    {
        "id": "ancient_dna",
        "query": "Process ancient DNA sequences — map degraded short reads accounting for DNA damage patterns",
        "correct": "nf-core/eager",
        "confusable": ["nf-core/sarek", "nf-core/rnaseq"],
        "failure_mode": "function_boundary",
        "notes": "Ancient DNA has characteristic C→T damage, very short fragments. eager handles mapDamage, decontamination, etc.",
    },
    {
        "id": "bacterial_assembly",
        "query": "Assemble a bacterial genome from Illumina short reads and annotate the genes",
        "correct": "nf-core/bacass",
        "confusable": ["nf-core/mag"],
        "failure_mode": "function_boundary",
        "notes": "Single bacterial genome assembly+annotation → bacass. mag is for multi-sample metagenomic assembly and binning.",
    },

    # ── Paraphrase ────────────────────────────────────���───────────────────────
    # User uses colloquial or field-specific terms that don't appear in workflow names/descriptions.

    {
        "id": "paraphrase_scrna_10x",
        "query": "Run Chromium single-cell analysis on my 10X FASTQ files",
        "correct": "nf-core/scrnaseq",
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "paraphrase",
        "notes": "'Chromium' is the 10X instrument brand — synonymous with 10X single-cell but not in workflow name.",
    },
    {
        "id": "paraphrase_de_genes",
        "query": "Find genes that are up- or down-regulated between my treatment and control groups",
        "correct": "nf-core/differentialabundance",
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "paraphrase",
        "notes": "'Up/down-regulated' = differential expression. User hasn't said what input format they have.",
        # NOTE: this case is input-format-ambiguous too — the test accepts either rnaseq or differentialabundance
        "acceptable": ["nf-core/rnaseq", "nf-core/differentialabundance"],
    },
    {
        "id": "paraphrase_wgbs",
        "query": "WGBS data analysis — I want CpG methylation levels across the genome",
        "correct": "nf-core/methylseq",
        "confusable": ["nf-core/methylarray"],
        "failure_mode": "paraphrase",
        "notes": "WGBS (Whole Genome Bisulfite Sequencing) is the full name for what methylseq processes. Acronym not in workflow name.",
    },
    {
        "id": "paraphrase_ncrna",
        "query": "I have total RNA-seq data including non-coding RNAs, process FASTQ and quantify all transcripts",
        "correct": "nf-core/rnaseq",
        "confusable": ["nf-core/smrnaseq"],
        "failure_mode": "paraphrase",
        "notes": "Total RNA-seq → rnaseq with appropriate strandedness/quantification settings. smrnaseq is for small RNA specifically.",
    },
    {
        "id": "paraphrase_immune_repertoire",
        "query": "Clonotype analysis from B-cell sequencing — what are the dominant antibody clones in my sample?",
        "correct": "nf-core/airrflow",
        "confusable": ["nf-core/rnaseq", "nf-core/scrnaseq"],
        "failure_mode": "paraphrase",
        "notes": "'Clonotype', 'dominant clones', 'B-cell sequencing' = AIRR repertoire. Not in workflow name.",
    },
    {
        "id": "paraphrase_gut_microbiome",
        "query": "Characterize the microbial community in stool samples using 16S amplicons",
        "correct": "nf-core/ampliseq",
        "confusable": ["nf-core/taxprofiler"],
        "failure_mode": "paraphrase",
        "notes": "'Microbial community', 'stool samples', '16S amplicons' are all synonyms for ampliseq use case.",
    },

    # ── Multi-hop inference ───────────────────────────────────────────────────
    # User describes the scientific goal, not the bioinformatics method.
    # The LLM must infer what workflow is needed.

    {
        "id": "multihop_open_chromatin",
        "query": "Which genomic regions are accessible in my cell type? I want to identify active regulatory elements.",
        "correct": "nf-core/atacseq",
        "confusable": ["nf-core/chipseq"],
        "failure_mode": "multi_hop",
        "notes": "'Accessible regions' + 'regulatory elements' → open chromatin → ATAC-seq. User didn't name the assay.",
    },
    {
        "id": "multihop_cell_type_annotation",
        "query": "I want to know what cell types are present in my tumor biopsy at single-cell resolution",
        "correct": "nf-core/scrnaseq",
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "multi_hop",
        "notes": "Cell type annotation at single-cell resolution → scRNA-seq pipeline. FTS 'tumor biopsy' may pull cancer workflows.",
    },
    {
        "id": "multihop_de_genes_from_fastq",
        "query": "My collaborator sent me raw sequencing files. I want to know which genes change between treated and untreated cells.",
        "correct": "nf-core/rnaseq",
        "confusable": ["nf-core/differentialabundance"],
        "failure_mode": "multi_hop",
        "notes": "'Raw sequencing files' = FASTQ → must do rnaseq first before differentialabundance. Two-step inference.",
    },
    {
        "id": "multihop_protein_binding_site",
        "query": "Where does the transcription factor bind in the genome? I have ChIP data.",
        "correct": "nf-core/chipseq",
        "confusable": ["nf-core/atacseq"],
        "failure_mode": "multi_hop",
        "notes": "Transcription factor binding = ChIP-seq. ATAC-seq profiles open chromatin but doesn't identify TF binding directly.",
    },
    {
        "id": "multihop_microbiome_diversity",
        "query": "Compare alpha and beta diversity between two patient cohorts in a gut microbiome study",
        "correct": "nf-core/ampliseq",
        "confusable": ["nf-core/taxprofiler"],
        "failure_mode": "multi_hop",
        "notes": "Alpha/beta diversity comparison is the statistical output of amplicon (16S) analysis. taxprofiler doesn't output diversity metrics.",
    },
    {
        "id": "multihop_chromatin_looping",
        "query": "Identify chromatin loops and topologically associated domains in my proximity ligation data",
        "correct": "nf-core/hic",
        "confusable": ["nf-core/atacseq", "nf-core/chipseq"],
        "failure_mode": "multi_hop",
        "notes": "'Proximity ligation' = Hi-C. TADs and loops are Hi-C outputs. ATAC/ChIP can't detect 3D genome structure.",
    },

    # ── Log-regression (documented in codebase) ──────────────────────────────
    # Real routing failures extracted from evaluation runs, evaluation docs,
    # and inline comments in unified_workflow_search.py.  These are the cases
    # that motivated the semantic query rewriting design.

    {
        "id": "log_diann_to_rnaseq",
        "query": "Run DIA-NN on raw Thermo .raw files from my proteomics experiment",
        "correct": "Dia Proteomics Analysis",
        "acceptable": ["nf-core/diaproteomics", "nf-core/dia_proteomics_analysis"],
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "log_regression",
        "notes": (
            "DIA-NN misroutes to RNA-seq ~1/3 of runs (docs/20260414_EVALUATION_LESSONS_AND_IMPROVEMENTS.md §2.5). "
            "Root cause: 'acquisition' keyword overlaps with sequencing context in routing distribution. "
            "DIA-NN is a mass-spec tool; Thermo .raw are mass-spec files, not FASTQ. "
            "Any of the three DIA proteomics workflows is a correct answer."
        ),
    },
    {
        "id": "log_diann_paraphrase",
        "query": "Quantify proteins from data-independent acquisition mass spectrometry data",
        "correct": "Dia Proteomics Analysis",
        "acceptable": ["nf-core/diaproteomics", "nf-core/dia_proteomics_analysis"],
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "log_regression",
        "notes": (
            "Paraphrase variant of the DIA-NN routing bug (same §2.5 root cause). "
            "'Data-independent acquisition' is the full DIA modality name; no tool name given. "
            "FTS sees 'acquisition' and may score RNA-seq higher. "
            "Any DIA proteomics workflow is acceptable."
        ),
    },
    {
        "id": "log_bulk_rnaseq_de_vs_rnaseq",
        "query": "Run RNA-seq pipeline on my paired-end FASTQ files to get a count matrix",
        "correct": "nf-core/rnaseq",
        "confusable": ["bulk_rnaseq_de_analysis"],
        "failure_mode": "log_regression",
        "notes": (
            "Dense rescue DISABLED because bulk_rnaseq_de_analysis ranked above nf-core/rnaseq, "
            "causing P@1 regression 0.742 → 0.417 (unified_workflow_search.py ~line 988). "
            "User has FASTQ and needs alignment+quantification; DE analysis requires a count matrix as input."
        ),
    },
    {
        "id": "log_pksim_vs_pbpk_native",
        "query": "Run PK-Sim PBPK simulation for my small molecule compound",
        "correct": "pk_sim_pbpk",
        "confusable": ["pbpk_simulation"],
        "failure_mode": "log_regression",
        "notes": (
            "User explicitly names PK-Sim (licensed tool). pk_sim_pbpk is the wrapper for it. "
            "pbpk_simulation is the BioMate-native PBPK workflow with ~22pt FTS advantage on generic PBPK terms "
            "(unified_workflow_search.py line 403 comment). The special-cased boost for 'pk-sim'/'pksim' keywords "
            "should make pk_sim_pbpk rank first — this test verifies that boost is working."
        ),
    },
    {
        "id": "log_epitopeprediction_vs_mhcquant",
        "query": "Predict MHC class I epitopes from my protein sequence using NetMHCpan",
        "correct": "nf-core/epitopeprediction",
        "confusable": ["nf-core/mhcquant"],
        "failure_mode": "log_regression",
        "notes": (
            "epitopeprediction = in-silico epitope prediction from sequence (no MS data needed). "
            "mhcquant = LC-MS immunopeptidomics (requires raw mass-spec files). "
            "Both workflows contain 'MHC' and 'epitope' in their names. "
            "The special-casing in unified_workflow_search.py line 1872 penalises mhcquant when "
            "there's prediction intent but no MS data signal — this test verifies that penalty."
        ),
    },
    {
        "id": "log_mhcquant_lc_ms",
        "query": "Identify HLA-presented peptides from my LC-MS/MS immunopeptidomics data",
        "correct": "nf-core/mhcquant",
        "confusable": ["nf-core/epitopeprediction"],
        "failure_mode": "log_regression",
        "notes": (
            "Reverse of log_epitopeprediction_vs_mhcquant. User has LC-MS/MS data (raw mass-spec files). "
            "mhcquant processes experimental immunopeptidomics data; epitopeprediction works from sequence alone. "
            "'LC-MS/MS' is the discriminating signal that should route to mhcquant."
        ),
    },

    # ── Semantic query advantage cases ────────────────────────────────────────
    # Cases where a well-formed semantic description should dramatically
    # outperform keyword matching.

    {
        "id": "semantic_scrna_de",
        "query": "Single-cell differential expression — I have an annotated h5ad with cell type labels and want to compare conditions",
        "correct": "nf-core/differentialabundance",
        "confusable": ["nf-core/scrnaseq", "nf-core/rnaseq"],
        "failure_mode": "semantic",
        "notes": "Input is h5ad (processed scRNA-seq), goal is DE between conditions. differentialabundance accepts count matrices from scRNA-seq too.",
    },
    {
        "id": "semantic_wgbs_vs_array",
        "query": "I used Bismark to map my reads, now I want DMR analysis between case and control",
        "correct": "nf-core/methylseq",
        "confusable": ["nf-core/methylarray"],
        "failure_mode": "semantic",
        "notes": "Bismark is the bisulfite aligner used by methylseq. DMR = differentially methylated regions (methylseq output).",
    },
    {
        "id": "semantic_somatic_cnv",
        "query": "Detect copy number alterations and structural variants in my cancer whole-genome sequencing data",
        "correct": "nf-core/sarek",
        "confusable": ["nf-core/rnaseq"],
        "failure_mode": "semantic",
        "notes": "CNV + SV from WGS in cancer → sarek. Requires understanding that sarek handles somatic CNV/SV, not just SNVs.",
    },
    {
        "id": "semantic_mag_binning",
        "query": "I sequenced a complex environmental sample and want to reconstruct individual microbial genomes",
        "correct": "nf-core/mag",
        "confusable": ["nf-core/taxprofiler", "nf-core/ampliseq"],
        "failure_mode": "semantic",
        "notes": "Reconstructing individual genomes from a community = MAG (metagenome-assembled genomes). taxprofiler only classifies, doesn't reconstruct.",
    },

    # ── Extended cases: Round 2 (added after description enrichment + anchor fix) ──

    # input_format
    {
        "id": "bcl_to_fastq_illumina",
        "query": "My Illumina sequencer finished and I have the BCL output folder, how do I get FASTQ files per sample",
        "correct": "nf-core/bcl_demultiplex",
        "confusable": ["nf-core/fetchngs", "nf-core/demultiplex"],
        "failure_mode": "input_format",
        "notes": "BCL flowcell directory → per-sample FASTQ. Requires bcl-convert/bcl2fastq demultiplexing. Not a public database download.",
    },
    {
        "id": "bam_convert_re_align",
        "query": "Extract reads from my BAM file and convert back to FASTQ so I can re-map them",
        "correct": "nf-core/bamtofastq",
        "confusable": ["nf-core/sarek", "nf-core/rnaseq"],
        "failure_mode": "input_format",
        "notes": "BAM → FASTQ extraction/conversion. Cleaner query avoids 'align' keyword dominating FTS toward alignment subworkflows.",
    },
    {
        "id": "methylation_epic_idat",
        "query": "Differential methylation analysis from Illumina EPIC array IDAT files comparing tumor vs normal",
        "correct": "nf-core/methylarray",
        "confusable": ["nf-core/methylseq"],
        "failure_mode": "input_format",
        "notes": "EPIC array IDAT files → methylarray. methylseq only handles bisulfite sequencing FASTQ, not array data.",
    },

    # function_boundary
    {
        "id": "fetchngs_sra_download",
        "query": "Download raw sequencing data from SRA using accession numbers SRR12345678",
        "correct": "nf-core/fetchngs",
        "confusable": ["nf-core/rnaseq", "nf-core/sarek"],
        "failure_mode": "function_boundary",
        "notes": "Fetching public data from SRA/ENA/GEO is a distinct step before any analysis pipeline.",
    },
    {
        "id": "rnafusion_tumor",
        "query": "Detect gene fusions in RNA-seq from a pediatric cancer tumor sample",
        "correct": "nf-core/rnafusion",
        "confusable": ["nf-core/sarek", "nf-core/rnaseq"],
        "failure_mode": "function_boundary",
        "notes": "Gene fusion detection from RNA-seq is rnafusion (STAR-Fusion, Arriba). sarek is DNA variant calling.",
    },
    {
        "id": "viralrecon_sars",
        "query": "Assemble SARS-CoV-2 genome from Illumina amplicon sequencing using the ARTIC protocol",
        "correct": "nf-core/viralrecon",
        "confusable": ["nf-core/mag", "nf-core/rnaseq"],
        "failure_mode": "function_boundary",
        "notes": "Viral assembly from amplicon enrichment is viralrecon. mag is for shotgun metagenome assembly.",
    },
    {
        "id": "hic_3d_genome",
        "query": "Generate Hi-C contact maps and find topologically associating domains from proximity ligation sequencing",
        "correct": "nf-core/hic",
        "confusable": ["nf-core/atacseq", "nf-core/chipseq"],
        "failure_mode": "function_boundary",
        "notes": "Hi-C proximity ligation → 3D chromatin structure. TADs and loops are Hi-C outputs. ATAC/ChIP measure 1D features.",
    },
    {
        "id": "eager_ancient_dna",
        "query": "Map ancient DNA from archaeological bone samples and assess C-to-T damage patterns",
        "correct": "nf-core/eager",
        "confusable": ["nf-core/sarek", "nf-core/rnaseq"],
        "failure_mode": "function_boundary",
        "notes": "Ancient DNA requires aDNA-specific handling: damage patterns, short fragments, MapDamage. sarek is for modern clinical DNA.",
    },
    {
        "id": "airrflow_bcr",
        "query": "Analyze B-cell receptor repertoire from immunoglobulin amplicon sequencing to track clonal evolution",
        "correct": "nf-core/airrflow",
        "confusable": ["nf-core/rnaseq", "nf-core/ampliseq"],
        "failure_mode": "function_boundary",
        "notes": "BCR/TCR adaptive immune repertoire analysis using Immcantation. 16S ampliseq is for microbiome, not immune repertoire.",
    },

    # paraphrase
    {
        "id": "paraphrase_cuttag_h3k27me3",
        "query": "Profile repressive histone marks genome-wide using CUT&TAG with anti-H3K27me3 antibody",
        "correct": "nf-core/cutandrun",
        "confusable": ["nf-core/chipseq", "nf-core/atacseq"],
        "failure_mode": "paraphrase",
        "notes": "CUT&TAG is an antibody-based method handled by nf-core/cutandrun, not ChIP-seq. ATAC-seq uses no antibody.",
    },
    {
        "id": "paraphrase_taxprofiler_species",
        "query": "Identify which microbial species are present in my shotgun metagenome sequencing reads",
        "correct": "nf-core/taxprofiler",
        "confusable": ["nf-core/ampliseq", "nf-core/mag"],
        "failure_mode": "paraphrase",
        "notes": "Taxonomic profiling from shotgun reads → taxprofiler. ampliseq is amplicon-based. mag does assembly, not classification.",
    },

    # multi_hop
    {
        "id": "multihop_10x_cell_types",
        "query": "I ran the 10X Genomics Chromium workflow on my tumor biopsy and want to see what cell types are present",
        "correct": "nf-core/scrnaseq",
        "confusable": ["nf-core/rnaseq", "nf-core/scdownstream"],
        "failure_mode": "multi_hop",
        "notes": "10X Chromium → scRNA-seq FASTQ → scrnaseq for Cell Ranger processing. scdownstream is for already-processed matrices.",
    },
    {
        "id": "multihop_metagenome_diversity",
        "query": "Characterize the microbiome diversity in my gut samples from shotgun sequencing",
        "correct": "nf-core/taxprofiler",
        "confusable": ["nf-core/ampliseq", "nf-core/mag"],
        "failure_mode": "multi_hop",
        "notes": "Shotgun metagenome diversity → taxprofiler for taxonomy. ampliseq needs 16S amplicon reads. mag reconstructs genomes, not diversity profiles.",
    },
]


# ──────────────────────────────────────────────────────────────────────────────
# Fixtures
# ──────────────────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def search():
    return UnifiedWorkflowSearch()


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def top_names(search_results, n=5):
    return [m.name for m in search_results[:n]]


def assert_in_top_k(results, correct, k, acceptable=None, case_id=""):
    names = top_names(results, k)
    targets = set([correct] + (acceptable or []))
    assert any(t in names for t in targets), (
        f"[{case_id}] Expected one of {targets} in top-{k}; got {names}"
    )


# ──────────────────────────────────────────────────────────────────────────────
# P@1 tests (strict) — correct workflow must be rank 1
# ──────────────────────────────────────────────────────────────────────────────

class TestTop1:
    """Correct workflow must appear at rank 1. These document the current FTS baseline."""

    @pytest.mark.parametrize("case", [c for c in CASES if c["failure_mode"] == "input_format"])
    def test_input_format_top1(self, search, case):
        results = search.search(case["query"], limit=10)
        acceptable = case.get("acceptable", [])
        assert_in_top_k(results, case["correct"], k=1, acceptable=acceptable, case_id=case["id"])

    @pytest.mark.parametrize("case", [c for c in CASES if c["failure_mode"] == "function_boundary"])
    def test_function_boundary_top1(self, search, case):
        results = search.search(case["query"], limit=10)
        acceptable = case.get("acceptable", [])
        assert_in_top_k(results, case["correct"], k=1, acceptable=acceptable, case_id=case["id"])

    @pytest.mark.parametrize("case", [c for c in CASES if c["failure_mode"] == "paraphrase"])
    def test_paraphrase_top1(self, search, case):
        results = search.search(case["query"], limit=10)
        acceptable = case.get("acceptable", [])
        assert_in_top_k(results, case["correct"], k=1, acceptable=acceptable, case_id=case["id"])

    @pytest.mark.parametrize("case", [c for c in CASES if c["failure_mode"] == "multi_hop"])
    def test_multi_hop_top1(self, search, case):
        results = search.search(case["query"], limit=10)
        acceptable = case.get("acceptable", [])
        assert_in_top_k(results, case["correct"], k=1, acceptable=acceptable, case_id=case["id"])

    @pytest.mark.parametrize("case", [c for c in CASES if c["failure_mode"] == "log_regression"])
    def test_log_regression_top1(self, search, case):
        """Documented production regressions — these MUST pass or we've regressed."""
        results = search.search(case["query"], limit=10)
        acceptable = case.get("acceptable", [])
        assert_in_top_k(results, case["correct"], k=1, acceptable=acceptable, case_id=case["id"])


# ──────────────────────────────────────────────────────────────────────────────
# P@3 tests (lenient) — correct workflow must appear in top-3
# ──────────────────────────────────────────────────────────────────────────────

class TestTop3:
    @pytest.mark.parametrize("case", CASES)
    def test_all_cases_top3(self, search, case):
        results = search.search(case["query"], limit=10)
        acceptable = case.get("acceptable", [])
        assert_in_top_k(results, case["correct"], k=3, acceptable=acceptable, case_id=case["id"])


# ──────────────────────────────────────────────────────────────────────────────
# Confusable sanity — correct workflow ranks above all confusables
# ──────────────────────────────────────────────────────────────────────────────

class TestAboveConfusable:
    @pytest.mark.parametrize("case", CASES)
    def test_correct_ranks_above_confusable(self, search, case):
        results = search.search(case["query"], limit=20)
        names = [m.name for m in results]
        acceptable = set([case["correct"]] + case.get("acceptable", []))
        if not any(t in names for t in acceptable):
            pytest.skip(f"[{case['id']}] correct workflow not in top-20, skip rank comparison")
        correct_rank = min(
            (names.index(t) for t in acceptable if t in names),
            default=len(names)
        )
        for confusable in case["confusable"]:
            if confusable not in names:
                continue
            confusable_rank = names.index(confusable)
            assert correct_rank < confusable_rank, (
                f"[{case['id']}] '{confusable}' (rank {confusable_rank}) ranked above "
                f"correct '{case['correct']}' (rank {correct_rank})\n"
                f"  query: {case['query']}\n"
                f"  top-5: {names[:5]}"
            )


# ──────────────────────────────────────────────────────────────────────────────
# P@1 evaluation report (run as script)
# ──────────────────────────────────────────────────────────────────────────────

def _run_eval():
    """Print a P@1 / P@3 scorecard across all cases, with per-category breakdown."""
    s = UnifiedWorkflowSearch()
    p1 = p3 = above_confusable = 0
    total = len(CASES)
    failures = []
    by_category: dict = {}

    for case in CASES:
        results = s.search(case["query"], limit=20)
        names = [m.name for m in results]
        acceptable = set([case["correct"]] + case.get("acceptable", []))

        hit1 = any(t == names[0] for t in acceptable) if names else False
        hit3 = any(t in names[:3] for t in acceptable)
        correct_rank = min(
            (names.index(t) for t in acceptable if t in names),
            default=999
        )
        confusable_ranks = [names.index(c) for c in case["confusable"] if c in names]
        above = correct_rank < min(confusable_ranks) if confusable_ranks else True

        if hit1:
            p1 += 1
        if hit3:
            p3 += 1
        if above:
            above_confusable += 1

        cat = case["failure_mode"]
        if cat not in by_category:
            by_category[cat] = {"p1": 0, "total": 0}
        by_category[cat]["total"] += 1
        if hit1:
            by_category[cat]["p1"] += 1

        status = "✅" if hit1 else ("~" if hit3 else "❌")
        print(f"{status}  [{case['id']:<45}]  top1={'Y' if hit1 else 'N'}  top3={'Y' if hit3 else 'N'}  rank={correct_rank}  confuse={min(confusable_ranks) if confusable_ranks else '-'}")
        if not hit1:
            failures.append((case, names[:5]))

    print(f"\nP@1  = {p1}/{total} = {p1/total:.1%}")
    print(f"P@3  = {p3}/{total} = {p3/total:.1%}")
    print(f"Above-confusable = {above_confusable}/{total} = {above_confusable/total:.1%}")

    print("\nBy category:")
    for cat, counts in sorted(by_category.items()):
        n, t = counts["p1"], counts["total"]
        marker = "🔴" if n < t else "🟢"
        print(f"  {marker}  {cat:<22}  P@1 = {n}/{t} = {n/t:.1%}")

    if failures:
        print("\nTop-1 failures:")
        for case, top5 in failures:
            print(f"  [{case['id']}]")
            print(f"    query:   {case['query'][:80]}")
            print(f"    correct: {case['correct']}")
            print(f"    got:     {top5}")
            print(f"    why:     {case['notes']}")


if __name__ == "__main__":
    _run_eval()
