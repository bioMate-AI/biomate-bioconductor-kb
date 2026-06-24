"""
Bioconductor pipeline chain templates (v2).

These chains use BIOC_* single-package wrappers chained through the
existing workflow_chain executor. They are registered in the
workflow_chains DB table at startup via register_bioc_chains().

Naming convention:
  BIOC_<PKG>         = atomic single-package wrapper (existing)
  bioc_<analysis>_v2 = multi-step Bioconductor pipeline (this file)
"""

import json
import logging
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

log = logging.getLogger(__name__)

_DB_PATH = Path(__file__).parent.parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

# ── Chain template definitions ────────────────────────────────────────────────
# Each step's workflow_name must match an existing BIOC_* wrapper or
# a registered workflow in the DB.
# connections: from_step/to_step use 1-based step order.

BIOC_CHAIN_TEMPLATES: List[Dict[str, Any]] = [
    {
        "name": "bioc_bulk_rnaseq_de_v2",
        "display_name": "Bulk RNA-seq → Differential Expression → Pathway Enrichment",
        "domain": "transcriptomics",
        "description": (
            "Single-method downstream RNA-seq differential expression from a PRE-COMPUTED "
            "COUNT MATRIX — use when you already have counts + a sample sheet and want a "
            "DESeq2-only wrapper chain (not multi-method consensus DE, and not raw-read "
            "processing). DESeq2 DE, then clusterProfiler GO/KEGG enrichment and enrichplot "
            "visualisation. Input: count matrix TSV + sample sheet CSV."
        ),
        "steps": [
            {
                "order": 1,
                "workflow_name": "BIOC_DESEQ2",
                "role": "differential_expression",
                "params_template": {"design_formula": "~condition", "reference_level": "control"},
            },
            {
                "order": 2,
                "workflow_name": "BIOC_CLUSTERPROFILER",
                "role": "pathway_enrichment",
                "params_template": {"ontology": "BP", "organism": "hsa", "pvalueCutoff": 0.05},
            },
            {
                "order": 3,
                "workflow_name": "BIOC_ENRICHPLOT",
                "role": "visualisation",
                "params_template": {},
            },
        ],
        "connections": [
            {
                "from_step": 1, "from_output": "results",
                "to_step": 2, "to_input": "de_results",
                # Inherit the genome param from step 1 and convert to KEGG organism code
                # so clusterProfiler knows which organism DB to use (e.g. GRCh38 → "hsa").
                "context_params": {
                    "organism": {"from_run_param": "genome", "transform": "genome_to_organism"}
                },
            },
            {"from_step": 2, "from_output": "enrichment", "to_step": 3, "to_input": "enrichment_obj"},
        ],
        "required_inputs": ["count_matrix", "sample_sheet"],
        "expected_outputs": ["de_table", "pathway_dotplot", "enrichmap"],
        "example_queries": [
            "run differential expression on my RNA-seq counts",
            "DESeq2 then pathway analysis",
            "what genes are enriched after rnaseq",
            "bioconductor downstream analysis of count matrix",
            "what should I do after rnaseq completes",
        ],
        "tags": ["rnaseq", "deseq2", "clusterprofiler", "go-enrichment", "bioconductor"],
        "trigger_on_workflows": ["rnaseq", "salmon", "star_align", "differentialabundance"],
        "trigger_on_output_extensions": ["tsv", "csv"],
    },
    {
        "name": "bioc_scrna_cluster_v2",
        "display_name": "Single-cell RNA-seq → QC → Normalisation → Clustering → UMAP",
        "domain": "single_cell",
        "description": (
            "Single-cell downstream QC + normalisation from a COUNT MATRIX — use when you "
            "already have a count matrix and want scater QC/filtering then scran "
            "normalisation, HVG selection and UMAP (lighter than the per-method consensus "
            "DE pipeline). Input: raw count matrix."
        ),
        # SingleCellExperiment (data-container) and uwot (UMAP, part of scater) are not
        # standalone analysis workflows — scater loads the count matrix and runs UMAP itself.
        "steps": [
            {
                "order": 1,
                "workflow_name": "BIOC_SCATER",
                "role": "qc_filtering",
                "params_template": {"mito_threshold": 20, "min_genes": 200},
            },
            {
                "order": 2,
                "workflow_name": "BIOC_SCRAN",
                "role": "normalisation_hvg_umap",
                "params_template": {"n_hvgs": 2000, "n_neighbors": 15, "min_dist": 0.1},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "rds", "to_step": 2, "to_input": "sce_rds"},
        ],
        "required_inputs": ["count_matrix"],
        "expected_outputs": ["umap_plot", "clustered_sce_rds", "marker_genes"],
        "example_queries": [
            "single cell analysis from raw counts",
            "scRNA-seq QC normalisation clustering",
            "UMAP of my single cell data",
            "downstream single cell bioconductor pipeline",
        ],
        "tags": ["scrna", "singlecellexperiment", "scater", "scran", "umap", "bioconductor"],
        "trigger_on_workflows": ["cellranger", "starsolo", "alevin"],
        "trigger_on_output_extensions": ["h5", "h5ad", "tsv"],
    },
    {
        "name": "bioc_chipseq_annotation_v2",
        "display_name": "ChIP-seq Peaks → GRanges → Gene Annotation → Pathway Enrichment",
        "domain": "epigenomics",
        "description": (
            "Bioconductor annotation of ChIP-seq peaks: "
            "import BED file as GRanges, annotate peaks to nearest gene and genomic feature "
            "with ChIPseeker, then run clusterProfiler GO enrichment on annotated genes. "
            "Natural handoff point from nf-core/chipseq BED output."
        ),
        # GenomicRanges (data-container) is not a standalone workflow — ChIPseeker reads the
        # BED/peak file directly and builds the GRanges internally.
        "steps": [
            {
                "order": 1,
                "workflow_name": "BIOC_CHIPSEEKER",
                "role": "annotate_peaks",
                "params_template": {"tss_region": [-3000, 3000], "organism": "hg38"},
            },
            {
                "order": 2,
                "workflow_name": "BIOC_CLUSTERPROFILER",
                "role": "pathway_enrichment",
                "params_template": {"ontology": "BP", "organism": "hsa"},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "results", "to_step": 2, "to_input": "gene_list"},
        ],
        "required_inputs": ["bed_file"],
        "expected_outputs": ["annotated_peaks_csv", "peak_distribution_plot", "pathway_dotplot"],
        "example_queries": [
            "annotate my chip-seq peaks",
            "what genes are near my peaks",
            "chipseeker annotation of bed file",
            "bioconductor chip-seq downstream",
            "annotate peaks from chipseq run",
        ],
        "tags": ["chipseq", "chipseeker", "genomicranges", "peaks", "annotation", "bioconductor"],
        "trigger_on_workflows": ["chipseq", "cut_and_run", "cutandtag"],
        "trigger_on_output_extensions": ["bed", "narrowPeak", "broadPeak"],
    },
    {
        "name": "bioc_variant_annotation_v2",
        "display_name": "VCF Variants → Annotation → Gene-level Summary",
        "domain": "genomics",
        "description": (
            "Bioconductor VCF annotation pipeline: "
            "import VCF with VariantAnnotation, annotate variants to genes and "
            "transcripts with ensembldb, then summarise at gene level with GenomicRanges. "
            "Natural handoff from nf-core/sarek or GATK variant calling output."
        ),
        # VariantAnnotation imports the VCF and does gene/transcript annotation natively
        # (ensembldb/GenomicRanges are data-containers it uses internally, not workflows).
        # Downstream gene-set enrichment on the hit genes via clusterProfiler.
        "steps": [
            {
                "order": 1,
                "workflow_name": "BIOC_VARIANTANNOTATION",
                "role": "import_annotate_vcf",
                "params_template": {"genome": "hg38"},
            },
            {
                "order": 2,
                "workflow_name": "BIOC_CLUSTERPROFILER",
                "role": "gene_set_enrichment",
                "params_template": {"ontology": "BP", "organism": "hsa"},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "results", "to_step": 2, "to_input": "gene_list"},
        ],
        "required_inputs": ["vcf_file"],
        "expected_outputs": ["annotated_variants_csv", "gene_summary_csv"],
        "example_queries": [
            "annotate my VCF variants",
            "what genes do my variants fall in",
            "bioconductor variant annotation",
            "annotate sarek vcf output",
        ],
        "tags": ["vcf", "variants", "variantannotation", "ensembldb", "genomicranges", "bioconductor"],
        "trigger_on_workflows": ["sarek", "gatk", "variantcalling", "haplotypecaller"],
        "trigger_on_output_extensions": ["vcf", "vcf.gz", "bcf"],
    },
    {
        "name": "bioc_methylation_dm_v2",
        "display_name": "IDAT → Normalisation → Differential Methylation → Gene Enrichment",
        "domain": "epigenomics",
        "description": (
            "EPIC/450K array methylation from IDAT — minfi load + functional normalisation, "
            "DSS differential methylation, missMethyl gene-set enrichment. Use when you want "
            "the DSS-based differential-methylation + enrichment wrapper chain. "
            "Also applicable to bismark bisulfite coverage from nf-core/methylseq."
        ),
        "steps": [
            {
                "order": 1,
                "workflow_name": "BIOC_MINFI",
                "role": "load_normalise",
                "params_template": {"normalisation": "functional"},
            },
            {
                "order": 2,
                "workflow_name": "BIOC_DSS",
                "role": "differential_methylation",
                "params_template": {"delta": 0.1, "p_threshold": 0.05},
            },
            {
                "order": 3,
                "workflow_name": "BIOC_MISSMETHYL",
                "role": "gene_set_enrichment",
                "params_template": {"collection": "GO", "array_type": "EPIC"},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "rds", "to_step": 2, "to_input": "methylset_rds"},
            {"from_step": 2, "from_output": "results", "to_step": 3, "to_input": "dmp_results"},
        ],
        "required_inputs": ["idat_dir"],
        "expected_outputs": ["dmp_table", "dmp_plot", "pathway_table"],
        "example_queries": [
            "differential methylation analysis",
            "minfi epic array analysis",
            "methylation downstream bioconductor",
            "dmps from methylseq",
        ],
        "tags": ["methylation", "minfi", "dss", "missmethyl", "epic", "bioconductor"],
        "trigger_on_workflows": ["methylseq", "bismark", "wgbs"],
        "trigger_on_output_extensions": ["idat", "bismark.cov", "bismark_coverage"],
    },
    {
        "name": "bioc_proteomics_de_v2",
        "display_name": "mzML → Protein Quantification → Differential Expression → QC Report",
        "domain": "proteomics",
        "description": (
            "Bioconductor label-free proteomics pipeline: "
            "load mzML files with MSnbase, normalise and impute missing values, "
            "run limma differential protein expression, and produce MSstats QC report. "
            "Covers DDA label-free workflows."
        ),
        # Core label-free MSstats is not indexed (only TMT/PTM variants, a different quant
        # mode); limma already produces the differential-expression statistics + volcano, so
        # the supplementary MSstats QC step is dropped rather than remapped to a wrong mode.
        "steps": [
            {
                "order": 1,
                "workflow_name": "BIOC_MSNBASE",
                "role": "load_quantify",
                "params_template": {"method": "label_free"},
            },
            {
                "order": 2,
                "workflow_name": "BIOC_LIMMA",
                "role": "differential_expression",
                "params_template": {"adj_method": "BH", "lfc_threshold": 1.0},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "rds", "to_step": 2, "to_input": "msnset_rds"},
        ],
        "required_inputs": ["mzml_files"],
        "expected_outputs": ["de_proteins_csv", "volcano_plot", "qc_report"],
        "example_queries": [
            "proteomics differential expression",
            "mzml limma analysis",
            "bioconductor proteomics pipeline",
            "label free protein de analysis",
        ],
        "tags": ["proteomics", "msnbase", "limma", "msstats", "label-free", "bioconductor"],
        "trigger_on_workflows": ["diaproteomics", "maxquant", "openms"],
        "trigger_on_output_extensions": ["mzml", "mzML", "txt"],
    },
]


