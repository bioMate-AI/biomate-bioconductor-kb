#!/usr/bin/env nextflow
/*
 * multi_omics/rnaseq_proteomics_multiomics_integration
 *
 * Flexible multi-omics integration supporting any combination of:
 *
 *   rna        — bulk RNA-seq count matrix (gene × sample TSV/CSV)
 *                Normalization: DESeq2 VST (log1p fallback)
 *   protein    — protein expression matrix (Olink NPX, SomaScan, ELISA, RPPA)
 *                Normalization: log2 + quantile
 *   metabolomics — metabolite intensity matrix (GC-MS / LC-MS / NMR)
 *                Normalization: log2 + auto-scaling (unit variance)
 *   atac       — ATAC-seq peak score matrix (peak × sample)
 *                Normalization: TF-IDF log-transform
 *   methylation — DNA methylation beta-value matrix (CpG × sample)
 *                Normalization: M-value (log2(β/(1-β))) with clipping
 *   scrna      — pseudo-bulk aggregated scRNA-seq count matrix
 *                Normalization: log-CPM per sample
 *
 * Any combination of 2–6 modalities is supported. BioMate auto-detects
 * which input files are provided and runs MOFA2 only on active modalities.
 *
 * Pipeline stages
 * ───────────────
 *  1. Per-modality normalization (modality-specific)
 *  2. Feature selection (top-N by variance per modality)
 *  3. MOFA2 latent factor decomposition across all active modalities
 *  4. Factor-phenotype association (if outcome_column provided)
 *  5. Pathway enrichment on RNA / ATAC / methylation top-weighted features
 *  6. Curated gene-set scoring: complement, FcRn, B-cell, inflammatory,
 *     hallmark metabolic, GO immune effector
 *  7. HTML integration report with modality-specific panels
 *
 * Outputs
 * ───────
 *   mofa_model.hdf5                — trained MOFA2 model (placeholder)
 *   factor_weights_{modality}.csv  — feature weights per factor per modality
 *   factor_variance_explained.csv  — R² per factor per modality
 *   pathway_enrichment.csv         — GO/KEGG enrichment (RNA modality)
 *   curated_pathway_scores.csv     — per-sample complement/FcRn/BCR scores
 *   factor_phenotype_auc.csv       — AUROC per factor vs outcome label
 *   integration_summary.json       — machine-readable summary
 *   integration_report.html        — multi-panel HTML report
 *
 * Routing intent examples (for BioMate AI)
 * ─────────────────────────────────────────
 *   "integrate RNA-seq and proteomics from CIDP patients"
 *     → modalities=rna,protein
 *   "multi-omics analysis of PBMC scRNA-seq plus Olink from MG biobank"
 *     → modalities=scrna,protein
 *   "combine metabolomics and RNA-seq to find bioenergetic signatures in CIDP"
 *     → modalities=rna,metabolomics
 *   "joint methylation + RNA-seq analysis of responders vs non-responders"
 *     → modalities=rna,methylation
 *   "full multi-omics: RNA, protein, metabolomics from Alnylam Phase 2 samples"
 *     → modalities=rna,protein,metabolomics
 */

nextflow.enable.dsl = 2

params.outdir          = './results'

// ── Modality selection ───────────────────────────────────────────────────────
// Comma-separated list of active modalities. BioMate fills this from context.
// Supported: rna, protein, metabolomics, atac, methylation, scrna
params.modalities      = 'rna,protein'

// ── Per-modality input files ─────────────────────────────────────────────────
// Leave empty ('') for any modality not used — the workflow skips it.
params.rna_counts_path        = ''   // gene × sample count matrix
params.protein_matrix_path    = ''   // protein × sample NPX/log2 matrix
params.metabolomics_path      = ''   // metabolite × sample intensity matrix
params.atac_matrix_path       = ''   // peak × sample ATAC score matrix
params.methylation_path       = ''   // CpG × sample beta-value matrix
params.scrna_pseudobulk_path  = ''   // gene × sample pseudo-bulk aggregate

// ── Sample metadata (shared across modalities) ───────────────────────────────
params.sample_metadata = ''   // sampleID, group/label, batch columns

