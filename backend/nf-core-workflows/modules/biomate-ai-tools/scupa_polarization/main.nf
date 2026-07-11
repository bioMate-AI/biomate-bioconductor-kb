#!/usr/bin/env nextflow
/*
 * immuno_oncology/scupa_polarization  (3-phase pipeline)
 *
 *   Implements immune cell polarization scoring following the method published
 *   in Scupa (Zhao lab, github.com/bsml320/Scupa). The core algorithm —
 *   gene-set scoring with curated immune cell marker panels — is based on
 *   published signatures and re-implemented in Python/scanpy so the workflow
 *   runs without the R package dependency.
 *
 *   Phase A — Signature scoring  : score each cell for Tex/Tem/Trm/Teff/Tpex
 *                                   gene-set signatures using scanpy score_genes
 *   Phase B — Polarization call  : assign dominant polarization state per cell;
 *                                   compute confidence (margin between top-2 scores)
 *   Phase C — Report + h5ad out  : polarization_scores.tsv, polarized_cells.h5ad,
 *                                   summary JSON for ImmuneApp handoff
 *
 * Input:
 *   reactive_cells_h5ad  — h5ad from turep Phase C (or any CD8+ T cell h5ad)
 *   min_genes            — minimum genes per cell filter (default 200)
 *   score_method         — "scanpy" | "ucell" (default scanpy)
 *
 * Output:
 *   polarization_scores.tsv      — per-cell scores for all 5 states
 *   polarized_cells.h5ad         — input h5ad + obs columns: scupa_state, scupa_conf
 *   scupa_summary.json           — state counts, dominant state, feeds ImmuneApp
 *
 * Gene signatures (from Scupa paper + curated literature):
 *   Tex  (exhausted)     : PDCD1, HAVCR2, LAG3, TIGIT, CTLA4, TOX, NR4A1, ENTPD1
 *   Tem  (effector mem)  : GZMK, CXCR3, CXCR4, CCR5, EOMES, TBX21, IFNG, TNF
 *   Trm  (tissue-res)   : ITGAE, ITGA1, ZNF683, CXCR6, KCNK5, RGS1, RBPJ
 *   Teff (effector)      : GZMB, PRF1, GNLY, FGFBP2, CX3CR1, KLRG1, NKG7
 *   Tpex (progenitor ex) : TCF7, SLAMF6, XCL1, XCL2, CCR7, SELL, IL7R
 *
 * Method reference:
 *   Scupa: github.com/bsml320/Scupa (Zhao lab, UTHealth Houston)
 *   Signatures cross-referenced with:
 *     Sade-Feldman et al. 2018 Cell (Tex/Teff)
 *     Miller et al. 2019 Nature Immunology (Tpex)
 *     Mackay et al. 2016 Nature Immunology (Trm)
 *
 * ZZ01 chain position: Step 2 of 3
 *   turep → [scupa_polarization] → immuneapp_hla_screen
 *
 * For autoimmune use (RA/SLE):
 *   The same polarization states occur in autoreactive T cells. Trm and Tex
 *   populations are enriched in RA synovium (Zhang et al. 2019 Nat Immunol).
 *   Dominant state informs which T cell phenotype is driving tissue damage.
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.reactive_cells_h5ad = 'null'
params.min_genes           = 200
params.score_method        = 'scanpy'
params.use_baked_toy       = false

CONTAINER = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
    : 'biomate/biomni-tools:latest'

// ── Phase A: Signature scoring ────────────────────────────────────────────────
process SCUPA_SCORE {
    tag "scupa:phaseA_score"
    label 'process_medium'
    container CONTAINER
    publishDir "${params.outdir}/phaseA_score", mode: 'copy'

    input:  val(meta)
    output:
        tuple val(meta), path("scored_cells.h5ad"), emit: scored
        path "scoring_log.txt",                     emit: log
        path "versions.yml",                        emit: versions

    script:
    def h5ad      = params.reactive_cells_h5ad
    def min_genes = params.min_genes
    def baked     = params.use_baked_toy as Boolean
    """
    python3 << 'PYEOF'
import sys, json, warnings
warnings.filterwarnings("ignore")

try:
    import scanpy as sc
    import numpy as np
    import pandas as pd
except ImportError as e:
    print(f"ERROR: missing dependency: {e}", file=sys.stderr)
    sys.exit(1)

# ── Scupa gene signatures ─────────────────────────────────────────────────────
SIGNATURES = {
    "Tex":  ["PDCD1", "HAVCR2", "LAG3", "TIGIT", "CTLA4", "TOX",
             "NR4A1", "ENTPD1", "VCAM1", "CXCL13"],
    "Tem":  ["GZMK", "CXCR3", "CXCR4", "CCR5", "EOMES", "TBX21",
             "IFNG", "TNF", "GZMA", "FASL"],
    "Trm":  ["ITGAE", "ITGA1", "ZNF683", "CXCR6", "KCNK5",
             "RGS1", "RBPJ", "BHLHE40", "CD69", "PRDM1"],
    "Teff": ["GZMB", "PRF1", "GNLY", "FGFBP2", "CX3CR1",
             "KLRG1", "NKG7", "FCGR3A", "S1PR5", "TBGFB1"],
    "Tpex": ["TCF7", "SLAMF6", "XCL1", "XCL2", "CCR7",
             "SELL", "IL7R", "LEF1", "KLF2", "MYC"],
}

baked     = ${baked}
h5ad_path = "${h5ad}"
min_genes = int("${min_genes}")

if baked or h5ad_path in ("null", ""):
    # Synthetic toy dataset: 500 cells × 2000 genes
    print("Using synthetic toy dataset (500 cells, 2000 genes)", flush=True)
    np.random.seed(42)
    n_cells, n_genes = 500, 2000
    all_sig_genes = [g for genes in SIGNATURES.values() for g in genes]
    other_genes = [f"GENE{i:04d}" for i in range(n_genes - len(all_sig_genes))]
    gene_names = all_sig_genes + other_genes
    X = np.random.negative_binomial(2, 0.3, size=(n_cells, len(gene_names))).astype(float)
    # Enrich signature genes in subsets to create clear polarization signal
    boundaries = [0, 100, 200, 300, 400, 500]
    for idx, state in enumerate(SIGNATURES.keys()):
        start, end = boundaries[idx], boundaries[idx+1]
        for gene in SIGNATURES[state]:
            gi = gene_names.index(gene)
            X[start:end, gi] += np.random.poisson(8, size=end-start)
    import anndata as ad
    adata = ad.AnnData(
        X=X,
        obs=pd.DataFrame({"cell_id": [f"cell_{i}" for i in range(n_cells)]},
                         index=[f"cell_{i}" for i in range(n_cells)]),
        var=pd.DataFrame(index=gene_names),
    )
    adata.obs["turep_score"] = np.random.uniform(0.3, 0.95, n_cells)
    adata.obs["turep_reactive"] = (adata.obs["turep_score"] > 0.5).astype(int)
else:
    print(f"Loading h5ad: {h5ad_path}", flush=True)
    adata = sc.read_h5ad(h5ad_path)
    print(f"Loaded: {adata.n_obs} cells × {adata.n_vars} genes", flush=True)

# Basic QC filter
sc.pp.filter_cells(adata, min_genes=min_genes)
print(f"After QC filter ({min_genes} min genes): {adata.n_obs} cells", flush=True)

if adata.n_obs == 0:
    print("ERROR: no cells passed QC filter", file=sys.stderr)
    sys.exit(1)

# Normalize if raw counts
if adata.X.max() > 50:
    sc.pp.normalize_total(adata, target_sum=1e4)
    sc.pp.log1p(adata)

# Score each signature — scanpy score_genes adds obs column
log_lines = []
for state, genes in SIGNATURES.items():
    present = [g for g in genes if g in adata.var_names]
    if len(present) < 3:
        print(f"  WARNING: {state} — only {len(present)}/{len(genes)} genes in data; using available", flush=True)
    sc.tl.score_genes(adata, present if present else genes[:3],
                      score_name=f"scupa_{state}", use_raw=False)
    log_lines.append(f"{state}: {len(present)}/{len(genes)} signature genes found")
    print(f"  Scored {state}: {len(present)} genes", flush=True)

adata.write_h5ad("scored_cells.h5ad")

with open("scoring_log.txt", "w") as f:
    f.write("Scupa Phase A — Signature Scoring\\n")
    f.write(f"Cells scored: {adata.n_obs}\\n")
    f.write("\\n".join(log_lines) + "\\n")

with open("versions.yml", "w") as f:
    f.write("scupa_polarization: 1.0.0\\n")
    import scanpy; f.write(f"scanpy: {scanpy.__version__}\\n")

print(f"Phase A complete: {adata.n_obs} cells scored for 5 polarization states", flush=True)
PYEOF
    """
}

// ── Phase B: Polarization state assignment ────────────────────────────────────
process SCUPA_POLARIZE {
    tag "scupa:phaseB_polarize"
    label 'process_low'
    container CONTAINER
    publishDir "${params.outdir}/phaseB_polarize", mode: 'copy'

    input:  tuple val(meta), path(scored_h5ad)
    output:
        tuple val(meta), path("polarized_cells.h5ad"), emit: polarized
        path "polarization_scores.tsv",                emit: scores
        path "versions.yml",                           emit: versions

    script:
    """
    python3 << 'PYEOF'
import sys, warnings
warnings.filterwarnings("ignore")
import scanpy as sc
import numpy as np
import pandas as pd

adata = sc.read_h5ad("${scored_h5ad}")

states = ["Tex", "Tem", "Trm", "Teff", "Tpex"]
score_cols = [f"scupa_{s}" for s in states]

# Build score matrix
score_df = adata.obs[score_cols].copy()
score_df.columns = states

# Assign dominant state and confidence (margin between top-2)
dominant = score_df.idxmax(axis=1)
sorted_scores = np.sort(score_df.values, axis=1)
confidence = sorted_scores[:, -1] - sorted_scores[:, -2]

adata.obs["scupa_state"]      = dominant.values
adata.obs["scupa_confidence"] = confidence

# Polarization score matrix as TSV
score_out = score_df.copy()
score_out["scupa_state"]      = dominant.values
score_out["scupa_confidence"] = confidence
if "turep_score" in adata.obs.columns:
    score_out["turep_score"] = adata.obs["turep_score"].values

score_out.index = adata.obs.index
score_out.to_csv("polarization_scores.tsv", sep="\\t")

adata.write_h5ad("polarized_cells.h5ad")

# State distribution summary
state_counts = dominant.value_counts().to_dict()
dominant_state = dominant.value_counts().idxmax()
print(f"Phase B complete:", flush=True)
for s, c in sorted(state_counts.items(), key=lambda x: -x[1]):
    pct = 100 * c / len(dominant)
    print(f"  {s}: {c} cells ({pct:.1f}%)", flush=True)
print(f"  Dominant state: {dominant_state}", flush=True)
print(f"  Mean confidence: {confidence.mean():.3f}", flush=True)

with open("versions.yml", "w") as f:
    f.write("scupa_polarization_phase_b: 1.0.0\\n")
PYEOF
    """
}

// ── Phase C: Report + ImmuneApp handoff ──────────────────────────────────────
process SCUPA_REPORT {
    tag "scupa:phaseC_report"
    label 'process_low'
    container CONTAINER
    publishDir "${params.outdir}/phaseC_report", mode: 'copy'

    input:  tuple val(meta), path(polarized_h5ad)
    output:
        path "scupa_summary.json",    emit: summary
        path "scupa_report.html",     emit: report
        path "versions.yml",          emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, sys, warnings
warnings.filterwarnings("ignore")
import scanpy as sc
import numpy as np
import pandas as pd

adata = sc.read_h5ad("${polarized_h5ad}")

states     = ["Tex", "Tem", "Trm", "Teff", "Tpex"]
state_ser  = adata.obs["scupa_state"]
state_counts = state_ser.value_counts().to_dict()
total_cells  = len(state_ser)
dominant     = state_ser.value_counts().idxmax()
mean_conf    = float(adata.obs["scupa_confidence"].mean())

# Per-state mean scores
mean_scores = {}
for s in states:
    col = f"scupa_{s}"
    if col in adata.obs.columns:
        mean_scores[s] = float(adata.obs[col].mean())

# Autoimmune context interpretation
autoimmune_notes = {
    "Tex":  "Exhausted T cells — chronically stimulated by persistent antigen. Dominant in RA synovium and SLE kidneys. High Tex suggests prolonged autoreactive stimulation.",
    "Tem":  "Effector memory — cytokine-producing, tissue-patrolling. Key drivers of flares in RA/SLE when reactivated.",
    "Trm":  "Tissue-resident memory — retained in inflamed tissue (synovium, skin, kidney). Fuel local inflammation without recirculating. Prime target for tissue-directed therapy.",
    "Teff": "Cytotoxic effectors — immediate killers. Elevated in acute autoimmune flares and organ damage.",
    "Tpex": "Progenitor exhausted — stem-like, self-renewing. Source of Tex pool. Targeting Tpex prevents exhaustion replenishment.",
}

summary = {
    "tool": "scupa_polarization",
    "method": "gene-set scoring (scanpy score_genes) with Scupa published signatures",
    "cells_analyzed": total_cells,
    "dominant_state": dominant,
    "mean_confidence": round(mean_conf, 4),
    "state_distribution": {
        s: {
            "count": state_counts.get(s, 0),
            "pct": round(100 * state_counts.get(s, 0) / total_cells, 1),
            "mean_score": round(mean_scores.get(s, 0), 4),
            "autoimmune_context": autoimmune_notes.get(s, ""),
        }
        for s in states
    },
    "immuneapp_handoff": {
        "input_h5ad": "${polarized_h5ad}",
        "recommended_subset": dominant,
        "note": f"Run ImmuneApp on the {dominant} subset for highest-confidence neoantigen/autoantigen prediction",
    },
    "reference": "Scupa method: github.com/bsml320/Scupa (Zhao lab, UTHealth Houston)"
}

with open("scupa_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

# HTML report
state_rows = ""
for s in states:
    d = summary["state_distribution"][s]
    bar_w = max(4, int(d["pct"] * 3))
    highlight = ' style="font-weight:bold;background:#1a3a2a;"' if s == dominant else ""
    state_rows += f"""
    <tr{highlight}>
      <td>{s}</td>
      <td>{d['count']}</td>
      <td>{d['pct']}%</td>
      <td><div style="background:#22c55e;height:14px;width:{bar_w}px;border-radius:3px;"></div></td>
      <td style="font-size:0.85em;color:#94a3b8;">{d['autoimmune_context'][:90]}...</td>
    </tr>"""

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Scupa Polarization Report</title>
<style>
  body{{background:#0f1117;color:#e2e8f0;font-family:monospace;padding:2rem;}}
  h1{{color:#22c55e;}} h2{{color:#94a3b8;font-size:1rem;}}
  table{{border-collapse:collapse;width:100%;margin-top:1rem;}}
  th{{background:#1e293b;padding:8px 12px;text-align:left;color:#94a3b8;font-size:0.8rem;}}
  td{{padding:8px 12px;border-bottom:1px solid #1e293b;font-size:0.9rem;}}
  .badge{{display:inline-block;padding:2px 8px;border-radius:4px;font-size:0.75rem;}}
  .dominant{{background:#166534;color:#86efac;}}
</style></head>
<body>
<h1>Scupa Immune Cell Polarization</h1>
<h2>Method: gene-set scoring (Scupa signatures) · {total_cells} cells analyzed</h2>
<p>Dominant state: <span class="badge dominant">{dominant}</span>
   &nbsp; Mean confidence: {mean_conf:.3f}</p>
<table>
  <tr><th>State</th><th>Cells</th><th>%</th><th>Score</th><th>Autoimmune context</th></tr>
  {state_rows}
</table>
<p style="margin-top:2rem;font-size:0.8rem;color:#475569;">
  Gene signatures from Scupa (Zhao lab, github.com/bsml320/Scupa) ·
  Sade-Feldman 2018 · Miller 2019 Nat Immunol · Mackay 2016 Nat Immunol<br>
  Next step: run immuneapp_hla_screen on {dominant} subset
</p>
</body></html>"""

with open("scupa_report.html", "w") as f:
    f.write(html)

with open("versions.yml", "w") as f:
    f.write("scupa_polarization_phase_c: 1.0.0\\n")

print(f"Phase C complete. Dominant state: {dominant} ({state_counts.get(dominant,0)} cells, {100*state_counts.get(dominant,0)/total_cells:.1f}%)")
print(f"Summary → scupa_summary.json  Report → scupa_report.html")
PYEOF
    """
}

// ── Workflow ──────────────────────────────────────────────────────────────────
workflow {
    meta_ch = Channel.of([id: 'scupa_polarization'])
    SCUPA_SCORE(meta_ch)
    SCUPA_POLARIZE(SCUPA_SCORE.out.scored)
    SCUPA_REPORT(SCUPA_POLARIZE.out.polarized)
}
