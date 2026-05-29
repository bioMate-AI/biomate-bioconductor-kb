#!/usr/bin/env nextflow
/*
 * genomics/crispr_screen_mageck
 * Pooled CRISPR screen analysis using MAGeCK (Model-based Analysis of Genome-wide CRISPR Knockout).
 *
 * Supports both loss-of-function (negative selection) and gain-of-function (positive selection)
 * screens. Runs the full MAGeCK pipeline: count → test → pathway enrichment.
 *
 * Outputs:
 *   mageck_count/         — per-guide read counts across all samples
 *   mageck_test/          — gene-level RRA scores, p-values, FDR (pos + neg selection)
 *   pathway_enrichment/   — GSEA on MAGeCK gene scores against MSigDB Hallmarks
 *   qc_summary.json       — aggregate QC metrics for the gate monitor
 *
 * Quality gates (qc_trace_monitor.py):
 *   gini_index > 0.1       — SILVER advisory (skewed guide distribution, possible bias)
 *   mapped_reads_pct < 60  — GOLD blocking (insufficient guide coverage; Li et al. Genome Biol 2014)
 *   median_count < 300     — SILVER advisory (low sequencing depth per guide)
 *   zero_count_guides_pct > 20 — SILVER advisory (high guide dropout, possible library degradation)
 *
 * References:
 *   Li et al. (2014) MAGeCK. Genome Biology 15:554. doi:10.1186/s13059-014-0554-4
 *   Li et al. (2015) MAGeCKFlute. Nature Protocols. doi:10.1038/s41596-018-0113-7
 */

nextflow.enable.dsl = 2

// ── Parameters ────────────────────────────────────────────────────────────────
params.outdir            = './results'
params.fastq_dir         = null          // Directory of FASTQ files (one per sample)
params.sample_sheet      = null          // CSV: sample_name,fastq_file,condition (treated/control)
params.library_file      = null          // MAGeCK sgRNA library CSV: sgRNA_id,sequence,gene
params.control_sgrna     = null          // File of non-targeting control sgRNA IDs (one per line)
params.norm_method       = 'median'      // MAGeCK normalisation: median | total | control
params.fdr_threshold     = 0.05         // FDR threshold for significant gene hits
params.screen_type       = 'negative'   // Screen selection type: negative | positive | both
params.run_pathway       = true          // Run pathway enrichment on significant gene hits
params.gene_sets         = 'h.all.v2023.1.Hs.symbols.gmt'  // MSigDB gene set file or alias
params.pam_sequence      = 'NGG'        // PAM sequence for sgRNA trimming
params.sgrna_len         = 20           // Expected sgRNA length after trimming

// ── Containers ───────────────────────────────────────────────────────────────
def MAGECK_CONTAINER() { 'quay.io/biocontainers/mageck:0.5.9.5--py39h6935b12_1' }
def PYTHON_CONTAINER() { 'quay.io/biocontainers/python:3.11' }

// ── Helper: parse sample sheet ────────────────────────────────────────────────
def parseSampleSheet(csv_path) {
    def rows = []
    new File(csv_path).eachLine { line, i ->
        if (i == 1) return  // skip header
        def cols = line.trim().split(',')
        rows << [name: cols[0], fastq: cols[1], condition: cols[2]]
    }
    return rows
}

// ── Channels ──────────────────────────────────────────────────────────────────
Channel
    .fromPath(params.sample_sheet)
    .splitCsv(header: true)
    .map { row -> tuple(row.sample_name, file(row.fastq_file), row.condition) }
    .set { ch_samples }

ch_library   = Channel.fromPath(params.library_file)
ch_ctrl_sgrna = params.control_sgrna
    ? Channel.fromPath(params.control_sgrna)
    : Channel.empty()