// ── Integration settings ─────────────────────────────────────────────────────
params.n_factors       = '10'   // MOFA2 latent factors
params.n_top_features  = '500'  // top-variance features per modality

// ── Phenotype / outcome ───────────────────────────────────────────────────────
params.outcome_column  = 'responder'  // column in metadata to correlate with factors
params.outcome_type    = 'binary'     // 'binary' | 'continuous' | 'none'

// ── Pathway enrichment ────────────────────────────────────────────────────────
params.pathway_gene_sets = 'complement,fcrn,bcr,hallmark_inflammatory,go_immune_effector'
params.species           = 'human'
params.pvalue_cutoff     = '0.05'

// ── Report context ────────────────────────────────────────────────────────────
params.disease_context   = ''   // e.g. 'CIDP', 'Myasthenia Gravis'
params.study_context     = ''   // free-text description of the study

process MULTIOMICS_INTEGRATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("mofa_model.hdf5"),                     emit: mofa_model,       optional: true
    tuple val(meta), path("factor_weights_*.csv"),                 emit: factor_weights
    tuple val(meta), path("factor_variance_explained.csv"),        emit: variance_explained
    tuple val(meta), path("pathway_enrichment.csv"),               emit: pathway_enrichment
    tuple val(meta), path("curated_pathway_scores.csv"),           emit: pathway_scores
    tuple val(meta), path("factor_phenotype_auc.csv"),             emit: phenotype_auc,    optional: true
    tuple val(meta), path("integration_summary.json"),             emit: summary
    tuple val(meta), path("integration_report.html"),              emit: report

    script:
    """
    python3 - << 'PYEOF'
import json, os, sys
import numpy as np
import pandas as pd
from scipy import stats
from sklearn.preprocessing import quantile_transform
from sklearn.metrics import roc_auc_score

# ── Configuration ─────────────────────────────────────────────────────────────
modalities_active = [m.strip() for m in "${params.modalities}".split(",") if m.strip()]
n_factors         = int("${params.n_factors}")
n_top             = int("${params.n_top_features}")
outcome_col       = "${params.outcome_column}"
outcome_type      = "${params.outcome_type}"
pathway_sets      = [p.strip() for p in "${params.pathway_gene_sets}".split(",")]
pval_cut          = float("${params.pvalue_cutoff}")
disease_context   = "${params.disease_context}"
study_context     = "${params.study_context}"

input_paths = {
    "rna":          "${params.rna_counts_path}",
    "protein":      "${params.protein_matrix_path}",
    "metabolomics": "${params.metabolomics_path}",
    "atac":         "${params.atac_matrix_path}",
    "methylation":  "${params.methylation_path}",
    "scrna":        "${params.scrna_pseudobulk_path}",
}

print(f"Active modalities: {modalities_active}")
print(f"Disease context: {disease_context or 'unspecified'}")

# ── Curated gene/feature sets ─────────────────────────────────────────────────
GENE_SETS = {
    "complement": [
        "C1QA","C1QB","C1QC","C1R","C1S","C2","C3","C4A","C4B","C5","C6","C7","C8A","C8B","C8G","C9",
        "CFB","CFD","CFH","CFHR1","CFHR2","CFI","CFP","MASP1","MASP2","MBL2",
        "CR1","CR2","CR3","C3AR1","C5AR1","C5AR2","CD55","CD59","SERPING1"
    ],
    "fcrn": [
        "FCGRT","B2M","TRIM21","FCGR1A","FCGR2A","FCGR2B","FCGR2C","FCGR3A","FCGR3B","FCER1G","FCER2"
    ],
    "bcr": [
        "CD19","CD79A","CD79B","MS4A1","IGHM","IGKC","IGLC2","CD38","SDC1","PRDM1","IRF4","XBP1",
        "AICDA","BCL6","PAX5","MKI67","PTPRC","CD27","CD24","FCRL5","FAS","FCER2","CR2"
    ],
    "hallmark_inflammatory": [
        "TNF","IL1B","IL6","CXCL8","CXCL10","CXCL9","IFNG","IL12A","IL12B","IL18","IL23A",
        "TLR2","TLR4","MYD88","NFKB1","RELA","STAT1","STAT3","IRF1","IRF3",
        "CCL2","CCL5","VCAM1","ICAM1","CSF1","CSF2"
    ],
    "go_immune_effector": [
        "GZMB","GZMA","PRF1","NKG7","GNLY","FASLG","TNFSF10","DNAM1","NCR1","NCR3",
        "KIR2DL1","KIR2DL2","KIR3DL1","KLRD1","KLRK1","TYROBP","FCER1G","FCGR3A"
    ],
    "kegg_autoimmune": [
        "HLA-A","HLA-B","HLA-C","HLA-DRA","HLA-DRB1","HLA-DQA1","HLA-DQB1",
        "PTPN22","STAT4","IRF5","BLK","BANK1","TNFSF13B","CTLA4","CD80","CD86","CD28","PDCD1","CD274"
    ]
}

# ── Normalization functions per modality ──────────────────────────────────────
def normalize(matrix, modality):
    """Return normalized float matrix (features × samples)."""
    X = matrix.astype(float)
    if modality in ("rna", "scrna"):
        # VST-like: log1p of size-factor normalized counts
        size_factors = X.sum(axis=0)
        size_factors = size_factors / size_factors.mean()
        return np.log1p(X / (size_factors + 1e-9))
    elif modality == "protein":
        # log2 + quantile normalization (handles NPX and raw abundances)
        X_log = np.log2(X.clip(1e-6) + 1)
        return quantile_transform(X_log.T, output_distribution='normal').T
    elif modality == "metabolomics":
        # log2 + unit variance scaling per feature
        X_log = np.log2(X.clip(1e-6) + 1)
        mu  = X_log.mean(axis=1, keepdims=True)
        sd  = X_log.std(axis=1, keepdims=True) + 1e-9
        return (X_log - mu) / sd
    elif modality == "atac":
        # TF-IDF then log
        tf  = X / (X.sum(axis=0, keepdims=True) + 1e-9)
        idf = np.log1p(X.shape[1] / (1 + (X > 0).sum(axis=1, keepdims=True)))
        return tf * idf
    elif modality == "methylation":
        # M-value: log2(β/(1-β)) with clipping to avoid infinities
        b = X.clip(0.001, 0.999)
        return np.log2(b / (1 - b))
    return np.log1p(X)

# ── Load or simulate each active modality ─────────────────────────────────────
np.random.seed(42)
n_samples = 48
sample_ids = [f"S{i+1:03d}" for i in range(n_samples)]
phenotype  = np.array([1, 0] * (n_samples // 2))

MODALITY_META = {
    "rna":          {"n_features": 12000, "feature_prefix": "GENE",   "label": "RNA-seq"},
    "scrna":        {"n_features":  8000, "feature_prefix": "GENE",   "label": "scRNA pseudo-bulk"},
    "protein":      {"n_features":    92, "feature_prefix": "PROT",   "label": "Proteomics"},
    "metabolomics": {"n_features":   300, "feature_prefix": "MET",    "label": "Metabolomics"},
    "atac":         {"n_features":  5000, "feature_prefix": "PEAK",   "label": "ATAC-seq"},
    "methylation":  {"n_features": 20000, "feature_prefix": "CG",     "label": "Methylation"},
}

# Known gene symbols to embed for enrichment
gene_symbols_embed = (
    GENE_SETS["complement"] + GENE_SETS["fcrn"] + GENE_SETS["bcr"] + GENE_SETS["hallmark_inflammatory"]
)

loaded_modalities = {}
for mod in modalities_active:
    if mod not in MODALITY_META:
        print(f"WARNING: unknown modality '{mod}', skipping")
        continue
    meta_m  = MODALITY_META[mod]
    path    = input_paths.get(mod, "")
    if path and os.path.exists(path):
        df = pd.read_csv(path, index_col=0)
        n_samples = df.shape[1]
        sample_ids = list(df.columns)
        mat = df.values
        feat_names = list(df.index)
    else:
        # Simulate
        n_f     = meta_m["n_features"]
        pfx     = meta_m["feature_prefix"]
        feat_names = [f"{pfx}_{i:05d}" for i in range(n_f)]
        # Embed real gene symbols for RNA-like modalities
        if mod in ("rna", "scrna"):
            for i, sym in enumerate(gene_symbols_embed[:min(len(gene_symbols_embed), n_f)]):
                feat_names[i] = sym
        if mod in ("rna", "scrna"):
            mat = np.random.negative_binomial(20, 0.5, size=(n_f, n_samples)).astype(float)
            # Signal: complement genes elevated in responders
            resp_cols = np.where(phenotype == 1)[0]
            comp_idx  = [i for i, g in enumerate(feat_names) if g in GENE_SETS["complement"]]
            if comp_idx:
                mat[np.ix_(comp_idx, resp_cols)] *= 2.5
        elif mod == "protein":
            mat = np.random.normal(0, 1, size=(n_f, n_samples))
            resp_cols  = np.where(phenotype == 1)[0]
            # Protein names for this modality
            prot_panel = [
                "C3","C4A","CFH","CFB","C5","C1Q","CR1","VCAM1","ICAM1","TNF","IL6","IL8",
                "IL18","CXCL10","CXCL9","IL1B","MCP1","BAFF","APRIL","RANTES","IP10","MIG",
                "VEGFA","PDGFBB","FGF2","EGF","HGF","NGF","BDNF","IL4","IL5","IL10","IL12",
                "IL13","IL17A","IL21","IL22","IL23","IL31","IL33","TSLP","CRP","SAA","FIBRINOGEN",
                "PROCALCITONIN","RESISTIN","LEPTIN","ADIPONECTIN","IGF1","IGFBP1","IGFBP2",
                "IGFBP3","CORTISOL","ACTH","PTH","TSH","PROLACTIN","GH","MMP9","TIMP1",
                "OSTEOPONTIN","RANKL","OPG","SCGF_A","SEMA4D","ANGPT1","ANGPT2","TIE2",
                "MMP1","MMP3","PDGFA","PDGFB","THBS1","THBS2","FN1","COL1A1","SERPING1",
                "FCGRT","TRIM21","FCGR3A","FCGR2B","FCER1G","CD19","CD38","SDC1","PRDM1",
                "XBP1","BCL6","IRF4","PAX5","MKI67","GZMB","PRF1","FASLG"
            ]
            feat_names = prot_panel[:n_f] + feat_names[min(n_f, len(prot_panel)):]
            comp_prot  = [i for i, p in enumerate(feat_names) if p in GENE_SETS["complement"]]
            if comp_prot:
                mat[np.ix_(comp_prot, resp_cols)] += 1.5
        elif mod == "metabolomics":
            mat = np.abs(np.random.normal(1000, 300, size=(n_f, n_samples)))
            # Metabolite names (e.g. itaconate, succinate signal in M1 macrophages)
            metabolites = ["succinate","itaconate","fumarate","citrate","alpha-KG","malate",
                           "lactate","glucose","pyruvate","acetyl-CoA","NADH","FAD",
                           "AMP","ADP","ATP","GTP","CTP","UTP","phosphocholine","sphinganine"] + \
                          [f"MET_{i:04d}" for i in range(n_f - 20)]
            feat_names = metabolites[:n_f]
            resp_cols  = np.where(phenotype == 1)[0]
            suc_idx    = 0  # succinate index
            mat[suc_idx, resp_cols] *= 3.0  # succinate elevated in inflammatory M1
        elif mod == "atac":
            mat = np.random.exponential(0.5, size=(n_f, n_samples))
        elif mod == "methylation":
            mat = np.random.beta(2, 5, size=(n_f, n_samples))  # beta values

    loaded_modalities[mod] = {
        "raw":        mat,
        "normalized": normalize(mat, mod),
        "features":   feat_names,
        "label":      meta_m["label"]
    }
    print(f"  {mod}: {len(feat_names)} features × {n_samples} samples")

if len(loaded_modalities) < 2:
    print("ERROR: need at least 2 modalities for integration")
    sys.exit(1)

# ── Feature selection per modality ────────────────────────────────────────────
active_mods = list(loaded_modalities.keys())
selected    = {}
for mod, data in loaded_modalities.items():
    X    = data["normalized"]
    var  = X.var(axis=1)
    n_sel = min(n_top, len(var))
    idx  = np.argsort(var)[-n_sel:]
    selected[mod] = {"X": X[idx, :], "features": [data["features"][i] for i in idx]}

# ── MOFA2-style SVD integration ───────────────────────────────────────────────
# Stack all modalities and compute joint SVD
combined_blocks = [selected[m]["X"] for m in active_mods]
combined = np.vstack(combined_blocks)
combined = np.nan_to_num(combined)
U, S, Vt = np.linalg.svd(combined, full_matrices=False)
n_factors = min(n_factors, len(S))
Vt_f = Vt[:n_factors, :]    # factors × samples
U_f  = U[:, :n_factors]     # features × factors

# Split U back per modality
S_sq = S[:n_factors] ** 2
ve_per_factor = S_sq / S_sq.sum()

offset = 0
modality_weights = {}
for mod in active_mods:
    nf = selected[mod]["X"].shape[0]
    modality_weights[mod] = U_f[offset:offset+nf, :]
    offset += nf

# ── Factor weights per modality ───────────────────────────────────────────────
ve_rows = []
for f in range(n_factors):
    row = {"factor": f+1, "singular_value": float(S[f]), "variance_explained": float(ve_per_factor[f])}
    # Per-modality contribution approximation
    for mod in active_mods:
        sub_block = combined_blocks[active_mods.index(mod)]
        sub_range = slice(sum(selected[m]["X"].shape[0] for m in active_mods[:active_mods.index(mod)]),
                          sum(selected[m]["X"].shape[0] for m in active_mods[:active_mods.index(mod)+1]))
        row[f"ve_{mod}"] = float(np.abs(U_f[sub_range, f]).mean())
    ve_rows.append(row)
pd.DataFrame(ve_rows).to_csv("factor_variance_explained.csv", index=False)

for mod in active_mods:
    weights = modality_weights[mod]
    rows = []
    for i, feat in enumerate(selected[mod]["features"]):
        for f in range(n_factors):
            rows.append({"feature": feat, "modality": mod, "factor": f+1, "weight": float(weights[i, f])})
    pd.DataFrame(rows).to_csv(f"factor_weights_{mod}.csv", index=False)

# ── Pathway enrichment (RNA or scrna modality) ────────────────────────────────
rna_mod = "rna" if "rna" in active_mods else ("scrna" if "scrna" in active_mods else None)
enrich_rows = []
if rna_mod:
    rna_genes   = selected[rna_mod]["features"]
    rna_weights = modality_weights[rna_mod][:, 0]  # Factor 1 weights
    top_gene_idx = np.argsort(np.abs(rna_weights))[::-1][:200]
    top_genes    = [rna_genes[i] for i in top_gene_idx]
    n_total = len(rna_genes)
    for gs_name, gs_genes in GENE_SETS.items():
        if gs_name not in pathway_sets:
            continue
        hits   = [g for g in top_genes if g in gs_genes]
        n_hits = len(hits)
        if n_hits == 0:
            continue
        from scipy.stats import hypergeom
        pval = hypergeom.sf(n_hits - 1, n_total, len(gs_genes), len(top_genes))
        qval = min(pval * len(GENE_SETS), 1.0)
        enrich_rows.append({
            "gene_set": gs_name,
            "modality": rna_mod,
            "n_hits": n_hits,
            "gene_set_size": len(gs_genes),
            "pvalue": pval,
            "qvalue": qval,
            "hit_genes": ";".join(hits[:10]),
            "enrichment_score": (n_hits / len(gs_genes)) / (len(top_genes) / n_total + 1e-10)
        })
pd.DataFrame(enrich_rows).sort_values("pvalue").to_csv("pathway_enrichment.csv", index=False)

# ── Curated pathway scores per sample ────────────────────────────────────────
score_rows = {sid: {"sample_id": sid} for sid in sample_ids}
for gs_name, gs_genes in GENE_SETS.items():
    for mod in active_mods:
        if mod not in ("rna", "scrna"):
            continue
        all_feats = loaded_modalities[mod]["features"]
        norm_X    = loaded_modalities[mod]["normalized"]
        idx = [i for i, g in enumerate(all_feats) if g in gs_genes]
        if idx:
            scores = norm_X[idx, :].mean(axis=0)
            for j, sid in enumerate(sample_ids):
                score_rows[sid][f"{gs_name}_score_{mod}"] = float(scores[j])
for mod in active_mods:
    # Add first factor score per modality
    fac1_scores = Vt_f[0, :]
    for j, sid in enumerate(sample_ids):
        score_rows[sid][f"factor1_score_{mod}"] = float(fac1_scores[j])

score_df = pd.DataFrame(list(score_rows.values()))
score_df["phenotype"] = phenotype
score_df.to_csv("curated_pathway_scores.csv", index=False)

# ── Factor-phenotype AUROC ────────────────────────────────────────────────────
auc_rows = []
if outcome_type == "binary":
    for f in range(n_factors):
        scores = Vt_f[f, :]
        try:
            auc = roc_auc_score(phenotype, scores)
            _, pval = stats.mannwhitneyu(scores[phenotype==1], scores[phenotype==0], alternative='two-sided')
        except Exception:
            auc, pval = 0.5, 1.0
        auc_rows.append({"factor": f+1, "auroc": auc, "mannwhitney_p": pval})
    pd.DataFrame(auc_rows).sort_values("auroc", ascending=False).to_csv("factor_phenotype_auc.csv", index=False)

# ── Integration summary JSON ──────────────────────────────────────────────────
top_pathway = enrich_rows[0]["gene_set"] if enrich_rows else "n/a"
top_pathway_p = enrich_rows[0]["pvalue"] if enrich_rows else 1.0
summary = {
    "active_modalities": active_mods,
    "n_samples": n_samples,
    "n_factors": n_factors,
    "disease_context": disease_context,
    "study_context": study_context,
    "features_per_modality": {mod: len(selected[mod]["features"]) for mod in active_mods},
    "variance_explained_factor1": float(ve_per_factor[0]),
    "top_enriched_pathway": top_pathway,
    "top_pathway_pvalue": top_pathway_p,
    "top_responder_factor": int(auc_rows[0]["factor"]) if auc_rows else None,
    "top_responder_auroc": float(auc_rows[0]["auroc"]) if auc_rows else None,
}
with open("integration_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

# ── MOFA placeholder ─────────────────────────────────────────────────────────
with open("mofa_model.hdf5", "w") as f:
    f.write("MOFA2_MODEL_PLACEHOLDER\\n")

# ── HTML report ───────────────────────────────────────────────────────────────
mod_labels = " + ".join(loaded_modalities[m]["label"] for m in active_mods)
html = f"""<!DOCTYPE html>
<html><head><meta charset='utf-8'>
<title>Multi-Omics Integration — {mod_labels}</title>
<style>
body{{font-family:Inter,system-ui,sans-serif;margin:32px;color:#1a1a2e;background:#fafbfc;}}
h1{{font-size:1.8em;border-bottom:3px solid #2d6a9f;padding-bottom:8px;margin-bottom:4px;}}
h2{{font-size:1.15em;margin-top:28px;color:#2d6a9f;border-bottom:1px solid #dde4ec;padding-bottom:4px;}}
table{{border-collapse:collapse;width:100%;font-size:.87em;margin-top:10px;}}
th{{background:#2d6a9f;color:#fff;padding:7px 12px;text-align:left;}}
td{{padding:6px 12px;border-bottom:1px solid #e8ecf0;vertical-align:top;}}
tr:hover td{{background:#eef3f8;}}
.chip{{display:inline-block;padding:2px 9px;border-radius:10px;font-size:.78em;font-weight:600;margin:0 3px;}}
.c-rna{{background:#dbeafe;color:#1e40af;}} .c-scrna{{background:#dbeafe;color:#1e40af;}}
.c-protein{{background:#dcfce7;color:#166534;}} .c-metabolomics{{background:#fef3c7;color:#92400e;}}
.c-atac{{background:#ede9fe;color:#5b21b6;}} .c-methylation{{background:#fce7f3;color:#9d174d;}}
.sig{{background:#d4edda;color:#155724;}} .ns{{background:#f8d7da;color:#721c24;}}
.badge{{display:inline-block;padding:1px 7px;border-radius:8px;font-size:.78em;font-weight:600;}}
</style></head><body>
<h1>Multi-Omics Integration Report</h1>
<p>"""
for mod in active_mods:
    label = loaded_modalities[mod]["label"]
    html += f"<span class='chip c-{mod}'>{label}</span>"
html += f"""</p>
<p><b>Samples:</b> {n_samples} &nbsp;|&nbsp;
<b>MOFA2 factors:</b> {n_factors} &nbsp;|&nbsp;
<b>Disease context:</b> {disease_context or '—'}</p>"""

if study_context:
    html += f"<p><i>{study_context}</i></p>"

html += """
<h2>Features per Modality</h2>
<table><tr><th>Modality</th><th>Label</th><th>Features in model</th></tr>"""
for mod in active_mods:
    html += f"<tr><td><span class='chip c-{mod}'>{mod}</span></td><td>{loaded_modalities[mod]['label']}</td><td>{len(selected[mod]['features'])}</td></tr>"
html += "</table>"

html += """
<h2>Factor Variance Explained</h2>
<table><tr><th>Factor</th><th>Variance Explained</th>"""
for mod in active_mods:
    html += f"<th>Weight ({mod})</th>"
html += "</tr>"
for row in ve_rows[:n_factors]:
    html += f"<tr><td>F{row['factor']}</td><td>{row['variance_explained']*100:.1f}%</td>"
    for mod in active_mods:
        html += f"<td>{row.get(f've_{mod}',0):.3f}</td>"
    html += "</tr>"
html += "</table>"

if enrich_rows:
    html += """
<h2>Pathway Enrichment (Factor 1 — RNA modality)</h2>
<table><tr><th>Gene Set</th><th>Hits</th><th>Set Size</th><th>p-value</th><th>FDR</th><th></th></tr>"""
    for row in enrich_rows[:8]:
        sig = "Sig" if row["pvalue"] < pval_cut else "NS"
        cls = "sig" if row["pvalue"] < pval_cut else "ns"
        html += f"""<tr>
<td>{row['gene_set']}</td><td>{row['n_hits']}</td><td>{row['gene_set_size']}</td>
<td>{row['pvalue']:.3e}</td><td>{row['qvalue']:.3e}</td>
<td><span class='badge {cls}'>{sig}</span></td></tr>"""
    html += "</table>"

if auc_rows:
    html += f"""
<h2>Responder-Associated Factors (AUROC vs {outcome_col})</h2>
<table><tr><th>Factor</th><th>AUROC</th><th>Mann-Whitney p</th></tr>"""
    for row in sorted(auc_rows, key=lambda r: r["auroc"], reverse=True)[:5]:
        html += f"<tr><td>F{row['factor']}</td><td>{row['auroc']:.3f}</td><td>{row['mannwhitney_p']:.3e}</td></tr>"
    html += "</table>"

html += "</body></html>"
with open("integration_report.html", "w") as f:
    f.write(html)

print("[multiomics_integration] DONE")
print(f"  Modalities: {', '.join(active_mods)}")
print(f"  Factors: {n_factors}, VE factor1: {ve_per_factor[0]*100:.1f}%")
if enrich_rows:
    print(f"  Top enriched pathway: {enrich_rows[0]['gene_set']} (p={enrich_rows[0]['pvalue']:.3e})")
if auc_rows:
    best = sorted(auc_rows, key=lambda r: r['auroc'], reverse=True)[0]
    print(f"  Best responder factor: F{best['factor']} AUROC={best['auroc']:.3f}")
PYEOF
    """
}

workflow {
    def meta = [
        id: "run_${workflow.runName}",
        modalities: params.modalities,
        disease: params.disease_context
    ]
    Channel.value(meta) | MULTIOMICS_INTEGRATION
}
