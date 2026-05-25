#!/usr/bin/env python3
"""
Audit and patch critical workflow descriptions in the Galaxy AI tools DB.
Run in dry-run mode first: python workflow_desc_audit.py --dry-run
"""
import sqlite3, sys, textwrap, argparse
from pathlib import Path

DB_PATH = Path("/opt/biomate/backend/database/galaxy_ai_tools.db")

# (name_pattern, new_description_suffix_or_full, mode)
# mode = "prepend" | "append" | "replace"
PATCHES = [
    # ── Critical: raredisease description is broken link text ──────────────
    {
        "name_pattern": "nf-core/raredisease",
        "mode": "replace",
        "description": (
            "Rare disease WGS/WES diagnosis pipeline with trio analysis (proband + parents), "
            "variant ranking by pathogenicity (GENMOD/rank_model), repeat expansion detection "
            "(ExpansionHunter/Stranger), mobile element insertion profiling (RetroSeq), "
            "mitochondrial variant calling (HaploGrep2), and OMIM/ClinVar annotation. "
            "Optimised for diagnosing inherited rare disease in family cohorts. "
            "Does NOT cover somatic cancer variant calling (use sarek for somatic/cancer WGS/WES)."
        ),
    },
    # ── Critical: sarek lacks raredisease exclusions ───────────────────────
    {
        "name_pattern": "nf-core/sarek",
        "mode": "append",
        "description": (
            " Does NOT support trio/family analysis, variant ranking by inheritance model, "
            "repeat expansion detection (ExpansionHunter), or mobile element profiling — "
            "use raredisease for rare inherited disease diagnosis."
        ),
    },
    # ── Epigenomics: add protocol vocabulary ──────────────────────────────
    {
        "name_pattern": "nf-core/chipseq",
        "mode": "prepend",
        "description": (
            "Antibody-based protein-DNA interaction profiling (ChIP-seq). "
            "Requires antibody immunoprecipitation step in wet lab. "
            "Use for histone mark profiling (H3K27ac, H3K4me3), transcription factor binding, "
            "or chromatin state mapping. "
        ),
    },
    {
        "name_pattern": "nf-core/atacseq",
        "mode": "replace",
        "description": (
            "Transposase-accessible chromatin profiling (ATAC-seq). "
            "Measures open chromatin regions using Tn5 transposase (no antibody required). "
            "Pipeline: adapter trimming, alignment (Bowtie2), peak calling (MACS2/MACS3), "
            "differential accessibility, TSS enrichment, nucleosome positioning, "
            "and motif enrichment. "
            "Does NOT measure protein-DNA binding (use chipseq for that). "
            "Does NOT require antibody or immunoprecipitation."
        ),
    },
    {
        "name_pattern": "nf-core/cutandrun",
        "mode": "replace",
        "description": (
            "Nuclease-coupled antibody profiling via CUT&RUN, CUT&Tag, or TIPseq. "
            "Uses pA/G-MNase to cleave chromatin at antibody-bound sites. "
            "IgG or unrelated antibody is the standard negative control for peak calling. "
            "Key advantage: works with very low cell numbers (<1000 cells), unlike ChIP-seq. "
            "Outputs: aligned BAM files, MACS2/SEACR peak calls, differential binding, QC metrics. "
            "Does NOT measure open chromatin (use atacseq for that)."
        ),
    },
    # ── differentialabundance: add input boundary ─────────────────────────
    {
        "name_pattern": "nf-core/differentialabundance",
        "mode": "prepend",
        "description": (
            "Requires pre-computed gene/transcript count matrix as input. "
            "Does NOT process raw FASTQ files (use nf-core/rnaseq for that). "
        ),
    },
    # ── Proteomics DDA vs DIA disambiguation ──────────────────────────────
    {
        "name_pattern": "nf-core/diaproteomics",
        "mode": "prepend",
        "description": (
            "Data-Independent Acquisition (DIA) proteomics pipeline. "
            "Input: DIA-mode mass spectra (Spectronaut, DIA-NN, OpenSWATH). "
            "Does NOT support Data-Dependent Acquisition (DDA) or TMT-labeled experiments. "
        ),
    },
    {
        "name_pattern": "nf-core/proteomicslfq",
        "mode": "prepend",
        "description": (
            "Data-Dependent Acquisition (DDA) label-free quantification (LFQ) proteomics pipeline. "
            "Input: DDA mass spectra (FASTA database search, OpenMS). "
            "Does NOT support Data-Independent Acquisition (DIA) — use diaproteomics for DIA data. "
        ),
    },
    # ── methylseq: clarify WGBS vs array ─────────────────────────────────
    {
        "name_pattern": "nf-core/methylseq",
        "mode": "prepend",
        "description": (
            "Bisulfite sequencing (WGBS/RRBS) methylation analysis. Input: raw FASTQ reads. "
            "Does NOT process Illumina methylation arrays (450K/EPIC) — use methylarray for that. "
        ),
    },
    # ── Fix placeholder descriptions (22 pipelines have README template text) ──
    {
        "name_pattern": "nf-core/scdownstream",
        "mode": "replace",
        "description": (
            "Downstream single-cell RNA-seq analysis starting from pre-quantified count matrices "
            "(h5ad, Seurat, or CSV). Performs QC, ambient RNA correction, doublet detection, "
            "batch integration, clustering, and cell type annotation. "
            "Does NOT process raw FASTQ files — use nf-core/scrnaseq to go from FASTQ to count matrices first."
        ),
    },
    {
        "name_pattern": "nf-core/mcmicro",
        "mode": "replace",
        "description": (
            "Highly-multiplexed tissue imaging pipeline (CODEX, CyCIF, MIBI, t-CyCIF). "
            "Input: multi-channel whole-slide images. Output: segmentation masks, registered images, "
            "and single-cell feature matrices. Covers image registration, segmentation, and quantification."
        ),
    },
    {
        "name_pattern": "nf-core/bactmap",
        "mode": "replace",
        "description": (
            "Bacterial whole-genome short-read mapping pipeline for phylogenetics. "
            "Input: paired-end bacterial WGS FASTQ reads + reference genome. "
            "Output: filtered VCFs, pseudogenomes, and phylogenetic trees. "
            "Mapping-based approach — does NOT perform de novo assembly."
        ),
    },
    {
        "name_pattern": "nf-core/hadge",
        "mode": "replace",
        "description": (
            "Single-cell demultiplexing pipeline for multiplexed experiments with cell hashing "
            "and/or genetic barcoding. Input: count matrices, BAM, and VCF from pooled samples. "
            "Combines 11 deconvolution methods to assign cells to donors. "
            "Use before downstream scRNA-seq analysis when multiple donors are pooled."
        ),
    },
    {
        "name_pattern": "nf-core/lncpipe",
        "mode": "replace",
        "description": (
            "Long non-coding RNA (lncRNA) discovery and quantification pipeline from raw RNA-seq FASTQ reads. "
            "Aligns reads, assembles transcripts, identifies and classifies novel lncRNAs, and quantifies expression. "
            "Supports human, mouse, fly, and zebrafish only (CPAT dependency)."
        ),
    },
    {
        "name_pattern": "nf-core/createpanelrefs",
        "mode": "replace",
        "description": (
            "Generates panel-of-normals (PoN) reference files for somatic variant calling. "
            "Input: normal-sample BAMs/CRAMs. Output: PoN files for CNVkit, GATK Mutect2, and GENS. "
            "Run once on normal samples — output is used by tumor-only somatic variant callers."
        ),
    },
    {
        "name_pattern": "nf-core/phageannotator",
        "mode": "replace",
        "description": (
            "Phage sequence identification, annotation, and quantification from metagenomic assemblies. "
            "Input: pre-assembled genomes (e.g., from nf-core/mag) — does NOT process raw reads. "
            "Outputs annotated phage sequences and abundance estimates."
        ),
    },
    {
        "name_pattern": "nf-core/sammyseq",
        "mode": "replace",
        "description": (
            "SAMMY-seq (Sequential Analysis of MacroMolecules accessibilitY) chromatin accessibility pipeline. "
            "Input: SAMMY-seq FASTQ reads. Performs QC, BWA-MEM alignment, and chromatin-state statistical analysis "
            "(PCA, correlation). Specialized for lamina-associated chromatin profiling."
        ),
    },
    {
        "name_pattern": "nf-core/tbanalyzer",
        "mode": "replace",
        "description": (
            "Mycobacterium tuberculosis complex genomics pipeline. "
            "Input: sequencing data from TB samples. "
            "Performs QC and variant detection specialized for tuberculosis genomic surveillance and resistance profiling."
        ),
    },
    # ── variant_calling domain: sarek vs wgs_germline_gatk disambiguation ────
    {
        "name_pattern": "nf-core/sarek",
        "mode": "prepend",
        "description": (
            "For somatic and tumor-normal variant calling, cancer genomics, CNV/SV detection, "
            "and multi-sample cohort analysis. "
            "Use nf-core/raredisease for rare disease diagnosis. "
        ),
    },
    {
        "name_pattern": "wgs_germline_gatk",
        "mode": "append",
        "description": (
            " Use for germline single-sample, family trio, or population genetics variant calling "
            "of inherited disease. NOT for somatic/tumor samples — use nf-core/sarek for cancer."
        ),
    },
    # ── atac_seq domain: atacseq vs cutandrun disambiguation ─────────────────
    {
        "name_pattern": "nf-core/atacseq",
        "mode": "prepend",
        "description": (
            "Tn5-transposase-based open chromatin profiling (ATAC-seq). "
            "Does NOT use antibodies. "
            "For antibody-based chromatin profiling use nf-core/cutandrun. "
        ),
    },
    {
        "name_pattern": "nf-core/cutandrun",
        "mode": "prepend",
        "description": (
            "Antibody-based targeted chromatin profiling: CUT&RUN, CUT&TAG, and SNAP-CUTANA. "
            "Uses pA-Tn5 or pA-MNase with specific antibodies for histone marks "
            "(H3K4me3, H3K27ac, H3K27me3) or TF binding. NOT ATAC-seq. "
        ),
    },
]


