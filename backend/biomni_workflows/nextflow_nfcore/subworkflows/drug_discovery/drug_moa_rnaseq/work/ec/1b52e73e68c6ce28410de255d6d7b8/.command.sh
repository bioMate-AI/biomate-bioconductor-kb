#!/bin/bash -ue
python3 << 'EOF'
import json
import csv
import math
from datetime import datetime

drug_name   = "Erlotinib"
target_gene = "EGFR"
mock_mode   = "false" == "true"

# -------------------------------------------------------------------------
# 1. Parse DE results
# -------------------------------------------------------------------------
de_genes  = []
sig_genes = []
with open("de_results.tsv") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        de_genes.append(row)
        try:
            if float(row["padj"]) < 0.05 and abs(float(row["log2FoldChange"])) > 1:
                sig_genes.append(row)
        except (ValueError, KeyError):
            pass

n_de_genes = len(sig_genes)

# -------------------------------------------------------------------------
# 2. Parse GSEA enrichment results
# -------------------------------------------------------------------------
pathways = []
with open("enrichment.tsv") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        try:
            pathways.append({
                "pathway":            row["pathway"],
                "NES":                float(row["NES"]),
                "padj":               float(row["padj"]),
                "leading_edge_genes": row.get("leading_edge_genes", ""),
            })
        except (ValueError, KeyError):
            pass

pathways.sort(key=lambda p: abs(p["NES"]), reverse=True)
top_pathways = pathways[:5]

# -------------------------------------------------------------------------
# 3. Parse CMap results
# -------------------------------------------------------------------------
cmap_data    = json.load(open("cmap_matches.json"))
cmap_matches = cmap_data.get("matches", [])
cmap_top     = (
    cmap_matches[0]
    if cmap_matches
    else {"drug_name": "N/A", "similarity_score": 0.0, "moa_annotation": "N/A"}
)

# -------------------------------------------------------------------------
# 4. QC status
# -------------------------------------------------------------------------
if n_de_genes >= 10:
    qc_status = "PASS"
elif n_de_genes >= 5:
    qc_status = "WARN"
else:
    qc_status = "FAIL"

# -------------------------------------------------------------------------
# 5. MoA hypothesis
# -------------------------------------------------------------------------
top_pw_name = top_pathways[0]["pathway"] if top_pathways else "unknown pathway"
top_nes     = top_pathways[0]["NES"]     if top_pathways else 0.0
cmap_drug   = cmap_top.get("drug_name", "N/A")
cmap_sim    = cmap_top.get("similarity_score", 0.0)
direction   = "activation" if top_nes > 0 else "suppression"

moa_hypothesis = (
    f"Treatment with {drug_name} induces {direction} of the {top_pw_name} pathway "
    f"(NES={top_nes:.2f}), consistent with {cmap_drug} "
    f"(CMap similarity={cmap_sim:.2f}), supporting {target_gene} engagement."
)