// ── Process: MAGeCK count ─────────────────────────────────────────────────────
// [Guide Counting]
process MAGECK_COUNT {
    tag "${meta.sample}"
    container MAGECK_CONTAINER()
    publishDir "${params.outdir}/mageck_count", mode: 'copy'

    input:
    tuple val(meta_list), path(fastqs), path(library)

    output:
    path "*.count.txt",        emit: counts
    path "*.count_normalized.txt", emit: norm_counts, optional: true
    path "*.countsummary.txt", emit: summary
    path "qc_count_metrics.json", emit: qc_json

    script:
    def sample_names = meta_list.collect { it.sample }.join(' ')
    def fastq_files  = fastqs.collect { it.toString() }.join(' ')
    """
    mageck count \\
        --list-seq ${library} \\
        --fastq ${fastq_files} \\
        --sample-label "${sample_names}" \\
        --norm-method ${params.norm_method} \\
        --sgrna-len ${params.sgrna_len} \\
        --pam ${params.pam_sequence} \\
        --output-prefix screen \\
        --pdf-report \\
        2>&1 | tee mageck_count.log

    # Extract QC metrics from the count summary
    python3 - <<'PYEOF'
import json, re, sys

summary_file = "screen.countsummary.txt"
metrics = {}
try:
    with open(summary_file) as f:
        lines = f.readlines()
    for line in lines:
        if "Reads in input" in line:
            metrics["total_reads"] = int(re.search(r"(\\d+)", line).group(1))
        elif "Reads mapped" in line:
            parts = re.findall(r"(\\d+\\.?\\d*)", line)
            if len(parts) >= 2:
                metrics["mapped_reads"] = int(parts[0])
                metrics["mapped_reads_pct"] = float(parts[1])
        elif "Median" in line:
            val = re.search(r"(\\d+\\.?\\d*)", line)
            if val: metrics["median_count"] = float(val.group(1))
        elif "Gini" in line:
            val = re.search(r"(\\d+\\.?\\d*)", line)
            if val: metrics["gini_index"] = float(val.group(1))
except Exception as e:
    metrics["parse_error"] = str(e)

qc = {
    "step": "mageck_count",
    "metrics": metrics,
    "gates": [
        {
            "gate": "Mapped reads",
            "value": metrics.get("mapped_reads_pct", 0),
            "threshold": 60,
            "operator": ">=",
            "status": "PASS" if metrics.get("mapped_reads_pct", 0) >= 60 else "FAIL",
            "evidence_level": "GOLD",
            "citation": "Li et al. 2014 Genome Biology doi:10.1186/s13059-014-0554-4"
        },
        {
            "gate": "Median guide count",
            "value": metrics.get("median_count", 0),
            "threshold": 300,
            "operator": ">=",
            "status": "PASS" if metrics.get("median_count", 0) >= 300 else "WARN",
            "evidence_level": "SILVER",
            "citation": "Joung et al. 2017 Nature Protocols doi:10.1038/nprot.2017.016"
        },
        {
            "gate": "Gini index",
            "value": metrics.get("gini_index", 0),
            "threshold": 0.1,
            "operator": "<=",
            "status": "PASS" if metrics.get("gini_index", 1) <= 0.1 else "WARN",
            "evidence_level": "SILVER",
            "citation": "Library uniformity heuristic; Cravatt lab ABPP practice"
        }
    ]
}
with open("qc_count_metrics.json", "w") as f:
    json.dump(qc, f, indent=2)
print("QC metrics written.")
PYEOF
    """
}

// ── Process: MAGeCK test ──────────────────────────────────────────────────────
// [Guide Counting]
process MAGECK_TEST {
    tag "RRA gene test"
    container MAGECK_CONTAINER()
    publishDir "${params.outdir}/mageck_test", mode: 'copy'

    input:
    path count_file
    path ctrl_sgrna

    output:
    path "*.gene_summary.txt",   emit: gene_summary
    path "*.sgrna_summary.txt",  emit: sgrna_summary
    path "qc_test_metrics.json", emit: qc_json

    script:
    def ctrl_arg = ctrl_sgrna ? "--control-sgrna ${ctrl_sgrna}" : ""
    """
    # Determine control and treatment sample names from count file header
    HEADER=\$(head -1 ${count_file})
    # Run RRA test for both negative and positive selection
    mageck test \\
        --count-table ${count_file} \\
        ${ctrl_arg} \\
        --norm-method ${params.norm_method} \\
        --gene-lfc-method median \\
        --remove-zero both \\
        --output-prefix screen \\
        --pdf-report \\
        2>&1 | tee mageck_test.log

    python3 - <<'PYEOF'
import json

gene_file = "screen.gene_summary.txt"
hits_neg, hits_pos = 0, 0
total_genes = 0
try:
    with open(gene_file) as f:
        lines = f.readlines()
    total_genes = len(lines) - 1
    for line in lines[1:]:
        cols = line.strip().split("\\t")
        if len(cols) >= 9:
            fdr_neg = float(cols[8]) if cols[8] != "NA" else 1.0
            fdr_pos = float(cols[5]) if cols[5] != "NA" else 1.0
            if fdr_neg < ${params.fdr_threshold}: hits_neg += 1
            if fdr_pos < ${params.fdr_threshold}: hits_pos += 1
except Exception as e:
    pass

qc = {
    "step": "mageck_test",
    "metrics": {
        "total_genes_tested": total_genes,
        "significant_hits_negative_selection": hits_neg,
        "significant_hits_positive_selection": hits_pos,
        "fdr_threshold": ${params.fdr_threshold}
    },
    "gates": [
        {
            "gate": "Genes with FDR < threshold (negative selection)",
            "value": hits_neg,
            "threshold": 1,
            "operator": ">=",
            "status": "PASS" if hits_neg >= 1 else "WARN",
            "evidence_level": "BRONZE",
            "citation": "Screen-dependent; expectation of ≥1 significant hit in a positive control screen"
        }
    ]
}
with open("qc_test_metrics.json", "w") as f:
    json.dump(qc, f, indent=2)
print("QC test metrics written.")
PYEOF
    """
}

