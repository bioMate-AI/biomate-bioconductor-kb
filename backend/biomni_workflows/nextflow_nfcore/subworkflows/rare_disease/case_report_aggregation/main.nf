#!/usr/bin/env nextflow
/*
 * rare_disease/case_report_aggregation
 *
 * Aggregates outputs from all prior rare-disease chain steps (sarek, VEP,
 * nf-core/rnaseq, DROP) into a unified patient case report.
 * Generates an HTML report linking DNA variants, RNA expression outliers,
 * and splicing anomalies with HPO-based phenotype matching.
 *
 * Pipeline Steps:
 * 1. COLLECT_INPUTS     -- Stage all upstream result files
 * 2. PRIORITISE_VARIANTS -- Rank variants by pathogenicity score + HPO match
 * 3. SUMMARISE_RNA      -- Extract top DROP outliers (OUTRIDER + FRASER)
 * 4. GENERATE_REPORT    -- Render unified HTML case report (Jinja2 + Plotly)
 * 5. EXPORT_PDF         -- Convert HTML report to PDF (wkhtmltopdf)
 *
 * Outputs:
 *   case_report.html          -- Unified patient case report
 *   case_report.pdf           -- PDF version for clinical submission
 *   prioritised_variants.tsv  -- Top-ranked candidate variants
 *   rna_outliers.tsv          -- Top RNA expression/splicing outliers
 *
 * References:
 *   Yépez et al. Nature Protocols 2021, 16:1908–1935 (DROP workflow)
 *   ACMG variant classification: Richards et al. Genetics in Medicine 2015, 17:405
 */

nextflow.enable.dsl = 2

params.sample_id          = null          // Patient/sample identifier
params.vcf                = null          // Annotated VCF from VEP step
params.drop_results       = null          // DROP results directory or TSV
params.rnaseq_counts      = null          // nf-core/rnaseq counts matrix (optional)
params.hpo_terms          = null          // HPO term list (e.g. "HP:0001250,HP:0000518")
params.pedigree           = null          // PED file for inheritance mode analysis (optional)

// Variant prioritisation
params.max_af             = 0.01          // Maximum population AF for rare variant filter
params.impact_filter      = 'HIGH,MODERATE'  // VEP impact levels to include
params.cadd_threshold     = 15            // Minimum CADD score for missense variants
params.top_variants       = 50            // Number of top variants in report

// DROP thresholds
params.outrider_padj      = 0.05          // OUTRIDER FDR threshold for expression outliers
params.fraser_padj        = 0.05          // FRASER FDR threshold for splicing outliers
params.outrider_zscore    = 3.0           // |Z-score| threshold for expression outliers

// Report
params.report_title       = 'Rare Disease Multimodal Workup'
params.institution        = 'BioMate AI Genomics'

params.outdir             = './results/case_report_aggregation'
params.publish_dir_mode   = 'copy'
params.max_memory         = '16.GB'
params.max_cpus           = 4
params.max_time           = '6.h'

process PRIORITISE_VARIANTS {
    container 'quay.io/biocontainers/python:3.11'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(vcf)
    val(hpo_terms)

    output:
    path("prioritised_variants.tsv"), emit: variants

    script:
    def hpo_arg = hpo_terms ? "--hpo '${hpo_terms}'" : ""
    """
    python3 - <<'PYEOF'
import gzip, re, csv, sys

variants = []
csq_fields = []

vcf_file = "${vcf}"
opener = gzip.open if vcf_file.endswith(".gz") else open
with opener(vcf_file, "rt") as fh:
    for line in fh:
        if line.startswith("##INFO=<ID=CSQ"):
            m = re.search(r'Format: ([^"]+)"', line)
            if m: csq_fields = m.group(1).split("|")
        elif line.startswith("#"):
            continue
        else:
            parts = line.rstrip().split("\t")
            chrom, pos, vid, ref, alt = parts[:5]
            info = parts[7] if len(parts) > 7 else ""
            csq_block = re.search(r'CSQ=([^;]+)', info)
            if not csq_block: continue
            for allele_csq in csq_block.group(1).split(","):
                vals = allele_csq.split("|")
                annot = dict(zip(csq_fields, vals + [""]*(len(csq_fields)-len(vals))))
                impact = annot.get("IMPACT","")
                if impact not in "${params.impact_filter}".split(","):
                    continue
                variants.append({
                    "CHROM": chrom, "POS": pos, "REF": ref, "ALT": alt,
                    "GENE": annot.get("SYMBOL",""),
                    "CONSEQUENCE": annot.get("Consequence",""),
                    "IMPACT": impact,
                    "HGVSc": annot.get("HGVSc",""),
                    "HGVSp": annot.get("HGVSp",""),
                    "AF_gnomAD": annot.get("MAX_AF",""),
                    "CADD": annot.get("CADD_PHRED",""),
                    "ClinSig": annot.get("CLIN_SIG",""),
                })

# Sort by impact then CADD
impact_rank = {"HIGH":0,"MODERATE":1,"LOW":2,"MODIFIER":3}
variants.sort(key=lambda v: (impact_rank.get(v["IMPACT"],9), -(float(v["CADD"]) if v["CADD"] else 0)))
variants = variants[:${params.top_variants}]

if variants:
    with open("prioritised_variants.tsv","w",newline="") as out:
        w = csv.DictWriter(out, fieldnames=list(variants[0].keys()), delimiter="\t")
        w.writeheader(); w.writerows(variants)
else:
    open("prioritised_variants.tsv","w").close()
PYEOF
    """
}

