#!/usr/bin/env nextflow
/*
 * single_cell/merfish_spatial_analysis
 *
 * Image-based spatial transcriptomics analysis for MERFISH / seqFISH+ data.
 * MERFISH (Multiplexed Error-Robust FISH) achieves subcellular resolution by
 * imaging individual RNA molecules in intact tissue sections, producing a
 * cell x gene matrix plus per-cell spatial coordinates.
 *
 * This subworkflow runs a REAL squidpy spatial-statistics pipeline on a
 * decoded MERFISH cell x gene AnnData:
 *   1. Load AnnData (user-supplied .h5ad, OR squidpy's built-in Moffitt-2018
 *      MERFISH hypothalamus dataset when no input is given — 73,655 cells x 161
 *      genes, with .obsm['spatial'] coordinates + Cell_class / Bregma obs).
 *   2. Basic QC + normalization (total-count normalize, log1p).
 *   3. Build the spatial neighbor graph (squidpy.gr.spatial_neighbors,
 *      coord_type='generic' — correct for imaging-based platforms).
 *   4. Spatially variable genes: Moran's I via squidpy.gr.spatial_autocorr
 *      (permutation null + BH-FDR) — the real SVG statistic.
 *   5. Spatial domains: neighborhood enrichment across annotated Cell_class
 *      (squidpy.gr.nhood_enrichment) — which cell types co-localize in space,
 *      summarized as spatial domains/compartments.
 *   6. Plots: spatial scatter of the top SVG + the Moran's I ranking.
 *
 * Tooling is REAL (squidpy / scanpy / anndata, all present in biomni-tools:x86);
 * there is no fabricated / RNG output. If squidpy is unavailable or the dataset
 * cannot be obtained the process exits non-zero (honest failure, never fake data).
 *
 * References:
 *   - Moffitt et al. 2018 Science 362(6416) (MERFISH hypothalamus atlas)
 *   - Palla et al. 2022 Nature Methods (squidpy)
 *   - Chen et al. 2015 Science 348(6233) (seqFISH)
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.input_h5ad          = 'null'      // decoded cell x gene AnnData (.h5ad); if null -> squidpy built-in MERFISH
params.platform            = 'merfish'   // merfish | seqfish | xenium
params.cluster_key         = 'Cell_class' // obs column with cell-type labels (for nhood enrichment)
params.bregma_slice        = 'null'      // optional: restrict to one Bregma slice (e.g. -9) for a 2D view
params.n_perms             = '100'       // Moran's I permutations
params.n_top_svg           = '25'        // SVGs reported in detail / plotted

process MERFISH_SPATIAL_ANALYSIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // squidpy biocontainer (squidpy+scanpy+anndata in the base python3) — probe-verified.
    // NOTE: this process-level directive is what actually runs on AWS Batch (it overrides
    // the DB docker_image for this single_cell workflow), so the container MUST be set here.
    // Legacy biomni-tools:x86 did NOT ship squidpy — see docs/20261001_MERFISH_SPATIAL.md.
    container 'quay.io/biocontainers/squidpy:1.5.0'

    input:
    val(meta)

    output:
    tuple val(meta), path("spatial_qc.json"),              emit: qc
    tuple val(meta), path("spatial_domains.csv"),          emit: domains
    tuple val(meta), path("spatially_variable_genes.csv"), emit: svg
    tuple val(meta), path("spatial_report.txt"),           emit: report
    tuple val(meta), path("*.png"),         optional: true, emit: plots
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_INPUT='${params.input_h5ad}'
    export PARAM_PLATFORM='${params.platform}'
    export PARAM_CLUSTER_KEY='${params.cluster_key}'
    export PARAM_BREGMA='${params.bregma_slice}'
    export PARAM_NPERMS='${params.n_perms}'
    export PARAM_NTOPSVG='${params.n_top_svg}'

    # This workflow runs in quay.io/biocontainers/squidpy (squidpy + scanpy + anndata
    # in the image's default python3 — verified: anndata 0.10.x, scanpy 1.10.x,
    # squidpy 1.5.x; squidpy.datasets.merfish() downloads the Moffitt-2018 atlas over
    # the Batch network). The DB docker_image for this workflow is set accordingly.
    # (Legacy biomni-tools:x86 did NOT ship squidpy — see docs/20261001_MERFISH_SPATIAL.md.)
    # Resolve a squidpy-capable interpreter robustly across images:
    BT_PY=\$(command -v python3 || command -v python)
    for _cand in /opt/conda/envs/biotools/bin/python /opt/conda/bin/python; do
      if [ -x "\$_cand" ] && "\$_cand" -c 'import squidpy' >/dev/null 2>&1; then BT_PY="\$_cand"; break; fi
    done
    echo "Using python: \$BT_PY"

    "\$BT_PY" << 'PYEOF'
import json, os, sys, csv
import numpy as np

def fail(msg):
    sys.stderr.write("ERROR: " + msg + "\\n")
    sys.exit(1)

try:
    import anndata as ad
    import scanpy as sc
    import squidpy as sq
except Exception as e:
    fail("squidpy/scanpy/anndata not importable in this image (%r). "
         "merfish_spatial_analysis requires an image with squidpy+scanpy+anndata "
         "(DB docker_image = quay.io/biocontainers/squidpy). Refusing to emit fabricated results." % e)

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

input_h5ad  = os.environ.get("PARAM_INPUT", "null")
platform    = os.environ.get("PARAM_PLATFORM", "merfish")
cluster_key = os.environ.get("PARAM_CLUSTER_KEY", "Cell_class")
bregma_raw  = os.environ.get("PARAM_BREGMA", "null")
n_perms     = int(float(os.environ.get("PARAM_NPERMS", "100") or 100))
n_top_svg   = int(float(os.environ.get("PARAM_NTOPSVG", "25") or 25))

# ---------------------------------------------------------------- load data
source = None
if input_h5ad not in (None, "", "null") and os.path.exists(input_h5ad):
    adata = ad.read_h5ad(input_h5ad)
    source = "user_h5ad:%s" % os.path.basename(input_h5ad)
else:
    # squidpy built-in Moffitt-2018 MERFISH hypothalamus atlas (73655 x 161)
    try:
        adata = sq.datasets.merfish()
    except Exception as e:
        fail("no input .h5ad supplied and squidpy.datasets.merfish() download failed "
             "(%r). Provide --input_h5ad or ensure network egress for the demo dataset." % e)
    source = "squidpy.datasets.merfish (Moffitt 2018)"

print("Loaded AnnData:", adata.shape, "from", source)

# spatial coords: MERFISH demo ships 3D (spatial3d) + we derive a 2D 'spatial' per slice
if "spatial" not in adata.obsm:
    if "spatial3d" in adata.obsm:
        adata.obsm["spatial"] = np.asarray(adata.obsm["spatial3d"])[:, :2]
    else:
        fail("AnnData has no obsm['spatial'] / obsm['spatial3d'] coordinates — "
             "cannot run spatial statistics.")

# optional: restrict to a single physical slice for a clean 2D view
bregma_used = None
if bregma_raw not in (None, "", "null") and "Bregma" in adata.obs:
    try:
        bval = float(bregma_raw)
        sub = adata[adata.obs["Bregma"] == bval].copy()
        if sub.n_obs > 50:
            adata = sub
            bregma_used = bval
            print("Restricted to Bregma == %s -> %d cells" % (bval, adata.n_obs))
    except Exception:
        pass
elif "Bregma" in adata.obs:
    # default: pick the single most-populated slice so coords are a true 2D section
    try:
        top = adata.obs["Bregma"].value_counts().idxmax()
        sub = adata[adata.obs["Bregma"] == top].copy()
        if sub.n_obs > 50:
            adata = sub
            bregma_used = float(top)
            print("Auto-selected densest Bregma slice %s -> %d cells" % (top, adata.n_obs))
    except Exception:
        pass

n_cells, n_genes = int(adata.n_obs), int(adata.n_vars)
if n_cells < 10 or n_genes < 2:
    fail("too few cells/genes after loading (%d x %d) to run spatial statistics." % (n_cells, n_genes))

# ---------------------------------------------------------------- QC + norm
adata.var_names_make_unique()
X = adata.X
counts_per_cell = np.asarray(X.sum(axis=1)).ravel()
genes_per_cell  = np.asarray((X > 0).sum(axis=1)).ravel()
median_counts   = float(np.median(counts_per_cell))
median_genes    = float(np.median(genes_per_cell))

# normalize for Moran's I (library-size + log1p); keep raw counts for QC above
sc.pp.normalize_total(adata)
sc.pp.log1p(adata)

# ---------------------------------------------------------------- spatial graph
# coord_type='generic' is the correct neighbor model for imaging-based platforms
# (as opposed to 'grid' for Visium). Delaunay gives a robust cell adjacency.
sq.gr.spatial_neighbors(adata, coord_type="generic", delaunay=True)
conn = adata.obsp.get("spatial_connectivities")
mean_degree = float(conn.sum() / conn.shape[0]) if conn is not None else 0.0

# ---------------------------------------------------------------- SVG: Moran's I
sq.gr.spatial_autocorr(adata, mode="moran", n_perms=n_perms, n_jobs=1, seed=0)
moran = adata.uns["moranI"].copy()
# columns: I, pval_norm, var_norm, pval_norm_fdr_bh, ...
moran = moran.sort_values("I", ascending=False)
pval_col = "pval_norm" if "pval_norm" in moran.columns else moran.columns[1]
fdr_col  = next((c for c in moran.columns if "fdr" in c.lower()), None)
n_sig = int((moran[fdr_col] <= 0.05).sum()) if fdr_col else int((moran[pval_col] <= 0.05).sum())

# ---------------------------------------------------------------- spatial domains
# neighborhood enrichment across annotated cell types = which types co-localize
# (spatial compartments / domains). Falls back gracefully if no cluster labels.
domain_rows = []
nhood_ok = False
if cluster_key in adata.obs and adata.obs[cluster_key].nunique() >= 2:
    try:
        adata.obs[cluster_key] = adata.obs[cluster_key].astype("category")
        sq.gr.nhood_enrichment(adata, cluster_key=cluster_key, seed=0)
        z = adata.uns["%s_nhood_enrichment" % cluster_key]["zscore"]
        cats = list(adata.obs[cluster_key].cat.categories)
        counts = adata.obs[cluster_key].value_counts()
        for i, c in enumerate(cats):
            # self-enrichment z (diagonal) = how spatially clustered that type is
            self_z = float(z[i, i])
            # strongest heterotypic partner
            row = z[i].copy(); row[i] = -np.inf
            j = int(np.argmax(row))
            domain_rows.append({
                "domain": str(c),
                "n_cells": int(counts.get(c, 0)),
                "pct_total": round(100.0 * counts.get(c, 0) / n_cells, 2),
                "self_colocalization_z": round(self_z, 2),
                "top_partner": str(cats[j]),
                "partner_z": round(float(z[i, j]), 2),
            })
        domain_rows.sort(key=lambda r: r["self_colocalization_z"], reverse=True)
        nhood_ok = True
    except Exception as e:
        sys.stderr.write("WARN: nhood_enrichment failed (%r)\\n" % e)

# ---------------------------------------------------------------- write outputs
with open("spatially_variable_genes.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["gene", "morans_I", "pval", "fdr_bh", "spatially_variable"])
    for gene, r in moran.iterrows():
        fdr = float(r[fdr_col]) if fdr_col else ""
        sigflag = (fdr <= 0.05) if fdr_col else (float(r[pval_col]) <= 0.05)
        w.writerow([gene, round(float(r["I"]), 4), "%.3e" % float(r[pval_col]),
                    ("%.3e" % fdr) if fdr_col else "", bool(sigflag)])

with open("spatial_domains.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["domain", "n_cells", "pct_total", "self_colocalization_z", "top_partner", "partner_z"])
    for d in domain_rows:
        w.writerow([d["domain"], d["n_cells"], d["pct_total"],
                    d["self_colocalization_z"], d["top_partner"], d["partner_z"]])

top_svgs = list(moran.index[:n_top_svg])
qc = {
    "status": "completed",
    "platform": platform,
    "source": source,
    "bregma_slice": bregma_used,
    "cells": {
        "n_cells": n_cells,
        "median_counts_per_cell": round(median_counts, 1),
        "median_genes_per_cell": round(median_genes, 1),
    },
    "panel_info": {"n_genes": n_genes},
    "spatial_graph": {
        "method": "squidpy spatial_neighbors (generic, Delaunay)",
        "mean_neighbors_per_cell": round(mean_degree, 2),
    },
    "spatially_variable_genes": {
        "method": "squidpy spatial_autocorr (Moran's I, %d perms, BH-FDR)" % n_perms,
        "n_tested": int(moran.shape[0]),
        "n_significant_fdr05": n_sig,
        "top_svg": top_svgs[:10],
        "top_morans_I": round(float(moran["I"].iloc[0]), 4),
    },
    "spatial_domains": {
        "method": "squidpy nhood_enrichment (z-score)" if nhood_ok else "not run (no cell-type labels)",
        "cluster_key": cluster_key if nhood_ok else None,
        "n_domains": len(domain_rows),
    },
    "references": [
        "Moffitt et al. 2018 Science 362(6416) (MERFISH)",
        "Palla et al. 2022 Nature Methods (squidpy)",
    ],
}
with open("spatial_qc.json", "w") as f:
    json.dump(qc, f, indent=2)

# plots
plot_files = []
try:
    sq.pl.spatial_scatter(adata, color=top_svgs[0], shape=None, size=8,
                          title="Top SVG: %s (Moran I=%.3f)" % (top_svgs[0], moran['I'].iloc[0]))
    plt.savefig("top_svg_spatial.png", dpi=120, bbox_inches="tight"); plt.close("all")
    plot_files.append("top_svg_spatial.png")
except Exception as e:
    sys.stderr.write("WARN: spatial_scatter plot failed (%r)\\n" % e)

try:
    topn = min(20, moran.shape[0])
    fig, ax = plt.subplots(figsize=(6, max(3, topn * 0.25)))
    sub = moran.iloc[:topn][::-1]
    ax.barh(range(topn), sub["I"].values, color="#4C72B0")
    ax.set_yticks(range(topn)); ax.set_yticklabels(list(sub.index))
    ax.set_xlabel("Moran's I"); ax.set_title("Top spatially variable genes")
    plt.tight_layout(); plt.savefig("morans_I_ranking.png", dpi=120); plt.close("all")
    plot_files.append("morans_I_ranking.png")
except Exception as e:
    sys.stderr.write("WARN: Moran ranking plot failed (%r)\\n" % e)

# text report
L = []
L.append("=" * 64)
L.append("  %s Spatial Transcriptomics Report (squidpy)" % platform.upper())
L.append("  Source: %s" % source)
if bregma_used is not None:
    L.append("  Slice: Bregma = %s" % bregma_used)
L.append("=" * 64)
L.append("  Cells:                    %d" % n_cells)
L.append("  Genes (panel):            %d" % n_genes)
L.append("  Median counts/cell:       %.1f" % median_counts)
L.append("  Median genes/cell:        %.1f" % median_genes)
L.append("  Mean spatial neighbors:   %.2f" % mean_degree)
L.append("  SVGs tested (Moran's I):  %d" % int(moran.shape[0]))
L.append("  SVGs significant (FDR5%%): %d" % n_sig)
if domain_rows:
    L.append("  Cell-type domains:        %d" % len(domain_rows))
L.append("")
L.append("  Top spatially variable genes (Moran's I):")
for gene in top_svgs[:8]:
    r = moran.loc[gene]
    L.append("    %-14s I=%.3f  p=%.1e" % (gene, float(r["I"]), float(r[pval_col])))
if domain_rows:
    L.append("")
    L.append("  Most spatially-clustered cell types (self-colocalization z):")
    for d in domain_rows[:6]:
        L.append("    %-22s z=%.1f  (%d cells, top partner %s)"
                 % (d["domain"], d["self_colocalization_z"], d["n_cells"], d["top_partner"]))
report = "\\n".join(L)
with open("spatial_report.txt", "w") as f:
    f.write(report + "\\n")
print(report)

# versions
sqv = getattr(sq, "__version__", "NA")
scv = getattr(sc, "__version__", "NA")
adv = getattr(ad, "__version__", "NA")
with open("versions.yml", "w") as f:
    f.write("merfish_spatial_analysis:\\n")
    f.write('  squidpy: "%s"\\n' % sqv)
    f.write('  scanpy: "%s"\\n' % scv)
    f.write('  anndata: "%s"\\n' % adv)
print("Pipeline completed successfully. Outputs: spatial_qc.json, spatial_domains.csv, "
      "spatially_variable_genes.csv, spatial_report.txt, %s, versions.yml" % ", ".join(plot_files))
PYEOF
    """
}

workflow MERFISH_WORKFLOW {
    take: meta_ch
    main: MERFISH_SPATIAL_ANALYSIS(meta_ch)
    emit:
        qc      = MERFISH_SPATIAL_ANALYSIS.out.qc
        domains = MERFISH_SPATIAL_ANALYSIS.out.domains
        svg     = MERFISH_SPATIAL_ANALYSIS.out.svg
        report  = MERFISH_SPATIAL_ANALYSIS.out.report
        versions = MERFISH_SPATIAL_ANALYSIS.out.versions
}

workflow { meta = [id:'merfish_run']; Channel.value(meta) | MERFISH_WORKFLOW }