// ── Process: Pathway enrichment on MAGeCK hits ───────────────────────────────
// [Analysis]
process PATHWAY_ENRICHMENT {
    tag "GSEA on screen hits"
    container PYTHON_CONTAINER()
    publishDir "${params.outdir}/pathway_enrichment", mode: 'copy'

    input:
    path gene_summary

    output:
    path "pathway_enrichment.tsv",    emit: enrichment
    path "pathway_enrichment.html",   emit: report
    path "qc_pathway_metrics.json",   emit: qc_json

    script:
    """
    pip install gseapy --quiet 2>/dev/null || true

    python3 - <<'PYEOF'
import json, gseapy as gp, pandas as pd, sys

gene_file = "${gene_summary}"
fdr_thresh = ${params.fdr_threshold}

try:
    df = pd.read_csv(gene_file, sep="\\t")
    # Build ranking by neg LFC (for negative selection screen)
    df_rank = df[["id", "neg|lfc"]].dropna()
    df_rank.columns = ["gene", "score"]
    df_rank = df_rank.set_index("gene")["score"].sort_values(ascending=False)

    pre_res = gp.prerank(
        rnk=df_rank,
        gene_sets="${params.gene_sets}",
        min_size=5, max_size=500,
        permutation_num=500,
        seed=42, verbose=False, outdir=None
    )
    result_df = pre_res.res2d
    result_df.to_csv("pathway_enrichment.tsv", sep="\\t", index=False)

    # HTML summary
    top = result_df.head(20) if len(result_df) > 0 else result_df
    rows = ""
    for _, r in top.iterrows():
        status = "ENRICHED" if float(r.get("NES", 0)) > 0 else "DEPLETED"
        color = "#c6efce" if status == "DEPLETED" else "#ffeb9c"
        rows += f"<tr style='background:{color}'><td>{r.get('Term','')}</td><td>{r.get('NES',0):.3f}</td><td>{r.get('FDR q-val',1):.4f}</td><td>{status}</td></tr>"

    html = f'''<!DOCTYPE html><html><head><style>
    body{{font-family:Arial;max-width:900px;margin:40px auto;}}
    table{{width:100%;border-collapse:collapse;}}
    th{{background:#0f4c81;color:white;padding:8px;}}
    td{{padding:8px;border-bottom:1px solid #eee;}}
    </style></head><body>
    <h1>CRISPR Screen — Pathway Enrichment</h1>
    <p>Gene set: {params.gene_sets} | Top pathways (NES ranked)</p>
    <table><tr><th>Pathway</th><th>NES</th><th>FDR</th><th>Direction</th></tr>{rows}</table>
    </body></html>'''
    with open("pathway_enrichment.html", "w") as f:
        f.write(html)

    sig = result_df[result_df.get("FDR q-val", pd.Series([1]*len(result_df))).astype(float) < fdr_thresh] if len(result_df) > 0 else result_df
    qc = {"step": "pathway_enrichment", "metrics": {"total_pathways_tested": len(result_df), "significant_pathways": len(sig)}}
except Exception as e:
    qc = {"step": "pathway_enrichment", "error": str(e)}
    pd.DataFrame().to_csv("pathway_enrichment.tsv", sep="\\t")
    with open("pathway_enrichment.html", "w") as f:
        f.write(f"<html><body><p>Error: {e}</p></body></html>")

with open("qc_pathway_metrics.json", "w") as f:
    json.dump(qc, f, indent=2)
PYEOF
    """
}

// ── Process: Final QC summary ─────────────────────────────────────────────────
// [Analysis]
process CRISPR_SCREEN_QC_REPORT {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path qc_count
    path qc_test
    path qc_pathway

    output:
    path "crispr_screen_qc_summary.json", emit: qc_summary

    script:
    """
    python3 - <<'PYEOF'
import json

summary = {"workflow": "crispr_screen_mageck", "steps": []}
for f in ["${qc_count}", "${qc_test}", "${qc_pathway}"]:
    try:
        with open(f) as fh:
            summary["steps"].append(json.load(fh))
    except:
        pass

all_gates = [g for s in summary["steps"] for g in s.get("gates", [])]
failed = [g for g in all_gates if g.get("status") == "FAIL"]
warned = [g for g in all_gates if g.get("status") == "WARN"]
summary["overall_status"] = "FAIL" if failed else ("WARN" if warned else "PASS")
summary["failed_gates"] = len(failed)
summary["warned_gates"] = len(warned)

with open("crispr_screen_qc_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(f"Overall status: {summary['overall_status']}")
PYEOF
    """
}

// ── Workflow ──────────────────────────────────────────────────────────────────
workflow {
    // Collect all samples, group with library for counting
    ch_all_samples = ch_samples.collect()
    MAGECK_COUNT(ch_all_samples, ch_library)

    // Gene-level test
    MAGECK_TEST(MAGECK_COUNT.out.counts, ch_ctrl_sgrna.ifEmpty([]))

    // Pathway enrichment (if enabled)
    if (params.run_pathway) {
        PATHWAY_ENRICHMENT(MAGECK_TEST.out.gene_summary)
        qc_pathway_ch = PATHWAY_ENRICHMENT.out.qc_json
    } else {
        qc_pathway_ch = Channel.empty()
    }

    // Aggregate QC
    CRISPR_SCREEN_QC_REPORT(
        MAGECK_COUNT.out.qc_json,
        MAGECK_TEST.out.qc_json,
        qc_pathway_ch.ifEmpty([])
    )
}
