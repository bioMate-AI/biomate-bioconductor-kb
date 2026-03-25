#!/usr/bin/env python3
"""
Unified Workflow Indexer

Correct table split:
  workflows table  — composite pipelines and multi-step subworkflows
  tools table      — individual executors (single tool/package wrappers)

workflows table sources (in priority order):
  nfcore        (100) — Full nf-core pipelines (rnaseq, sarek, chipseq, …)
  nfcore_subwf   (95) — nf-core composite subworkflows (nf-core-modules/subworkflows/)
  biomni_nextflow(85) — BioMate domain analysis workflows (nextflow_nfcore/subworkflows/)
  bioconductor   (75) — Bioconductor R package Nextflow workflows (~1818 on-disk .nf files)
                        Each file has a process + workflow block; these ARE runnable workflows.
  galaxy_biomni  (35) — Unique BioMate Galaxy workflows with NO Nextflow equivalent (2 items)

tools table additions (on top of 10 k+ existing Galaxy ToolShed entries):
  nfcore_module      — nf-core individual tool modules (nf-core-modules/modules/)
                       e.g. star/align, samtools/sort, gatk4/haplotypecaller
  bioconductor       — Bioconductor package metadata (2273 entries; rich vignette/function info)
                       Kept in tools for tool-level lookups; the runnable .nf goes in workflows.

NOT indexed any more:
  galaxy_local        — Removed: Galaxy copies of nfcore subworkflows (redundant)
  biomni (legacy)     — Removed: superseded by biomni_nextflow
  nfcore_module in workflows — Wrong table; moved to tools

Usage:
    python scripts/index_all_workflows.py              # incremental
    python scripts/index_all_workflows.py --rebuild    # wipe and re-index
    python scripts/index_all_workflows.py --update-types  # backfill input/output types only

Author: BioMate Team
Updated: 2026-03-18
"""

import argparse
import json
import re
import sqlite3
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# ── Paths ────────────────────────────────────────────────────────────────────
BACKEND_PATH = Path(__file__).parent.parent
DB_PATH = BACKEND_PATH / "database" / "galaxy_ai_tools.db"

BIOMNI_NF_PATH       = BACKEND_PATH / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"
NFCORE_MODULES_PATH  = BACKEND_PATH / "nf-core-modules" / "modules" / "nf-core"
NFCORE_SUBWF_PATH    = BACKEND_PATH / "nf-core-modules" / "subworkflows" / "nf-core"
NFCORE_PIPELINES_PATH= BACKEND_PATH / "nf-core-workflows"

BIOMNI_GALAXY_UNIQUE_PATH = BACKEND_PATH / "biomni_workflows" / "galaxy" / "subworkflows"
GALAXY_UNIQUE_WORKFLOWS = [
    ("synthetic_biology", "identify_fas_functional_domains"),
    ("biophysics",        "predict_protein_disorder_regions"),
]

NFCORE_PIPELINES = {
    "rnaseq":               {"name": "nf-core/rnaseq",               "description": "RNA sequencing analysis pipeline using STAR, RSEM, HISAT2 or Salmon with extensive QC",             "domain": "transcriptomics",  "tools": ["star","salmon","hisat2","rsem","kallisto","deseq2","fastqc","multiqc"]},
    "chipseq":              {"name": "nf-core/chipseq",              "description": "ChIP-seq peak-calling and differential analysis pipeline",                                           "domain": "epigenomics",      "tools": ["bwa","bowtie2","macs2","homer","deeptools","multiqc"]},
    "sarek":                {"name": "nf-core/sarek",                "description": "Analysis pipeline to detect germline or somatic variants from WGS/WES",                             "domain": "variant_calling",  "tools": ["bwa","gatk","strelka","manta","freebayes","mutect2"]},
    "methylseq":            {"name": "nf-core/methylseq",            "description": "Methylation (Bisulfite-Sequencing) analysis pipeline",                                              "domain": "epigenomics",      "tools": ["bismark","bwa-meth","methyldackel","multiqc"]},
    "diaproteomics":        {"name": "nf-core/diaproteomics",        "description": "Automated quantitative analysis of DIA proteomics mass spectrometry data",                         "domain": "proteomics",       "tools": ["dia-nn","openswath","pyprophet"]},
    "proteomicslfq":        {"name": "nf-core/proteomicslfq",        "description": "Proteomics label-free quantification (LFQ) analysis pipeline",                                     "domain": "proteomics",       "tools": ["maxquant","openms","comet"]},
    "differentialabundance":{"name": "nf-core/differentialabundance","description": "Differential abundance analysis for count matrices from RNA-seq, ATAC-seq, etc.",                  "domain": "transcriptomics",  "tools": ["deseq2","limma","edger"]},
}

# ── Domain → canonical output types ──────────────────────────────────────────
# Maps domain (or pipeline name keyword) to the file types it typically produces.
# Used to populate output_types when schema doesn't provide explicit output info.
DOMAIN_OUTPUT_TYPES: dict = {
    "transcriptomics":    ["bam", "counts_matrix", "tpm_matrix", "multiqc_report", "bigwig"],
    "variant_calling":    ["vcf", "bam", "bai", "multiqc_report"],
    "epigenomics":        ["bam", "bigwig", "bed_peaks", "multiqc_report"],
    "proteomics":         ["mzml", "tsv_peptides", "tsv_proteins", "pdf_report"],
    "metagenomics":       ["fasta_bins", "tsv_taxonomy", "tsv_abundance", "multiqc_report"],
    "genomics":           ["bam", "bai", "fasta_assembly", "multiqc_report"],
    "single_cell":        ["h5ad", "loom", "tsv_barcodes", "multiqc_report"],
    "structural_biology": ["pdb", "cif", "json_scores"],
    "drug_discovery":     ["sdf", "csv_scores", "tsv_admet"],
    "cryo_em":            ["mrcs", "star_particles", "mrc_map"],
    "pharmacology":       ["tsv_pk", "pdf_report", "csv_nca"],
    "systems_biology":    ["csv_simulation", "pdf_plot", "json_model"],
    "synthetic_biology":  ["genbank", "fasta", "pdf_design"],
    "imaging":            ["tiff", "csv_measurements", "pdf_report"],
    "general":            ["results_dir"],
}

# Pipeline-name keyword → output type overrides (more specific than domain)
_PIPELINE_OUTPUT_OVERRIDES: dict = {
    "rnaseq":       ["bam", "counts_matrix", "tpm_matrix", "multiqc_report", "bigwig"],
    "chipseq":      ["bam", "bigwig", "bed_peaks", "multiqc_report"],
    "atacseq":      ["bam", "bigwig", "bed_peaks", "multiqc_report"],
    "sarek":        ["vcf", "bam", "bai", "multiqc_report"],
    "mag":          ["fasta_bins", "tsv_taxonomy", "multiqc_report"],
    "ampliseq":     ["tsv_taxonomy", "biom", "multiqc_report"],
    "methylseq":    ["bam", "bismark_report", "multiqc_report"],
    "differentialabundance": ["tsv_deseq2", "html_report", "pdf_plots"],
    "diaproteomics":["tsv_proteins", "pdf_report"],
    "proteomicslfq":["tsv_proteins", "mzml"],
    "taxprofiler":  ["tsv_taxonomy", "multiqc_report"],
    "fetchngs":     ["fastq", "samplesheet_csv"],
    "demultiplex":  ["fastq", "multiqc_report"],
    "isoseq":       ["bam", "fasta_isoforms", "tsv_counts"],
    "crisprseq":    ["tsv_editing", "bam", "multiqc_report"],
    "hic":          ["cooler", "bedgraph", "multiqc_report"],
    "hicar":        ["cooler", "bedgraph", "multiqc_report"],
    "scrnaseq":     ["h5ad", "loom", "multiqc_report"],
    "spatialvi":    ["h5ad", "pdf_plots"],
    "nanoseq":      ["vcf", "bam", "multiqc_report"],
    "viralrecon":   ["vcf", "bam", "multiqc_report"],
    "eager":        ["bam", "tsv_damage", "multiqc_report"],
    "bacass":       ["fasta_assembly", "multiqc_report"],
    "bactmap":      ["vcf", "bam", "multiqc_report"],
}


def _infer_output_types(pipeline_name: str, domain: str) -> list:
    """Return canonical output types for a pipeline based on name then domain."""
    name_lower = pipeline_name.lower().replace("nf-core/", "")
    for key, otypes in _PIPELINE_OUTPUT_OVERRIDES.items():
        if key in name_lower:
            return otypes
    return DOMAIN_OUTPUT_TYPES.get(domain, DOMAIN_OUTPUT_TYPES["general"])