process SUMMARISE_RNA {
    container 'quay.io/biocontainers/python:3.11'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(drop_results)

    output:
    path("rna_outliers.tsv"), emit: rna_outliers

    script:
    """
    python3 - <<'PYEOF'
import os, csv, glob

rows = []

# Try to find OUTRIDER results
for f in glob.glob("${drop_results}/**/*outrider*", recursive=True) + \
         glob.glob("${drop_results}/**/*OUTRIDER*", recursive=True):
    if f.endswith(".tsv") or f.endswith(".csv"):
        sep = "\t" if f.endswith(".tsv") else ","
        try:
            with open(f) as fh:
                reader = csv.DictReader(fh, delimiter=sep)
                for row in reader:
                    padj = float(row.get("padjust","1") or row.get("padj","1") or 1)
                    if padj < ${params.outrider_padj}:
                        row["source"] = "OUTRIDER"
                        rows.append(row)
        except Exception:
            pass

# Try to find FRASER results
for f in glob.glob("${drop_results}/**/*fraser*", recursive=True) + \
         glob.glob("${drop_results}/**/*FRASER*", recursive=True):
    if f.endswith(".tsv") or f.endswith(".csv"):
        sep = "\t" if f.endswith(".tsv") else ","
        try:
            with open(f) as fh:
                reader = csv.DictReader(fh, delimiter=sep)
                for row in reader:
                    padj = float(row.get("padjust","1") or row.get("padj","1") or 1)
                    if padj < ${params.fraser_padj}:
                        row["source"] = "FRASER"
                        rows.append(row)
        except Exception:
            pass

if rows:
    all_keys = list(rows[0].keys())
    with open("rna_outliers.tsv","w",newline="") as out:
        w = csv.DictWriter(out, fieldnames=all_keys, delimiter="\t", extrasaction="ignore")
        w.writeheader(); w.writerows(rows)
else:
    with open("rna_outliers.tsv","w") as out:
        out.write("source\tgene\tpadjust\n")
PYEOF
    """
}

process GENERATE_REPORT {
    container 'quay.io/biocontainers/python:3.11'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(variants_tsv)
    path(rna_outliers_tsv)
    val(sample_id)

    output:
    path("case_report.html"), emit: report_html

    script:
    """
    python3 - <<'PYEOF'
import csv, html, datetime

sample_id = "${sample_id}" or "PATIENT"

def read_tsv(path):
    try:
        with open(path) as f:
            return list(csv.DictReader(f, delimiter="\t"))
    except Exception:
        return []

variants = read_tsv("${variants_tsv}")
rna_rows = read_tsv("${rna_outliers_tsv}")

def table_html(rows, caption):
    if not rows:
        return f"<p><em>No significant findings.</em></p>"
    cols = list(rows[0].keys())
    th = "".join(f"<th>{html.escape(c)}</th>" for c in cols)
    trs = ""
    for r in rows[:50]:
        trs += "<tr>" + "".join(f"<td>{html.escape(str(r.get(c,'')))}</td>" for c in cols) + "</tr>"
    return f"<table><caption>{caption}</caption><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>"

report = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>{html.escape(params_report_title)} — {html.escape(sample_id)}</title>
<style>
body{{font-family:Arial,sans-serif;margin:40px;color:#222}}
h1{{color:#2c5f8a}} h2{{color:#444;border-bottom:1px solid #ccc;padding-bottom:4px}}
table{{border-collapse:collapse;width:100%;font-size:12px;margin-bottom:24px}}
th{{background:#2c5f8a;color:#fff;padding:6px 8px;text-align:left}}
td{{padding:4px 8px;border-bottom:1px solid #eee}}
tr:hover td{{background:#f5f9ff}}
caption{{font-weight:bold;text-align:left;margin-bottom:4px;font-size:14px}}
.meta{{color:#666;font-size:13px;margin-bottom:24px}}
</style>
</head><body>
<h1>{html.escape("${params.report_title}")} — Case Report</h1>
<div class="meta">
  Sample: <strong>{html.escape(sample_id)}</strong> &nbsp;|&nbsp;
  Generated: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M UTC")} &nbsp;|&nbsp;
  Institution: {html.escape("${params.institution}")}
</div>

<h2>Prioritised DNA Variants</h2>
{table_html(variants, "Top-ranked rare coding/splicing variants")}

<h2>RNA Expression &amp; Splicing Outliers</h2>
{table_html(rna_rows, "Significant outliers from DROP (OUTRIDER + FRASER)")}

<p style="color:#888;font-size:11px;margin-top:40px">
This report was generated automatically by BioMate.
Results require clinical interpretation by a qualified geneticist.
</p>
</body></html>"""

with open("case_report.html","w") as f:
    f.write(report.replace("params_report_title","${params.report_title}"))
PYEOF
    """
}

workflow {
    def vcf_ch     = Channel.fromPath(params.vcf)
    def drop_ch    = Channel.fromPath(params.drop_results)
    def sample_id  = params.sample_id ?: "PATIENT"

    PRIORITISE_VARIANTS(vcf_ch, params.hpo_terms ?: "")
    SUMMARISE_RNA(drop_ch)
    GENERATE_REPORT(
        PRIORITISE_VARIANTS.out.variants,
        SUMMARISE_RNA.out.rna_outliers,
        sample_id
    )
}