# ── Registration ──────────────────────────────────────────────────────────────

def register_bioc_chains(db_path: Path = _DB_PATH) -> int:
    """
    Insert or update BIOC_CHAIN_TEMPLATES in the workflow_chains table.
    Returns the number of chains upserted.
    """
    now = datetime.now(timezone.utc).isoformat()
    conn = sqlite3.connect(str(db_path))
    upserted = 0
    try:
        for tpl in BIOC_CHAIN_TEMPLATES:
            conn.execute(
                """
                INSERT INTO workflow_chains
                  (name, display_name, domain, description, steps, connections,
                   required_inputs, expected_outputs, example_queries, tags,
                   source, usage_count, success_rate, created_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?, 'bioc_reactive', 0, 0.0, ?,?)
                ON CONFLICT(name) DO UPDATE SET
                  display_name    = excluded.display_name,
                  domain          = excluded.domain,
                  description     = excluded.description,
                  steps           = excluded.steps,
                  connections     = excluded.connections,
                  required_inputs = excluded.required_inputs,
                  expected_outputs= excluded.expected_outputs,
                  example_queries = excluded.example_queries,
                  tags            = excluded.tags,
                  updated_at      = excluded.updated_at
                """,
                (
                    tpl["name"],
                    tpl["display_name"],
                    tpl["domain"],
                    tpl["description"],
                    json.dumps(tpl["steps"]),
                    json.dumps(tpl["connections"]),
                    json.dumps(tpl.get("required_inputs", [])),
                    json.dumps(tpl.get("expected_outputs", [])),
                    json.dumps(tpl.get("example_queries", [])),
                    json.dumps(tpl.get("tags", [])),
                    now,
                    now,
                ),
            )
            upserted += 1
        conn.commit()
        log.info("bioc_chain_templates: upserted %d chains", upserted)
    except Exception as exc:
        log.error("bioc_chain_templates registration failed: %s", exc)
        conn.rollback()
        raise
    finally:
        conn.close()
    return upserted