# Domain inference from keyword text
DOMAIN_KEYWORDS = [
    ("rna",         "transcriptomics"),
    ("rnaseq",      "transcriptomics"),
    ("expression",  "transcriptomics"),
    ("align",       "genomics"),
    ("assembly",    "genomics"),
    ("genome",      "genomics"),
    ("variant",     "variant_calling"),
    ("vcf",         "variant_calling"),
    ("snp",         "variant_calling"),
    ("methylat",    "epigenomics"),
    ("chip",        "epigenomics"),
    ("atac",        "epigenomics"),
    ("peak",        "epigenomics"),
    ("protein",     "proteomics"),
    ("proteom",     "proteomics"),
    ("peptide",     "proteomics"),
    ("metagen",     "metagenomics"),
    ("microbiome",  "metagenomics"),
    ("16s",         "metagenomics"),
    ("imaging",     "imaging"),
    ("image",       "imaging"),
]


def infer_domain(text: str) -> str:
    t = text.lower()
    for kw, dom in DOMAIN_KEYWORDS:
        if kw in t:
            return dom
    return "general"


# ── Input/Output Type Extraction ──────────────────────────────────────────────

def _extract_process_input_block(content: str) -> str:
    """Extract the input: block from a Nextflow process definition."""
    m = re.search(
        r'\bprocess\s+\w+\s*\{.*?\binput:\s*\n(.*?)(?:\n\s*output:|\n\s*when:|\n\s*script:)',
        content, re.DOTALL
    )
    return m.group(1) if m else ""


def _extract_process_output_block(content: str) -> str:
    """Extract the output: block from a Nextflow process definition."""
    m = re.search(
        r'\bprocess\s+\w+\s*\{.*?\boutput:\s*\n(.*?)(?:\n\s*when:|\n\s*script:|\n\s*exec:)',
        content, re.DOTALL
    )
    return m.group(1) if m else ""


def _extract_take_block(content: str) -> str:
    """Extract the take: block from a Nextflow workflow definition."""
    m = re.search(r'\bworkflow\s+\w+\s*\{.*?\btake:\s*\n(.*?)(?:\n\s*main:|\n\s*emit:)',
                  content, re.DOTALL)
    return m.group(1) if m else ""


def extract_bioc_input_output(content: str) -> Tuple[List[str], List[str]]:
    """
    Extract input/output types from a Bioconductor .nf file.

    Input detection: looks for path() arguments in the process input block.
    If none found, falls back to the take: block comment for channel type hints.

    Output detection: extracts file extensions from path("...") in the output block,
    excluding internal files like versions.yml.
    """
    inputs: List[str] = []
    outputs: List[str] = []

    try:
        # ── inputs ──
        input_block = _extract_process_input_block(content)
        if input_block:
            # e.g. path(count_data)  →  count_data
            path_args = re.findall(r'\bpath\s*\(\s*(\w+)\s*\)', input_block)
            inputs = [a for a in path_args if a not in ("meta", "versions")]

        # Fallback: take: block channel type hint
        if not inputs:
            take_block = _extract_take_block(content)
            if take_block:
                # e.g. ch_input  // channel: [ val(meta), path(count_data) ]
                hints = re.findall(r'path\((\w+)\)', take_block)
                inputs = [h for h in hints if h not in ("meta", "versions")]

        # ── outputs ──
        output_block = _extract_process_output_block(content)
        if output_block:
            # Extract file extensions from quoted paths: path("${prefix}_out.csv")
            exts = re.findall(r'path\s+"[^"]*\.(\w+)"', output_block)
            # Also catch: path '*.<ext>'
            exts += re.findall(r"path\s+'[^']*\.(\w+)'", output_block)
            skip = {"yml", "yaml", "log", "txt", "json"}
            outputs = list(dict.fromkeys(e for e in exts if e.lower() not in skip))

    except Exception:
        pass

    return inputs, outputs


def extract_biomni_input_output(content: str) -> Tuple[List[str], List[str]]:
    """
    Extract input/output types from a BioMate Nextflow workflow.

    Inputs: params.* definitions (excluding outdir).
    Outputs: file extensions from the process output block.
    """
    inputs: List[str] = []
    outputs: List[str] = []

    try:
        # ── inputs: from params ──
        param_names = re.findall(r'\bparams\.(\w+)\s*=', content)
        skip_params = {"outdir", "publish_dir_mode", "enable_conda"}
        inputs = list(dict.fromkeys(p for p in param_names if p not in skip_params))

        # ── outputs: from process output block ──
        output_block = _extract_process_output_block(content)
        if output_block:
            exts = re.findall(r'path\s+"[^"]*\.(\w+)"', output_block)
            exts += re.findall(r"path\s+'[^']*\.(\w+)'", output_block)
            skip_exts = {"yml", "yaml", "log"}
            outputs = list(dict.fromkeys(e for e in exts if e.lower() not in skip_exts))

    except Exception:
        pass

    return inputs, outputs


def extract_nfcore_input_output(
    content: str,
    schema_path: Optional[Path] = None,
    pipeline_name: str = "",
    domain: str = "general",
) -> Tuple[List[str], List[str]]:
    """
    Extract input/output types for nf-core full pipelines.

    Strategy:
    1. Parse nextflow_schema.json for input param names.
    2. For outputs: use pipeline-name/domain knowledge mapping (schema never
       enumerates outputs explicitly — they are just written to outdir).
    3. Fall back to scanning params in main.nf if schema has no input info.
    """
    inputs: List[str] = []
    outputs: List[str] = []

    try:
        if schema_path and schema_path.exists():
            schema = json.loads(schema_path.read_text())
            # Support both $defs (newer nf-core) and definitions (older)
            defs = schema.get("$defs", schema.get("definitions", {}))
            for group in defs.values():
                for pname, pdef in group.get("properties", {}).items():
                    pname_l = pname.lower()
                    if pname_l in ("input", "samplesheet", "reads", "input_path",
                                   "samples", "manifest", "bam", "fastq"):
                        if pname not in inputs:
                            inputs.append(pname)

        if not inputs:
            # Fallback: scan params block in main.nf
            param_names = re.findall(r'\bparams\.(\w+)\s*=', content)
            skip = {"outdir", "publish_dir_mode", "enable_conda", "help",
                    "tracedir", "max_cpus", "max_memory", "max_time"}
            inputs = list(dict.fromkeys(p for p in param_names if p not in skip))[:5]

        # Outputs: use domain-knowledge mapping (schema has no explicit output list)
        outputs = _infer_output_types(pipeline_name, domain)

    except Exception:
        pass

    return inputs, outputs


# ── Helpers ───────────────────────────────────────────────────────────────────

def compute_hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def load_meta_yml(path: Path) -> Dict:
    if not HAS_YAML or not path.exists():
        return {}
    try:
        with open(path) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def extract_tools_from_ga(wf_json: Dict) -> List[str]:
    tools = []
    for step in wf_json.get("steps", {}).values():
        tid = step.get("tool_id") if isinstance(step, dict) else None
        if tid:
            tools.append(tid.split("/")[-1].lower())
    return list(set(tools))


def extract_nf_metadata(content: str) -> Dict:
    header = re.search(r'/\*\s*\n(.*?)\*/\s*\n', content, re.DOTALL)
    description = ""
    if header:
        lines = [ln.strip().lstrip("* ").strip()
                 for ln in header.group(1).splitlines()
                 if ln.strip() and ln.strip() not in ("*", "/*", "*/")]
        description = " ".join(lines)[:500]
    processes = re.findall(r'process\s+([A-Z][A-Z0-9_]+)', content)
    docker_m = re.search(r"container\s+'([^']+)'", content)
    return {"description": description, "processes": processes,
            "docker": docker_m.group(1) if docker_m else ""}


def wf_name(s: str) -> str:
    return s.replace("_", " ").replace("/", " ").title()