def patch_db(db_path: Path, dry_run: bool = True):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    updated = 0

    for patch in PATCHES:
        pattern = patch["name_pattern"]
        mode = patch["mode"]
        new_text = patch["description"]

        cur.execute("SELECT id, name, description FROM workflows WHERE name LIKE ?", (f"%{pattern}%",))
        rows = cur.fetchall()
        if not rows:
            print(f"  [NOT FOUND] '{pattern}'")
            continue

        for row_id, name, current_desc in rows:
            current_desc = current_desc or ""

            # Idempotency: skip if patch is already applied
            if mode == "replace" and current_desc.strip() == new_text.strip():
                print(f"\n  [SKIP-already-applied] {name[:60]}")
                continue
            if mode == "prepend" and current_desc.startswith(new_text):
                print(f"\n  [SKIP-already-applied] {name[:60]}")
                continue
            if mode == "append" and current_desc.endswith(new_text):
                print(f"\n  [SKIP-already-applied] {name[:60]}")
                continue

            if mode == "replace":
                final_desc = new_text
            elif mode == "prepend":
                final_desc = new_text + current_desc
            elif mode == "append":
                final_desc = current_desc + new_text
            else:
                continue

            print(f"\n  [{mode.upper()}] {name[:60]}")
            if dry_run:
                print(f"    OLD ({len(current_desc)}): {current_desc[:80]}...")
                print(f"    NEW ({len(final_desc)}): {final_desc[:80]}...")
            else:
                cur.execute("UPDATE workflows SET description=? WHERE id=?", (final_desc, row_id))
                updated += 1

    if not dry_run:
        conn.commit()
        print(f"\n  Updated {updated} workflow descriptions.")
    else:
        print(f"\n  DRY RUN — {len(PATCHES)} patches defined, {sum(1 for p in PATCHES for _ in [1])} total rows would be updated.")
    conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", default=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    dry_run = not args.apply
    patch_db(DB_PATH, dry_run=dry_run)