def suggest_chains_for_run(
    workflow_name: str,
    output_extensions: List[str],
    db_path: Path = _DB_PATH,
) -> List[Dict[str, Any]]:
    """
    Given the name of a completed workflow and its output file extensions,
    return matching bioc chain templates ranked by relevance.

    Matches on:
      - trigger_on_workflows: workflow_name substring match
      - trigger_on_output_extensions: any output extension match
    """
    candidates = []
    wf_lower = workflow_name.lower()
    ext_set = {e.lstrip(".").lower() for e in output_extensions}

    for tpl in BIOC_CHAIN_TEMPLATES:
        score = 0
        triggers_wf = [t.lower() for t in tpl.get("trigger_on_workflows", [])]
        triggers_ext = [e.lower() for e in tpl.get("trigger_on_output_extensions", [])]

        # Workflow name match (strong signal — mandatory for bioc chains)
        # tsv/csv are too common across all domains; require at least a
        # workflow-name match so mag/metabolomics/proteomics runs don't
        # falsely trigger a DESeq2 suggestion just from TSV output.
        if any(t in wf_lower or wf_lower in t for t in triggers_wf):
            score += 3

        # Output extension match (secondary boost only)
        if ext_set & set(triggers_ext):
            score += 2

        if score >= 3:  # require at least a workflow-name signal
            candidates.append({"score": score, "chain": tpl})

    candidates.sort(key=lambda x: -x["score"])
    return [c["chain"] for c in candidates]


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    n = register_bioc_chains()
    print(f"Registered {n} Bioconductor chain templates.")

    # Quick test
    matches = suggest_chains_for_run("nf-core/rnaseq", ["tsv", "bam"])
    print(f"Matches for rnaseq+tsv: {[m['name'] for m in matches]}")