# ── Curated workflow chains ───────────────────────────────────────────────────
#
# Each entry describes a named, ordered composition of workflows that naturally
# go together for a research project type.  The chain is the unit that maps a
# high-level user query ("run a rare disease workup") to a concrete execution
# plan, bypassing per-query LLM reassembly.
#
# steps:            ordered list of {order, workflow_name, role, params_template}
# connections:      data flow between steps {from_step, from_output, to_step, to_input}
# required_inputs:  what the user must supply at the start
# expected_outputs: what the chain produces at the end
# example_queries:  natural-language triggers used for semantic matching
#
CURATED_CHAINS = [
    {
        "name": "rare_disease_multimodal_workup",
        "display_name": "Rare Disease Multi-Modal Workup",
        "domain": "rare_disease",
        "description": (
            "End-to-end rare disease workup combining germline variant calling on "
            "WGS/WES with transcriptomic outlier detection (aberrant expression and "
            "splicing) on paired RNA-seq, producing a unified case report ready for "
            "downstream variant prioritisation tools."
        ),
        "steps": [
            {"order": 1, "workflow_name": "nf-core/sarek",         "role": "germline_variant_calling",    "params_template": {"genome": "GRCh38", "tools": ["haplotypecaller"], "wes": False}},
            {"order": 2, "workflow_name": "vep_annotation",         "role": "variant_annotation",          "params_template": {"species": "homo_sapiens", "assembly": "GRCh38"}},
            {"order": 3, "workflow_name": "nf-core/rnaseq",         "role": "rna_alignment_quantification","params_template": {"aligner": "star_salmon", "genome": "GRCh38"}},
            {"order": 4, "workflow_name": "nf-core/drop",           "role": "aberrant_expression_splicing","params_template": {"outrider": True, "fraser": True}},
            {"order": 5, "workflow_name": "case_report_aggregation","role": "result_aggregation",          "params_template": {}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "vcf",  "to_step": 2, "to_input": "vcf"},
            {"from_step": 3, "from_output": "bam",  "to_step": 4, "to_input": "bam"},
            {"from_step": 2, "from_output": "annotated_vcf", "to_step": 5, "to_input": "variant_evidence"},
            {"from_step": 4, "from_output": "outrider_results", "to_step": 5, "to_input": "expression_evidence"},
            {"from_step": 4, "from_output": "fraser_results",   "to_step": 5, "to_input": "splicing_evidence"},
        ],
        "required_inputs": [
            {"name": "wgs_fastq_or_bam", "type": "fastq|bam", "description": "WGS or WES reads for the patient (and parents for trio analysis)"},
            {"name": "rna_fastq",        "type": "fastq",      "description": "RNA-seq reads from patient-matched sample"},
        ],
        "expected_outputs": [
            {"name": "annotated_vcf",       "type": "vcf",  "description": "Germline variants with population frequency and consequence annotations"},
            {"name": "outrider_results",    "type": "tsv",  "description": "Aberrant expression outlier genes"},
            {"name": "fraser_results",      "type": "tsv",  "description": "Aberrant splicing junctions"},
            {"name": "case_report",         "type": "html", "description": "Unified patient case report linking DNA and RNA evidence"},
        ],
        "example_queries": [
            "Run a complete rare disease workup — I have WES and RNA-seq",
            "Germline variant calling and transcriptomic outlier detection for a rare disease patient",
            "Multi-modal rare disease analysis combining WGS and RNA-seq",
            "Run OUTRIDER and FRASER on the RNA-seq paired with this patient's WGS",
        ],
        "tags": ["rare_disease", "WGS", "WES", "RNA-seq", "OUTRIDER", "FRASER", "germline", "variant_calling"],
    },
    {
        "name": "bulk_rnaseq_de_analysis",
        "display_name": "Bulk RNA-seq Differential Expression Analysis",
        "domain": "transcriptomics",
        "description": (
            "Full bulk RNA-seq analysis pipeline: alignment and QC with nf-core/rnaseq, "
            "differential expression with DESeq2, and gene set enrichment analysis."
        ),
        "steps": [
            {"order": 1, "workflow_name": "nf-core/rnaseq",              "role": "alignment_qc_quantification", "params_template": {"aligner": "star_salmon", "genome": "GRCh38"}},
            {"order": 2, "workflow_name": "nf-core/differentialabundance","role": "differential_expression",     "params_template": {"method": "deseq2"}},
            {"order": 3, "workflow_name": "gene_set_enrichment_analysis", "role": "pathway_enrichment",          "params_template": {"databases": ["GO", "KEGG", "Reactome"]}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "counts_matrix", "to_step": 2, "to_input": "counts"},
            {"from_step": 2, "from_output": "de_results",    "to_step": 3, "to_input": "gene_list"},
        ],
        "required_inputs": [
            {"name": "fastq_files",    "type": "fastq",    "description": "Raw RNA-seq reads"},
            {"name": "sample_sheet",   "type": "csv",      "description": "Sample metadata with condition labels"},
            {"name": "contrast",       "type": "string",   "description": "Comparison to run, e.g. treatment vs control"},
        ],
        "expected_outputs": [
            {"name": "multiqc_report", "type": "html", "description": "QC summary across all samples"},
            {"name": "de_results",     "type": "tsv",  "description": "Differential expression table with log2FC and adjusted p-values"},
            {"name": "gsea_results",   "type": "tsv",  "description": "Enriched pathways and gene sets"},
        ],
        "example_queries": [
            "Run RNA-seq analysis and differential expression",
            "Align RNA-seq, run DESeq2, and do pathway enrichment",
            "Bulk RNA-seq DE analysis with GO enrichment",
            "Run nf-core rnaseq then differential expression and GSEA",
        ],
        "tags": ["RNA-seq", "DESeq2", "differential_expression", "GSEA", "GO", "pathway_enrichment"],
    },
    {
        "name": "single_cell_multimodal_analysis",
        "display_name": "Single-Cell RNA-seq Multi-Sample Analysis",
        "domain": "single_cell",
        "description": (
            "Full downstream single-cell analysis from Cell Ranger output: "
            "QC, normalization, batch-aware integration, clustering, reference-based "
            "cell-type annotation, trajectory inference, and multi-sample differential "
            "abundance testing accounting for donor as a random effect."
        ),
        "steps": [
            {"order": 1, "workflow_name": "scrna_qc_normalization",                   "role": "qc_and_normalization",          "params_template": {}},
            {"order": 2, "workflow_name": "create_harmony_embeddings_scRNA",          "role": "batch_integration",             "params_template": {}},
            {"order": 3, "workflow_name": "annotate_celltype_scRNA",                  "role": "clustering_and_annotation",     "params_template": {}},
            {"order": 4, "workflow_name": "trajectory_inference",                     "role": "trajectory_analysis",           "params_template": {}},
            {"order": 5, "workflow_name": "differential_abundance_random_effects",    "role": "differential_abundance",        "params_template": {"random_effect": "donor"}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "h5ad_filtered", "to_step": 2, "to_input": "h5ad"},
            {"from_step": 2, "from_output": "h5ad_integrated","to_step": 3, "to_input": "h5ad"},
            {"from_step": 3, "from_output": "h5ad_annotated", "to_step": 4, "to_input": "h5ad"},
            {"from_step": 3, "from_output": "h5ad_annotated", "to_step": 5, "to_input": "h5ad"},
        ],
        "required_inputs": [
            {"name": "cellranger_output", "type": "directory", "description": "Cell Ranger output directory (or equivalent h5ad/matrix)"},
            {"name": "sample_metadata",   "type": "csv",       "description": "Sample metadata including donor ID and condition"},
        ],
        "expected_outputs": [
            {"name": "h5ad_final",         "type": "h5ad", "description": "Annotated, integrated single-cell object"},
            {"name": "cell_type_umap",     "type": "pdf",  "description": "UMAP coloured by cell type and condition"},
            {"name": "da_results",         "type": "tsv",  "description": "Differential abundance results by cell type"},
            {"name": "trajectory_plot",    "type": "pdf",  "description": "Pseudotime trajectory"},
        ],
        "example_queries": [
            "Run single-cell analysis from Cell Ranger output",
            "scRNA-seq clustering, annotation, and differential abundance across donors",
            "Full downstream scRNA-seq analysis with donor batch correction",
            "Annotate cell types and test differential abundance accounting for donor",
        ],
        "tags": ["scRNA-seq", "single_cell", "Harmony", "cell_type_annotation", "differential_abundance", "trajectory"],
    },
    {
        "name": "cutandtag_chromatin_analysis",
        "display_name": "CUT&Tag Chromatin Profiling",
        "domain": "epigenomics",
        "description": (
            "CUT&Tag analysis pipeline: alignment with Bowtie2, spike-in normalisation, "
            "peak calling with SEACR, and differential binding analysis between conditions."
        ),
        "steps": [
            {"order": 1, "workflow_name": "cutandtag_alignment_spikein", "role": "alignment_and_normalisation", "params_template": {"aligner": "bowtie2", "spikein_genome": "dm6"}},
            {"order": 2, "workflow_name": "seacr_peak_calling",          "role": "peak_calling",               "params_template": {"mode": "non-stringent"}},
            {"order": 3, "workflow_name": "differential_binding_analysis","role": "differential_binding",       "params_template": {"method": "DESeq2"}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "normalised_bam", "to_step": 2, "to_input": "bam"},
            {"from_step": 2, "from_output": "peaks_bed",      "to_step": 3, "to_input": "peaks"},
            {"from_step": 1, "from_output": "normalised_bam", "to_step": 3, "to_input": "bam"},
        ],
        "required_inputs": [
            {"name": "fastq_files",    "type": "fastq",   "description": "CUT&Tag reads for target and IgG control"},
            {"name": "sample_sheet",   "type": "csv",     "description": "Sample metadata with antibody target and condition"},
            {"name": "spikein_genome", "type": "string",  "description": "Spike-in genome for normalisation (e.g. dm6 for Drosophila)"},
        ],
        "expected_outputs": [
            {"name": "normalised_bigwig", "type": "bigwig", "description": "Spike-in normalised coverage tracks"},
            {"name": "peaks_bed",         "type": "bed",    "description": "Called peaks per sample"},
            {"name": "differential_peaks","type": "tsv",    "description": "Differentially bound regions between conditions"},
        ],
        "example_queries": [
            "Run CUT&Tag analysis with spike-in normalisation",
            "CUT&Tag alignment, peak calling with SEACR, and differential binding",
            "Chromatin profiling analysis with IgG control and SEACR",
            "Process CUT&Tag data and find differential peaks between conditions",
        ],
        "tags": ["CUT&Tag", "CUT&RUN", "SEACR", "chromatin", "spike-in", "differential_binding", "epigenomics"],
    },
    {
        "name": "alternative_polyadenylation_analysis",
        "display_name": "Alternative Polyadenylation Analysis (PolyAMiner-Bulk)",
        "domain": "transcriptomics",
        "description": (
            "RNA-seq alignment followed by PolyAMiner-Bulk for alternative polyadenylation "
            "detection, quantification of 3'UTR length changes, and visualisation of "
            "differential APA genes between conditions."
        ),
        "steps": [
            {"order": 1, "workflow_name": "nf-core/rnaseq",    "role": "alignment",       "params_template": {"aligner": "star", "save_unaligned": False}},
            {"order": 2, "workflow_name": "polyaminer_bulk",   "role": "apa_detection",   "params_template": {"clustering_mode": "softclipped_assisted"}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "bam", "to_step": 2, "to_input": "bam"},
        ],
        "required_inputs": [
            {"name": "fastq_files",  "type": "fastq", "description": "Bulk RNA-seq reads"},
            {"name": "sample_sheet", "type": "csv",   "description": "Sample metadata with condition labels"},
            {"name": "genome",       "type": "string","description": "Reference genome (e.g. GRCh38, mm10)"},
        ],
        "expected_outputs": [
            {"name": "apa_results",       "type": "tsv", "description": "Differential APA genes with PolyAIndex metric"},
            {"name": "utr_length_plots",  "type": "pdf", "description": "Read density visualisations for top differential APA genes"},
        ],
        "example_queries": [
            "Run PolyAMiner-Bulk on my RNA-seq data",
            "Detect alternative polyadenylation from bulk RNA-seq",
            "APA analysis comparing two conditions",
            "Find 3'UTR length changes between treated and control samples",
        ],
        "tags": ["APA", "alternative_polyadenylation", "PolyAMiner", "3UTR", "RNA-seq"],
    },
    {
        "name": "drug_discovery_screening",
        "display_name": "Drug Discovery Screening Pipeline",
        "domain": "drug_discovery",
        "description": (
            "Multi-phase drug discovery pipeline: ADMET screening, molecular docking, "
            "structure-based binding affinity prediction, and compound prioritisation report."
        ),
        "steps": [
            {"order": 1, "workflow_name": "predict_admet_properties",           "role": "admet_screening",         "params_template": {}},
            {"order": 2, "workflow_name": "structure_prediction_docking",       "role": "molecular_docking",       "params_template": {}},
            {"order": 3, "workflow_name": "predict_binding_affinity_protein_1d_sequence", "role": "binding_affinity", "params_template": {}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "filtered_compounds", "to_step": 2, "to_input": "compounds"},
            {"from_step": 2, "from_output": "docked_poses",       "to_step": 3, "to_input": "complexes"},
        ],
        "required_inputs": [
            {"name": "compound_library", "type": "sdf|smiles", "description": "Compound structures to screen"},
            {"name": "target_structure", "type": "pdb",        "description": "Target protein structure"},
        ],
        "expected_outputs": [
            {"name": "admet_report",       "type": "tsv",  "description": "ADMET property predictions per compound"},
            {"name": "docking_scores",     "type": "tsv",  "description": "Docking scores and binding poses"},
            {"name": "priority_compounds", "type": "sdf",  "description": "Top-ranked compounds after all filters"},
        ],
        "example_queries": [
            "Screen this compound library against the target and rank by ADMET and docking",
            "Run ADMET screening then molecular docking",
            "Drug discovery pipeline: filter by ADMET then dock",
        ],
        "tags": ["drug_discovery", "ADMET", "docking", "virtual_screening", "compound_prioritisation"],
    },
    {
        "name": "drug_discovery_admet_gated_screening",
        "display_name": "ADMET-Gated Virtual Screening",
        "domain": "drug_discovery",
        "description": (
            "Compound library screening with upfront ADMET filtering before docking: "
            "pharmacophore pre-screen → ADMET triage (hERG, DILI, Ames, ClinTox) → "
            "AutoDock Vina docking → integrated ranking. Only ADMET-passing compounds "
            "advance to the computationally expensive docking step."
        ),
        "steps": [
            {"order": 1, "workflow_name": "pharmacophore_filtering",   "role": "pharmacophore_prescreen",  "params_template": {"min_features": 3}},
            {"order": 2, "workflow_name": "predict_admet_properties",  "role": "admet_triage",             "params_template": {"profile": "druglike_lead"}},
            {"order": 3, "workflow_name": "structure_prediction_docking","role": "docking",                "params_template": {"docking_engine": "vina"}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "filtered_smiles",  "to_step": 2, "to_input": "smiles"},
            {"from_step": 2, "from_output": "passed_compounds", "to_step": 3, "to_input": "ligand_sdf"},
        ],
        "required_inputs": [
            {"name": "reference_actives", "type": "smiles",     "description": "Known active compounds to define pharmacophore"},
            {"name": "library",           "type": "smiles|sdf", "description": "Compound library to screen"},
            {"name": "target_structure",  "type": "pdb|fasta",  "description": "Target protein structure or sequence"},
        ],
        "expected_outputs": [
            {"name": "ranked_compounds",  "type": "csv",  "description": "Final ranked compounds with docking and ADMET scores"},
            {"name": "admet_report",      "type": "tsv",  "description": "ADMET flags per compound"},
            {"name": "docking_poses",     "type": "sdf",  "description": "Top docking pose per compound"},
        ],
        "example_queries": [
            "Screen this library against the target, filter by ADMET first, then dock",
            "Run ADMET triage before docking to save compute",
            "Pharmacophore pre-screen then ADMET then Vina docking",
            "Virtual screening with upfront toxicity filtering",
        ],
        "tags": ["drug_discovery", "virtual_screening", "ADMET", "pharmacophore", "docking", "compound_triage"],
    },
    {
        "name": "target_to_lead_full",
        "display_name": "Full Target-to-Lead Pipeline",
        "domain": "drug_discovery",
        "description": (
            "Complete computational pipeline from a novel target protein to ranked, "
            "ADMET-filtered lead compounds with binding free energy validation: "
            "pocket detection → pharmacophore screen → ADMET triage → docking → "
            "MM-GBSA re-ranking → REINVENT4 analogues for top hits."
        ),
        "steps": [
            {"order": 1, "workflow_name": "pocket_detection_druggability","role": "pocket_detection",    "params_template": {}},
            {"order": 2, "workflow_name": "pharmacophore_filtering",       "role": "prescreen",          "params_template": {"min_features": 3}},
            {"order": 3, "workflow_name": "predict_admet_properties",      "role": "admet_triage",       "params_template": {"profile": "druglike_lead"}},
            {"order": 4, "workflow_name": "structure_prediction_docking",  "role": "docking",            "params_template": {}},
            {"order": 5, "workflow_name": "GROMACS Protein-Ligand MD + MM-GBSA", "role": "fep_reranking","params_template": {"sim_ns": 10}},
            {"order": 6, "workflow_name": "REINVENT4 Generative Lead Design",    "role": "lead_gen",    "params_template": {"n_compounds": 50}},
        ],
        "connections": [
            {"from_step": 1, "from_output": "pocket_json",       "to_step": 4, "to_input": "pocket_coords"},
            {"from_step": 2, "from_output": "filtered_smiles",   "to_step": 3, "to_input": "smiles"},
            {"from_step": 3, "from_output": "passed_compounds",  "to_step": 4, "to_input": "ligand_sdf"},
            {"from_step": 4, "from_output": "vina_poses",        "to_step": 5, "to_input": "docked_poses"},
            {"from_step": 5, "from_output": "mmgbsa_scores",     "to_step": 6, "to_input": "seed_smiles"},
        ],
        "required_inputs": [
            {"name": "target_fasta_or_pdb", "type": "fasta|pdb", "description": "Target protein sequence or structure"},
            {"name": "compound_library",    "type": "smiles|sdf", "description": "Compound library to screen"},
            {"name": "reference_actives",   "type": "smiles",     "description": "Known actives for pharmacophore (optional)"},
        ],
        "expected_outputs": [
            {"name": "ranked_leads",       "type": "csv",  "description": "Final ranked leads after MM-GBSA"},
            {"name": "generated_analogues","type": "sdf",  "description": "REINVENT4-generated analogues of top hits"},
            {"name": "druggability_report","type": "json", "description": "Target pocket analysis"},
        ],
        "example_queries": [
            "Run the full target-to-lead pipeline on this novel protein",
            "From FASTA to ranked leads: pocket detection, ADMET, docking, and lead generation",
            "Full computational drug discovery pipeline for a new target",
            "End-to-end drug discovery starting from a protein sequence",
        ],
        "tags": ["drug_discovery", "target_to_lead", "pocket_detection", "ADMET", "docking", "MM-GBSA", "REINVENT4", "lead_optimisation"],
    },
]