# -------------------------------------------------------------------------
# 6. Write moa_summary.json
# -------------------------------------------------------------------------
summary = {
    "drug_name":    drug_name,
    "target_gene":  target_gene,
    "n_de_genes":   n_de_genes,
    "qc_status":    qc_status,
    "top_pathways": [
        {"name": p["pathway"], "NES": p["NES"], "padj": p["padj"]}
        for p in top_pathways
    ],
    "cmap_top_match": {
        "drug_name":      cmap_top.get("drug_name", "N/A"),
        "similarity":     cmap_top.get("similarity_score", 0.0),
        "moa_annotation": cmap_top.get("moa_annotation", "N/A"),
    },
    "moa_hypothesis": moa_hypothesis,
    "mock_mode":    mock_mode,
    "timestamp":    datetime.utcnow().isoformat() + "Z",
}
with open("moa_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

# -------------------------------------------------------------------------
# 7. Build HTML report
# -------------------------------------------------------------------------
qc_color = {"PASS": "#28a745", "WARN": "#ffc107", "FAIL": "#dc3545"}.get(qc_status, "#6c757d")

# Top-20 DE gene rows
top_de = sorted(de_genes, key=lambda r: float(r.get("padj", 1)))[:20]
de_rows_html = ""
for r in top_de:
    try:
        padj   = float(r.get("padj", 1))
        log2fc = float(r.get("log2FoldChange", 0))
        sig    = " &#9733;" if padj < 0.05 and abs(log2fc) > 1 else ""
        fc_col = "#c0392b" if log2fc > 0 else "#2980b9"
        de_rows_html += (
            f"<tr><td>{r['gene_name']}</td>"
            f"<td style='color:{fc_col};text-align:right'>{log2fc:.3f}</td>"
            f"<td style='text-align:right'>{padj:.2e}</td>"
            f"<td style='text-align:right'>{r.get('baseMean', 'N/A')}</td>"
            f"<td>{sig}</td></tr>\n"
        )
    except (ValueError, KeyError):
        pass

# Top-10 pathway rows
pw_rows_html = ""
for p in pathways[:10]:
    nes_col = "#c0392b" if p["NES"] > 0 else "#2980b9"
    edge    = p["leading_edge_genes"][:60] + "..." if len(p["leading_edge_genes"]) > 60 else p["leading_edge_genes"]
    pw_rows_html += (
        f"<tr><td>{p['pathway']}</td>"
        f"<td style='color:{nes_col};text-align:right'>{p['NES']:.3f}</td>"
        f"<td style='text-align:right'>{p['padj']:.4f}</td>"
        f"<td style='font-size:0.82em'>{edge}</td></tr>\n"
    )

# CMap match rows
cmap_rows_html = ""
for m in cmap_matches:
    sim     = m.get("similarity_score", 0)
    sim_col = "#28a745" if sim >= 0.8 else ("#ffc107" if sim >= 0.6 else "#dc3545")
    cmap_rows_html += (
        f"<tr><td><b>{m['drug_name']}</b></td>"
        f"<td>{m.get('target', 'N/A')}</td>"
        f"<td style='color:{sim_col};text-align:right'>{sim:.3f}</td>"
        f"<td>{m.get('moa_annotation', 'N/A')}</td>"
        f"<td>{m.get('cell_line', 'N/A')}</td></tr>\n"
    )

gen_ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Drug MoA Report &mdash; {drug_name}</title>
<style>
  body {{font-family: Arial, sans-serif; max-width: 1100px; margin: 0 auto; padding: 20px; color: #333;}}
  h1   {{color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 8px;}}
  h2   {{color: #34495e; margin-top: 32px;}}
  .info-grid {{display: grid; grid-template-columns: 1fr 1fr; gap: 8px;
               background: #f8f9fa; padding: 14px 18px; border-radius: 6px; margin-bottom: 18px;}}
  .info-item {{padding: 3px 0;}}
  .info-label {{font-weight: bold; color: #555;}}
  .qc-box {{padding: 14px 20px; border-radius: 8px; color: white; font-size: 1.15em;
             font-weight: bold; margin: 18px 0; background: {qc_color};}}
  .hypothesis-box {{background: #eaf3fb; border-left: 5px solid #3498db;
                    padding: 14px 20px; border-radius: 0 6px 6px 0; margin: 18px 0;
                    font-style: italic; line-height: 1.6;}}
  table {{border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 0.93em;}}
  th    {{background: #2c3e50; color: white; padding: 8px 12px; text-align: left;}}
  td    {{padding: 6px 12px; border-bottom: 1px solid #dde;}}
  tr:nth-child(even) {{background: #f9f9fb;}}
  tr:hover {{background: #ebf5fb;}}
  .footer {{color: #aaa; font-size: 0.83em; margin-top: 40px;
             border-top: 1px solid #eee; padding-top: 10px;}}
</style>
</head>
<body>
<h1>&#127995; Drug Mechanism-of-Action Report</h1>

<div class="info-grid">
  <div class="info-item"><span class="info-label">Drug:</span> {drug_name}</div>
  <div class="info-item"><span class="info-label">Target Gene:</span> {target_gene}</div>
  <div class="info-item"><span class="info-label">Significant DE genes:</span> {n_de_genes}</div>
  <div class="info-item"><span class="info-label">Enriched pathways:</span> {len(pathways)}</div>
  <div class="info-item"><span class="info-label">Generated:</span> {gen_ts}</div>
  <div class="info-item"><span class="info-label">Top CMap match:</span> {cmap_drug} (sim={cmap_sim:.2f})</div>
</div>

<div class="qc-box">QC Status: {qc_status} &mdash; {n_de_genes} significant DE genes detected</div>

<h2>&#128161; MoA Hypothesis</h2>
<div class="hypothesis-box">{moa_hypothesis}</div>

<h2>&#128202; Top 20 Differentially Expressed Genes</h2>
<table>
  <tr><th>Gene</th><th>log2FC</th><th>padj</th><th>baseMean</th><th>Sig</th></tr>
  {de_rows_html}
</table>

<h2>&#127774; Top 10 Enriched Pathways (MSigDB Hallmark)</h2>
<table>
  <tr><th>Pathway</th><th>NES</th><th>padj</th><th>Leading Edge (truncated)</th></tr>
  {pw_rows_html}
</table>

<h2>&#128279; LINCS CMap Drug Similarity Matches</h2>
<table>
  <tr><th>Drug</th><th>Target</th><th>Similarity</th><th>MoA Annotation</th><th>Cell Line</th></tr>
  {cmap_rows_html}
</table>

<div class="footer">
  BioMate Drug MoA Pipeline &mdash; Gap 9 Drug Discovery Analysis &mdash;
  Generated {datetime.utcnow().isoformat()}Z
</div>
</body>
</html>'''

with open("moa_report.html", "w") as f:
    f.write(html)

print(f"MoA Report complete for {drug_name} / {target_gene}")
print(f"  QC status:   {qc_status}  ({n_de_genes} significant DE genes)")
print(f"  Top pathway: {top_pw_name}  NES={top_nes:.2f}")
print(f"  CMap top:    {cmap_drug}  similarity={cmap_sim:.2f}")
print(f"  Hypothesis:  {moa_hypothesis}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "DRUG_MOA_RNASEQ:MOA_REPORT":
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