# ── Schema ────────────────────────────────────────────────────────────────────

def _seed_workflow_chains(cursor: sqlite3.Cursor, conn: sqlite3.Connection):
    """Insert or update curated workflow chains. Existing rows are updated in-place."""
    now = datetime.utcnow().isoformat()
    inserted = updated = 0
    for chain in CURATED_CHAINS:
        cursor.execute("SELECT id FROM workflow_chains WHERE name=?", (chain["name"],))
        row = cursor.fetchone()
        payload = dict(
            display_name    = chain["display_name"],
            domain          = chain["domain"],
            description     = chain.get("description", ""),
            steps           = json.dumps(chain.get("steps", [])),
            connections     = json.dumps(chain.get("connections", [])),
            required_inputs = json.dumps(chain.get("required_inputs", [])),
            expected_outputs= json.dumps(chain.get("expected_outputs", [])),
            example_queries = json.dumps(chain.get("example_queries", [])),
            tags            = json.dumps(chain.get("tags", [])),
            source          = chain.get("source", "curated"),
            updated_at      = now,
        )
        if row:
            sets = ", ".join(f"{k}=?" for k in payload)
            cursor.execute(
                f"UPDATE workflow_chains SET {sets} WHERE name=?",
                [*payload.values(), chain["name"]],
            )
            updated += 1
        else:
            payload["name"]       = chain["name"]
            payload["created_at"] = now
            cols   = ", ".join(payload.keys())
            marks  = ", ".join("?" * len(payload))
            cursor.execute(
                f"INSERT INTO workflow_chains ({cols}) VALUES ({marks})",
                list(payload.values()),
            )
            inserted += 1
    conn.commit()
    print(f"    workflow_chains: {inserted} inserted, {updated} updated ({len(CURATED_CHAINS)} total)")


def ensure_schema(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(workflows)")
    cols = {c[1] for c in cursor.fetchall()}
    new_cols = {
        "source": "TEXT DEFAULT 'unknown'", "format": "TEXT DEFAULT 'galaxy_ga'",
        "executable": "INTEGER DEFAULT 1",  "docker_image": "TEXT",
        "category": "TEXT",                 "workflow_hash": "TEXT",
        "indexed_at": "TEXT",
        "input_types": "TEXT DEFAULT '[]'",
        "output_types": "TEXT DEFAULT '[]'",
    }
    for col, defn in new_cols.items():
        if col not in cols:
            try:
                cursor.execute(f"ALTER TABLE workflows ADD COLUMN {col} {defn}")
                print(f"    Added column: {col}")
            except sqlite3.OperationalError as e:
                if "duplicate column" not in str(e).lower():
                    raise

    # ── workflow_chains table ─────────────────────────────────────────────────
    # Stores expert-curated (and eventually learned) multi-step workflow
    # compositions keyed by research project type.  The workflow generator
    # checks this table first before falling back to LLM-driven assembly.
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS workflow_chains (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            name            TEXT NOT NULL UNIQUE,
            display_name    TEXT NOT NULL,
            domain          TEXT NOT NULL,
            description     TEXT,

            -- Ordered list of steps: JSON array of
            --   {order, workflow_name, role, params_template}
            steps           TEXT NOT NULL DEFAULT '[]',

            -- Data-flow connections between steps: JSON array of
            --   {from_step, from_output, to_step, to_input}
            connections     TEXT NOT NULL DEFAULT '[]',

            -- What the user must provide at chain start
            required_inputs TEXT NOT NULL DEFAULT '[]',

            -- What the chain produces at the end
            expected_outputs TEXT NOT NULL DEFAULT '[]',

            -- Natural-language queries used for semantic matching
            example_queries TEXT NOT NULL DEFAULT '[]',

            -- JSON array of keyword tags
            tags            TEXT NOT NULL DEFAULT '[]',

            -- 'curated' | 'learned' | 'user_defined'
            source          TEXT NOT NULL DEFAULT 'curated',

            -- Runtime telemetry (updated as chains are executed)
            usage_count     INTEGER NOT NULL DEFAULT 0,
            success_rate    REAL    NOT NULL DEFAULT 0.0,

            created_at      TEXT,
            updated_at      TEXT
        )
    """)
    conn.commit()
    _seed_workflow_chains(cursor, conn)


# ── Workflow insert ───────────────────────────────────────────────────────────

def _wf_insert(cursor, *, name, filename, description, annotation, tags, domain,
               workflow_json, step_count, tools_used, source, format_,
               executable=1, docker_image="", category="", workflow_hash, indexed_at,
               input_types=None, output_types=None):
    inp = json.dumps(input_types) if input_types is not None else "[]"
    out = json.dumps(output_types) if output_types is not None else "[]"
    cursor.execute("""
        INSERT INTO workflows (
            name, filename, description, annotation, tags, domain,
            workflow_json, step_count, tools_used, source, format,
            executable, docker_image, category, workflow_hash, indexed_at,
            input_types, output_types
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (name, filename, description[:500], annotation, tags, domain,
          workflow_json, step_count, tools_used, source, format_,
          executable, docker_image[:300] if docker_image else "", category,
          workflow_hash, indexed_at, inp, out))


def _wf_exists(cursor, wf_hash: str) -> bool:
    cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
    return cursor.fetchone() is not None


# ── Tool insert (into tools table) ───────────────────────────────────────────

def _tool_exists(cursor, tool_id: str) -> bool:
    cursor.execute("SELECT id FROM tools WHERE tool_id=?", (tool_id,))
    return cursor.fetchone() is not None


def _tool_insert(cursor, *, tool_id, name, category, description, language,
                 tags, nfcore_metadata, container_info, wrapper_path, indexed_at):
    cursor.execute("""
        INSERT OR IGNORE INTO tools (
            tool_id, name, category, description, language,
            tags, nfcore_metadata, container_info, wrapper_path,
            availability_status, auto_discovered, discovery_date
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'available', 1, ?)
    """, (tool_id, name, category, description[:500], language,
          tags, nfcore_metadata, container_info[:300] if container_info else "",
          wrapper_path, indexed_at))


# ── Workflow indexers ─────────────────────────────────────────────────────────

def _parse_nfcore_schema(schema_path) -> dict:
    """Parse nextflow_schema.json to extract description and parameter names."""
    try:
        schema = json.loads(schema_path.read_text())
        desc = schema.get("description", "") or schema.get("title", "")
        params = []
        for group in schema.get("definitions", {}).values():
            params.extend(group.get("properties", {}).keys())
        # Also check top-level properties
        params.extend(schema.get("properties", {}).keys())
        return {"description": desc, "params": list(dict.fromkeys(params))[:20]}
    except Exception:
        return {"description": "", "params": []}


def index_nfcore_pipelines(conn: sqlite3.Connection) -> int:
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    # Discover all pipeline directories dynamically — curated metadata takes precedence
    pipeline_dirs: dict = {}
    if NFCORE_PIPELINES_PATH.exists():
        for d in sorted(NFCORE_PIPELINES_PATH.iterdir()):
            if d.is_dir() and not d.name.startswith('.') and d.name != "modules":
                pipeline_dirs[d.name] = d

    for pipeline_name, pipeline_dir in pipeline_dirs.items():
        main_nf = pipeline_dir / "main.nf"
        if not main_nf.exists():
            continue
        try:
            content = main_nf.read_text(errors="replace")
        except Exception:
            continue
        wf_hash = compute_hash(content)
        if _wf_exists(cursor, wf_hash):
            continue

        schema_path = pipeline_dir / "nextflow_schema.json"

        # Curated metadata for known pipelines; auto-generate for the rest
        if pipeline_name in NFCORE_PIPELINES:
            meta = NFCORE_PIPELINES[pipeline_name]
            name = meta["name"]
            description = meta["description"]
            domain = meta["domain"]
            tools = meta["tools"]
        else:
            schema_info = _parse_nfcore_schema(schema_path) if schema_path.exists() else {"description": "", "params": []}
            description = schema_info["description"] or f"nf-core/{pipeline_name} analysis pipeline"
            domain = infer_domain(pipeline_name + " " + description)
            tools = schema_info["params"][:10]
            name = f"nf-core/{pipeline_name}"

        inp, out = extract_nfcore_input_output(
            content, schema_path, pipeline_name=pipeline_name, domain=domain
        )

        try:
            _wf_insert(cursor,
                name=name, filename=f"nfcore/{pipeline_name}/main.nf",
                description=description, annotation=description,
                tags=json.dumps(["nf-core", pipeline_name, domain]),
                domain=domain, workflow_json=content,
                step_count=max(len(tools), 1), tools_used=json.dumps(tools),
                source="nfcore", format_="nextflow",
                category=domain, workflow_hash=wf_hash, indexed_at=now,
                input_types=inp, output_types=out)
            indexed += 1
            print(f"    + {name}")
        except Exception as e:
            print(f"    Error {pipeline_name}: {e}")
    conn.commit()
    return indexed


def index_nfcore_subworkflows(conn: sqlite3.Connection) -> int:
    """
    nf-core composite subworkflows → workflows table.
    These compose multiple modules and represent a meaningful analysis step.
    """
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    if not NFCORE_SUBWF_PATH.exists():
        print(f"  Path not found: {NFCORE_SUBWF_PATH}")
        return 0
    for sw_dir in sorted(NFCORE_SUBWF_PATH.iterdir()):
        if not sw_dir.is_dir():
            continue
        main_nf = sw_dir / "main.nf"
        if not main_nf.exists():
            continue
        content = main_nf.read_text()
        wf_hash = compute_hash(content)
        if _wf_exists(cursor, wf_hash):
            continue
        meta = load_meta_yml(sw_dir / "meta.yml")
        name = meta.get("name", sw_dir.name)
        description = meta.get("description", "nf-core subworkflow")
        keywords = meta.get("keywords", [])
        components = meta.get("components", [])
        domain = infer_domain(" ".join(keywords))
        inp, out = extract_bioc_input_output(content)
        try:
            _wf_insert(cursor,
                name=wf_name(name), filename=f"nf-core-modules/subworkflows/nf-core/{sw_dir.name}/main.nf",
                description=description, annotation=description,
                tags=json.dumps(["nf-core", "subworkflow"] + keywords[:5]),
                domain=domain, workflow_json=content,
                step_count=len(components), tools_used=json.dumps(components),
                source="nfcore_subwf", format_="nextflow",
                category=domain, workflow_hash=wf_hash, indexed_at=now,
                input_types=inp, output_types=out)
            indexed += 1
        except Exception as e:
            print(f"    Error {sw_dir.name}: {e}")
    conn.commit()
    return indexed


def index_biomni_nextflow(conn: sqlite3.Connection) -> int:
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    if not BIOMNI_NF_PATH.exists():
        print(f"  Path not found: {BIOMNI_NF_PATH}")
        return 0
    for domain_dir in sorted(BIOMNI_NF_PATH.iterdir()):
        if not domain_dir.is_dir() or domain_dir.name == "bioconductor":
            continue
        domain = domain_dir.name
        for wf_dir in sorted(domain_dir.iterdir()):
            if not wf_dir.is_dir():
                continue
            main_nf = wf_dir / "main.nf"
            if not main_nf.exists():
                continue
            content = main_nf.read_text()
            wf_hash = compute_hash(content)
            if _wf_exists(cursor, wf_hash):
                continue
            meta = extract_nf_metadata(content)
            description = meta["description"] or f"BioMate {domain} workflow: {wf_dir.name}"
            inp, out = extract_biomni_input_output(content)
            try:
                _wf_insert(cursor,
                    name=wf_name(wf_dir.name),
                    filename=f"nextflow_nfcore/subworkflows/{domain}/{wf_dir.name}/main.nf",
                    description=description, annotation=description,
                    tags=json.dumps([domain, "biomni", "nextflow", wf_dir.name]),
                    domain=domain, workflow_json=content,
                    step_count=len(meta["processes"]), tools_used=json.dumps(meta["processes"]),
                    source="biomni_nextflow", format_="nextflow",
                    docker_image=meta["docker"], category=domain,
                    workflow_hash=wf_hash, indexed_at=now,
                    input_types=inp, output_types=out)
                indexed += 1
            except Exception as e:
                print(f"    Error {domain}/{wf_dir.name}: {e}")
    conn.commit()
    return indexed


def index_galaxy_biomni_unique(conn: sqlite3.Connection) -> int:
    """2 BioMate Galaxy workflows with no Nextflow equivalent (fallback)."""
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    for domain, wf_name_str in GALAXY_UNIQUE_WORKFLOWS:
        ga_file = BIOMNI_GALAXY_UNIQUE_PATH / domain / f"{wf_name_str}.ga"
        if not ga_file.exists():
            continue
        content = ga_file.read_text()
        wf_hash = compute_hash(content)
        if _wf_exists(cursor, wf_hash):
            continue
        try:
            wf_json = json.loads(content)
        except Exception:
            continue
        name = wf_json.get("name", wf_name_str)
        annotation = wf_json.get("annotation", "")
        tools = extract_tools_from_ga(wf_json)
        try:
            _wf_insert(cursor,
                name=name, filename=f"galaxy/subworkflows/{domain}/{wf_name_str}.ga",
                description=annotation or f"BioMate Galaxy unique: {wf_name_str}",
                annotation=annotation,
                tags=json.dumps([domain, "biomni", "galaxy", "pending-conversion"]),
                domain=domain, workflow_json=content,
                step_count=len(wf_json.get("steps", {})), tools_used=json.dumps(tools),
                source="galaxy_biomni", format_="galaxy_ga",
                category=domain, workflow_hash=wf_hash, indexed_at=now)
            indexed += 1
            print(f"    + {domain}/{wf_name_str}  [pending NF conversion]")
        except Exception as e:
            print(f"    Error {domain}/{wf_name_str}: {e}")
    conn.commit()
    return indexed


def index_bioconductor_as_workflows(conn: sqlite3.Connection) -> int:
    """
    Index Bioconductor Nextflow workflow files (.nf) into the workflows table.

    Each on-disk Bioconductor .nf file is a complete Nextflow workflow containing
    both a `process BIOC_<PKG>` block and a `workflow BIOC_<PKG>_WORKFLOW` block
    with proper I/O specs, container/conda directives, and an R analysis script.
    These are runnable pipelines — analogous to nfcore_subwf — not mere tool stubs.

    Architecture:
      tools table      → Bioconductor package metadata for tool-level search
      workflows table  → The runnable .nf workflow file for workflow discovery

    Returns count of newly indexed workflows.
    """
    bioc_nf_path = BIOMNI_NF_PATH / "bioconductor"
    if not bioc_nf_path.exists():
        print(f"  Path not found: {bioc_nf_path}")
        return 0

    cursor = conn.cursor()
    now = datetime.now().isoformat()

    # Pre-load rich metadata from tools table (description, step count, topics)
    tools_meta: Dict[str, Dict] = {}
    for tool_id, name, description, meta_json, topics, category in cursor.execute(
        "SELECT tool_id, name, description, nfcore_metadata, topics, category "
        "FROM tools WHERE tool_id LIKE 'bioconductor/%'"
    ).fetchall():
        tools_meta[tool_id] = {
            "name": name,
            "description": description,
            "nfcore_metadata": meta_json,
            "topics": topics or "",
            "category": category or "",
        }

    indexed = 0
    for pkg_dir in sorted(bioc_nf_path.iterdir()):
        if not pkg_dir.is_dir():
            continue
        main_nf = pkg_dir / "main.nf"
        if not main_nf.exists():
            continue

        pkg = pkg_dir.name
        tool_id = f"bioconductor/{pkg}"
        content = main_nf.read_text()
        wf_hash = compute_hash(content)

        if _wf_exists(cursor, wf_hash):
            continue

        tm = tools_meta.get(tool_id, {})
        name = tm.get("name") or pkg.capitalize()
        description = tm.get("description") or f"Bioconductor R workflow: {pkg}"

        # Total step count from vignette workflows in tools metadata
        step_count = 0
        meta_str = tm.get("nfcore_metadata") or ""
        if meta_str:
            try:
                mj = json.loads(meta_str)
                vw = mj.get("vignette_workflows", [])
                step_count = sum(v.get("total_steps", 0) for v in vw)
            except Exception:
                pass
        if step_count == 0:
            step_count = len(re.findall(r'\bprocess\s+[A-Z]', content))

        # Domain from description + package topics
        domain_text = (description or "") + " " + tm.get("topics", "") + " " + tm.get("category", "")
        domain = infer_domain(domain_text)

        # Upstream dependencies from file header
        upstream_m = re.search(r'//\s*Upstream\s*:\s*(.+)', content)
        deps = []
        if upstream_m:
            deps = [t.strip() for t in upstream_m.group(1).split(",")
                    if t.strip() and t.strip().lower() != "none"]
        tools_used = [tool_id] + [f"bioconductor/{d.lower()}" for d in deps]

        tags = json.dumps([pkg, "bioconductor", "nextflow", "R", domain])

        inp, out = extract_bioc_input_output(content)

        try:
            _wf_insert(cursor,
                name=name,
                # FIX: include subworkflows/ in path to match on-disk location
                filename=f"nextflow_nfcore/subworkflows/bioconductor/{pkg}/main.nf",
                description=description,
                annotation=description,
                tags=tags,
                domain=domain,
                workflow_json=content,
                step_count=step_count,
                tools_used=json.dumps(tools_used),
                source="bioconductor",
                format_="bioconductor_nf",
                category=domain,
                workflow_hash=wf_hash,
                indexed_at=now,
                input_types=inp,
                output_types=out)
            indexed += 1
        except Exception as e:
            print(f"    Error {pkg}: {e}")

    conn.commit()
    return indexed


# ── Backfill input/output types for existing rows ─────────────────────────────

def backfill_input_output_types(conn: sqlite3.Connection) -> Tuple[int, int]:
    """
    Populate input_types / output_types for existing workflow rows that have
    the default empty value '[]'.  Parses the stored workflow_json (nf content)
    using the same logic as the live indexers.

    Returns (rows_updated_input, rows_updated_output).
    """
    cursor = conn.cursor()

    # Fetch rows missing either field
    rows = cursor.execute("""
        SELECT id, source, workflow_json
        FROM workflows
        WHERE (input_types IS NULL OR input_types = '[]' OR input_types = '')
           OR (output_types IS NULL OR output_types = '[]' OR output_types = '')
    """).fetchall()

    updated_inp = updated_out = 0

    # Pre-load nfcore name→domain mapping for backfill
    nfcore_meta_map = {}
    for row_id2, name2, domain2 in cursor.execute(
        "SELECT id, name, domain FROM workflows WHERE source='nfcore'"
    ).fetchall():
        nfcore_meta_map[row_id2] = (name2, domain2)

    for row_id, source, wf_content in rows:
        if not wf_content:
            continue
        try:
            if source == "bioconductor":
                inp, out = extract_bioc_input_output(wf_content)
            elif source == "biomni_nextflow":
                inp, out = extract_biomni_input_output(wf_content)
            elif source == "nfcore":
                name, domain = nfcore_meta_map.get(row_id, ("", "general"))
                pipeline_name = name.replace("nf-core/", "")
                inp, out = extract_nfcore_input_output(
                    wf_content, pipeline_name=pipeline_name, domain=domain
                )
            elif source == "nfcore_subwf":
                inp, out = extract_bioc_input_output(wf_content)
            else:
                continue

            inp_json = json.dumps(inp) if inp else "[]"
            out_json = json.dumps(out) if out else "[]"

            cursor.execute("""
                UPDATE workflows
                SET input_types=?, output_types=?
                WHERE id=?
            """, (inp_json, out_json, row_id))

            if inp:
                updated_inp += 1
            if out:
                updated_out += 1

        except Exception as e:
            print(f"    Backfill error row {row_id}: {e}")

    conn.commit()
    return updated_inp, updated_out


# ── Tool indexers (tools table) ───────────────────────────────────────────────

def link_bioconductor_nf_wrappers(conn: sqlite3.Connection) -> Tuple[int, int]:
    """
    Link the 1818 Bioconductor NF wrapper files to their tools table entries
    by populating wrapper_path.  Also inserts the ~32 packages that have an
    NF file but no existing tools entry.

    The tools table already has 2241 rich Bioconductor entries (from Bioconductor
    web scraping with vignette steps, function lists, container info, etc.).
    This step simply connects those rows to the .nf files on disk.

    Returns (updated, inserted).
    """
    bioc_nf_path = BIOMNI_NF_PATH / "bioconductor"
    if not bioc_nf_path.exists():
        return 0, 0

    cursor = conn.cursor()
    updated = inserted = 0
    now = datetime.now().isoformat()

    for pkg_dir in sorted(bioc_nf_path.iterdir()):
        if not pkg_dir.is_dir():
            continue
        main_nf = pkg_dir / "main.nf"
        if not main_nf.exists():
            continue

        pkg = pkg_dir.name
        tool_id = f"bioconductor/{pkg}"
        wrapper_path = f"nextflow_nfcore/subworkflows/bioconductor/{pkg}/main.nf"

        row = cursor.execute(
            "SELECT id, wrapper_path FROM tools WHERE tool_id=?", (tool_id,)
        ).fetchone()

        if row:
            if not row[1]:
                cursor.execute(
                    "UPDATE tools SET wrapper_path=? WHERE tool_id=?",
                    (wrapper_path, tool_id)
                )
                updated += 1
        else:
            content = main_nf.read_text()
            header = re.search(r'// ={10,}\n(.*?)// ={10,}', content, re.DOTALL)
            description = f"Bioconductor R package: {pkg}"
            if header:
                for line in header.group(1).splitlines():
                    line = line.lstrip("/ ").strip()
                    if re.match(r'^[A-Z]', line) and len(line) > 20:
                        description = line[:500]
                        break
            docker_m = re.search(r"'quay\.io/[^']+bioconductor-([^:]+:[^']+)'", content)
            container = docker_m.group(0).strip("'") if docker_m else ""

            cursor.execute("""
                INSERT OR IGNORE INTO tools (
                    tool_id, name, description, language, category,
                    wrapper_path, container_info, availability_status,
                    auto_discovered, discovery_date
                ) VALUES (?, ?, ?, 'nextflow', 'Bioconductor', ?, ?, 'available', 1, ?)
            """, (tool_id, pkg, description[:500], wrapper_path,
                  container[:300], now))
            if cursor.rowcount:
                inserted += 1

    conn.commit()
    return updated, inserted


def index_nfcore_modules_as_tools(conn: sqlite3.Connection) -> int:
    """
    nf-core individual tool modules → tools table (NOT workflows table).
    Each module wraps a single bioinformatics tool (e.g. star/align, samtools/sort).
    Uses meta.yml for description, keywords, and container info.
    """
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    if not NFCORE_MODULES_PATH.exists():
        print(f"  Path not found: {NFCORE_MODULES_PATH}")
        return 0

    for tool_dir in sorted(NFCORE_MODULES_PATH.iterdir()):
        if not tool_dir.is_dir():
            continue
        # Collect (mod_id, main_nf, meta_yml) entries — direct or sub-command
        entries: List[Tuple[str, Path, Path]] = []
        direct_main = tool_dir / "main.nf"
        if direct_main.exists():
            entries.append((tool_dir.name, direct_main, tool_dir / "meta.yml"))
        else:
            for sub in sorted(tool_dir.iterdir()):
                if sub.is_dir() and (sub / "main.nf").exists():
                    entries.append((f"{tool_dir.name}/{sub.name}", sub / "main.nf", sub / "meta.yml"))

        for mod_id, main_nf, meta_yml in entries:
            tool_id = f"nfcore/{mod_id}"
            if _tool_exists(cursor, tool_id):
                continue

            meta = load_meta_yml(meta_yml)
            description = meta.get("description", f"nf-core module: {mod_id}")
            keywords = meta.get("keywords", [])
            tools_meta = meta.get("tools", [])

            # category from first tool's description or keywords
            category_text = " ".join(keywords)
            if tools_meta and isinstance(tools_meta[0], dict):
                first_tool = list(tools_meta[0].values())[0]
                if isinstance(first_tool, dict):
                    category_text += " " + first_tool.get("description", "")

            # container from main.nf
            content = main_nf.read_text()
            container_m = re.search(r"'(community\.wave\.seqera\.io[^']+|quay\.io[^']+|ghcr\.io[^']+)'", content)
            container = container_m.group(1) if container_m else ""

            # Store full meta as JSON for rich downstream use
            nfcore_meta_json = json.dumps({
                "keywords": keywords,
                "tools": tools_meta,
                "components": meta.get("components", []),
                "wrapper_path": f"nf-core-modules/modules/nf-core/{mod_id}/main.nf",
            })

            try:
                _tool_insert(cursor,
                    tool_id=tool_id,
                    name=wf_name(mod_id),
                    category=", ".join(keywords[:5]) if keywords else "Nextflow",
                    description=description,
                    language="nextflow",
                    tags=json.dumps(["nf-core", "module"] + keywords[:5]),
                    nfcore_metadata=nfcore_meta_json,
                    container_info=container,
                    wrapper_path=f"nf-core-modules/modules/nf-core/{mod_id}/main.nf",
                    indexed_at=now)
                indexed += 1
            except Exception as e:
                print(f"    Error {mod_id}: {e}")

    conn.commit()
    return indexed


# ── Stats ─────────────────────────────────────────────────────────────────────

def get_stats(conn: sqlite3.Connection) -> Dict:
    cur = conn.cursor()
    wf_total = cur.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
    wf_by_src = dict(cur.execute("SELECT source, COUNT(*) FROM workflows GROUP BY source ORDER BY COUNT(*) DESC").fetchall())
    tool_total = cur.execute("SELECT COUNT(*) FROM tools").fetchone()[0]
    tool_nfcore = cur.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE 'nfcore/%'").fetchone()[0]
    tool_bioc = cur.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE 'bioconductor/%'").fetchone()[0]
    wf_with_input = cur.execute(
        "SELECT COUNT(*) FROM workflows WHERE input_types IS NOT NULL AND input_types != '[]' AND input_types != ''"
    ).fetchone()[0]
    wf_with_output = cur.execute(
        "SELECT COUNT(*) FROM workflows WHERE output_types IS NOT NULL AND output_types != '[]' AND output_types != ''"
    ).fetchone()[0]
    return {
        "workflows": wf_total, "wf_by_source": wf_by_src,
        "tools": tool_total, "tools_nfcore": tool_nfcore, "tools_bioconductor": tool_bioc,
        "wf_with_input_types": wf_with_input, "wf_with_output_types": wf_with_output,
    }


# ── Cleanup ───────────────────────────────────────────────────────────────────

def _remove_wf_source(conn, source):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM workflows WHERE source=?", (source,))
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM workflows WHERE source=?", (source,))
        conn.commit()
        print(f"    Removed {count} workflows[source={source}]")
    return count


def _remove_tools_like(conn, pattern):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE ?", (pattern,))
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM tools WHERE tool_id LIKE ?", (pattern,))
        conn.commit()
        print(f"    Removed {count} tools[tool_id LIKE {pattern}]")
    return count


def rebuild_clean(conn: sqlite3.Connection):
    """Remove all entries that will be re-indexed."""
    for src in ("biomni", "biomni_nextflow", "galaxy_local", "galaxy_biomni",
                "nfcore_subwf", "nfcore_module", "bioconductor"):
        _remove_wf_source(conn, src)
    # Remove nf-core module entries from tools (will re-add)
    _remove_tools_like(conn, "nfcore/%")
    # Clear bioconductor wrapper_paths so link_bioconductor_nf_wrappers re-populates them
    cur = conn.cursor()
    cur.execute("UPDATE tools SET wrapper_path='' WHERE tool_id LIKE 'bioconductor/%'")
    conn.commit()
    print(f"    Cleared {cur.rowcount} bioconductor wrapper_path entries (will re-link)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Unified Workflow + Tool Indexer")
    parser.add_argument("--db-path", default=str(DB_PATH))
    parser.add_argument("--rebuild", action="store_true",
                        help="Remove re-indexable entries and rebuild from scratch")
    parser.add_argument("--update-types", action="store_true",
                        help="Backfill input_types/output_types for existing rows only")
    args = parser.parse_args()

    print("=" * 60)
    print("Unified Workflow + Tool Indexer")
    print("=" * 60)

    if not Path(args.db_path).exists():
        print(f"ERROR: Database not found at {args.db_path}")
        return 1

    conn = sqlite3.connect(args.db_path)
    try:
        print("\nPhase 0: Schema...")
        ensure_schema(conn)

        s = get_stats(conn)
        print(f"\nInitial: {s['workflows']} workflows | {s['tools']} tools")
        print(f"  workflows by source: {s['wf_by_source']}")
        print(f"  input_types populated: {s['wf_with_input_types']}  output_types: {s['wf_with_output_types']}")
        print(f"  tools: {s['tools_nfcore']} nfcore | {s['tools_bioconductor']} bioconductor")

        if args.update_types:
            print("\n[--update-types] Backfilling input/output types for existing rows...")
            inp_upd, out_upd = backfill_input_output_types(conn)
            print(f"  input_types updated: {inp_upd}  |  output_types updated: {out_upd}")
            s2 = get_stats(conn)
            print(f"\nAfter backfill:")
            print(f"  input_types populated: {s2['wf_with_input_types']}")
            print(f"  output_types populated: {s2['wf_with_output_types']}")
            print("=" * 60)
            return 0

        if args.rebuild:
            print("\nPhase 1: Cleanup...")
            rebuild_clean(conn)

        # ── WORKFLOWS TABLE ──────────────────────────────────────────────────
        print("\nPhase 2 [workflows]: nf-core full pipelines")
        n1 = index_nfcore_pipelines(conn)
        print(f"  Added: {n1}")

        print("\nPhase 3 [workflows]: nf-core composite subworkflows")
        n2 = index_nfcore_subworkflows(conn)
        print(f"  Added: {n2}")

        print("\nPhase 4 [workflows]: BioMate Nextflow subworkflows")
        n3 = index_biomni_nextflow(conn)
        print(f"  Added: {n3}")

        print("\nPhase 5 [workflows]: Unique BioMate Galaxy workflows (no NF equivalent)")
        n4 = index_galaxy_biomni_unique(conn)
        print(f"  Added: {n4}")

        print("\nPhase 6 [workflows]: Bioconductor Nextflow workflows (~1818 .nf files)")
        n5 = index_bioconductor_as_workflows(conn)
        print(f"  Added: {n5}")

        # Backfill types for any existing rows not yet updated
        print("\nPhase 6b: Backfilling input/output types for existing rows...")
        inp_upd, out_upd = backfill_input_output_types(conn)
        print(f"  input_types updated: {inp_upd}  |  output_types updated: {out_upd}")

        # ── TOOLS TABLE ──────────────────────────────────────────────────────
        print("\nPhase 7 [tools]: nf-core individual modules → tools table")
        n6 = index_nfcore_modules_as_tools(conn)
        print(f"  Added: {n6}")

        print("\nPhase 8 [tools]: Link Bioconductor NF wrappers to tools table entries")
        bioc_upd, bioc_ins = link_bioconductor_nf_wrappers(conn)
        print(f"  wrapper_path linked: {bioc_upd}  |  new entries: {bioc_ins}")

        s2 = get_stats(conn)
        print(f"\nFinal:")
        print(f"  workflows: {s2['workflows']}  by source: {s2['wf_by_source']}")
        print(f"  input_types populated: {s2['wf_with_input_types']}  output_types: {s2['wf_with_output_types']}")
        print(f"  tools:     {s2['tools']}  (nfcore={s2['tools_nfcore']}, bioconductor={s2['tools_bioconductor']})")
        print(f"\n  workflows added: {n1+n2+n3+n4+n5}   tools added: {n6}+{bioc_ins}(bioc)   bioc linked: {bioc_upd}")
        print("=" * 60)

    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    exit(main())
