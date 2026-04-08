#!/usr/bin/env nextflow
/*
 * genomics/perturb_seq_analysis
 *
 * End-to-end Perturb-seq CRISPR screen analysis pipeline.
 * Steps:
 *   1. Guide assignment    — MAGeCK count
 *   2. Hit calling         — MAGeCK MLE
 *   3. Perturbation state  — scVI / scANVI embedding
 *
 * Reference: Replogle JM et al. 2022 Cell 185(14):2559-2575
 *            https://doi.org/10.1016/j.cell.2022.05.013
 */

nextflow.enable.dsl = 2

// ─── Parameters ─────────────────────────────────────────────────────────────

params.outdir         = './results'

// Guide library / screen inputs
params.fastq          = null          // Path to FASTQ file(s) (glob OK)
params.library_csv    = null          // Guide library: columns sgRNA, gene, sequence
params.design_matrix  = null          // MAGeCK MLE design matrix
params.anndata_h5ad   = null          // AnnData h5ad with guide assignments in obs
params.sample_label   = 'sample'      // Label for MAGeCK count output columns
params.batch_key      = 'none'        // obs column for batch correction (or 'none')
params.guide_key      = 'guide'       // obs column holding guide assignment
params.label_key      = 'Unknown'     // obs column for cell type labels (or 'Unknown')

// ─── PROCESS 1: Guide assignment via MAGeCK count ───────────────────────────

process MAGECK_COUNT {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/mageck_count", mode: 'copy'

    container 'quay.io/biocontainers/mageck:0.5.9.5--py39h7cff6ad_2'

    input:
    tuple val(meta), path(fastq_files)
    path library_csv                   // Guide library: columns sgRNA, gene, sequence
    val  sample_label

    output:
    tuple val(meta), path("${meta.id}.count.txt")            , emit: count_table
    tuple val(meta), path("${meta.id}.count_normalized.txt") , emit: count_normalized
    tuple val(meta), path("${meta.id}.count.log")            , emit: log
    tuple val(meta), path("mageck_count_summary.json")       , emit: qc_summary
    path "versions.yml"                                       , emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Combine all FASTQ files when multiple are supplied
    cat ${fastq_files} > combined.fastq.gz 2>/dev/null || cp ${fastq_files[0]} combined.fastq.gz

    mageck count \\
        --list-seq ${library_csv} \\
        --fastq combined.fastq.gz \\
        --sample-label "${sample_label}" \\
        --output-prefix "${meta.id}" \\
        --norm-method median \\
        --no-hdr-info

    # Parse MAGeCK log to produce a structured QC JSON
    python3 - <<'PYEOF'
import json, re

log_text = open("${meta.id}.count.log").read()
qc = {}

m = re.search(r"([\\d.]+)% mapped", log_text)
if m:
    qc["mapping_rate_pct"] = float(m.group(1))

m = re.search(r"Total:(\\s*)(\\d+)", log_text)
if m:
    qc["total_reads"] = int(m.group(2))

m = re.search(r"Mapped:(\\s*)(\\d+)", log_text)
if m:
    qc["mapped_reads"] = int(m.group(2))

count_lines = [l for l in open("${meta.id}.count.txt") if not l.startswith("sgRNA")]
n_nonzero   = sum(1 for l in count_lines if int(l.strip().split()[-1]) > 0)
qc["guide_library_coverage_pct"] = round(100 * n_nonzero / max(1, len(count_lines)), 1)
qc["n_guides"] = len(count_lines)

json.dump(qc, open("mageck_count_summary.json", "w"), indent=2)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mageck: \$(mageck --version 2>&1 | head -1 | awk '{print \$NF}')
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

// ─── PROCESS 2: Hit calling via MAGeCK MLE ──────────────────────────────────

process MAGECK_MLE {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/mageck_mle", mode: 'copy'

    container 'quay.io/biocontainers/mageck:0.5.9.5--py39h7cff6ad_2'

    input:
    tuple val(meta), path(count_table)
    path design_matrix                 // MAGeCK MLE design matrix (samples x conditions)

    output:
    tuple val(meta), path("${meta.id}.gene_summary.txt") , emit: gene_summary
    tuple val(meta), path("${meta.id}.sgrna_summary.txt"), emit: sgrna_summary
    tuple val(meta), path("hits_table.csv")              , emit: hits_table
    path "versions.yml"                                  , emit: versions

    script:
    """
    mageck mle \\
        --count-table ${count_table} \\
        --design-matrix ${design_matrix} \\
        --output-prefix "${meta.id}" \\
        --norm-method median

    python3 - <<'PYEOF'
import csv

hits = []
with open("${meta.id}.gene_summary.txt") as fh:
    reader = csv.DictReader(fh, delimiter="\\t")
    for row in reader:
        hits.append({
            "gene"      : row.get("Gene", row.get("gene", "")),
            "beta"      : row.get("beta", ""),
            "z_score"   : row.get("z", ""),
            "p_value"   : row.get("p.value", ""),
            "FDR"       : row.get("FDR", ""),
            "significant": "True" if float(row.get("FDR", 1)) < 0.1 else "False",
        })

with open("hits_table.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["gene","beta","z_score","p_value","FDR","significant"])
    w.writeheader()
    w.writerows(hits)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mageck: \$(mageck --version 2>&1 | head -1 | awk '{print \$NF}')
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

// ─── PROCESS 3: scVI perturbation state inference ───────────────────────────

process SCVI_PERTURBATION {
    tag "${meta.id}"
    label 'process_high'
    publishDir "${params.outdir}/${meta.id}/scvi_perturbation", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(anndata_h5ad)  // AnnData with guide assignments stored in obs
    val batch_key                         // obs column for batch correction (or 'none')
    val guide_key                         // obs column holding guide assignment
    val label_key                         // obs column for cell type labels (or 'Unknown')

    output:
    tuple val(meta), path("scvi_perturbation_emb.h5ad")     , emit: anndata_with_embeddings
    tuple val(meta), path("perturbation_state_summary.csv") , emit: perturbation_summary
    tuple val(meta), path("umap_perturbation.png")          , emit: umap_plot
    path "versions.yml"                                      , emit: versions

    script:
    """
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    export MPLCONFIGDIR=/tmp/matplotlib
    mkdir -p /tmp/numba_cache /tmp/matplotlib

    python3 - <<'PYEOF'
import scanpy as sc
import scvi
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

adata = sc.read_h5ad("${anndata_h5ad}")

# -- scVI training
batch = "${batch_key}" if "${batch_key}" != "none" else None
scvi.model.SCVI.setup_anndata(adata, batch_key=batch)
model = scvi.model.SCVI(adata)
model.train(max_epochs=100, early_stopping=True)
adata.obsm["X_scVI"] = model.get_latent_representation()

# -- scANVI for perturbation label transfer
labels_key = "${label_key}" if "${label_key}" != "Unknown" else None
lvae = scvi.model.SCANVI.from_scvi_model(
    model,
    adata=adata,
    labels_key=labels_key,
    unlabeled_category="Unknown",
)
lvae.train(max_epochs=20)
adata.obsm["X_scANVI"] = lvae.get_latent_representation(adata)

# -- UMAP on scVI latent space
sc.pp.neighbors(adata, use_rep="X_scVI")
sc.tl.umap(adata)

guide_col = "${guide_key}" if "${guide_key}" in adata.obs.columns else None
sc.pl.umap(adata, color=guide_col, save=False)
plt.savefig("umap_perturbation.png", bbox_inches="tight", dpi=150)
plt.close()

# -- Per-perturbation embedding shift vs. non-targeting control
rows = []
if guide_col and guide_col in adata.obs.columns:
    emb         = adata.obsm["X_scVI"]
    ctrl_mask   = adata.obs[guide_col].str.contains(
        "non-target|ctrl|control", case=False, na=False
    )
    ctrl_mean   = emb[ctrl_mask.values].mean(axis=0) if ctrl_mask.any() else emb.mean(axis=0)

    for guide, idx in adata.obs.groupby(guide_col).groups.items():
        g_emb  = emb[adata.obs_names.get_indexer(idx)]
        shift  = float(np.sqrt(((g_emb - ctrl_mean) ** 2).sum(axis=1).mean()))
        rows.append({
            "perturbation"         : guide,
            "n_cells"              : len(idx),
            "mean_embedding_shift" : round(shift, 3),
            "signature_score"      : round(shift, 3),
        })

pd.DataFrame(rows).to_csv("perturbation_state_summary.csv", index=False)

adata.write_h5ad("scvi_perturbation_emb.h5ad")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        scvi_tools: \$(python3 -c "import scvi; print(scvi.__version__)")
        scanpy: \$(python3 -c "import scanpy; print(scanpy.__version__)")
    END_VERSIONS
    """
}

// ─── WORKFLOW ENTRY POINT ───────────────────────────────────────────────────

workflow PERTURB_SEQ_ANALYSIS {

    take:
    fastq_files      // channel: [meta, [fastq1, fastq2, ...]]
    library_csv      // path:    guide library CSV
    design_matrix    // path:    MAGeCK MLE design matrix
    anndata_h5ad     // channel: [meta, .h5ad] with guide assignments in obs
    sample_label     // val:     sample name for MAGeCK count column header
    batch_key        // val:     batch correction column in obs (or 'none')
    guide_key        // val:     guide assignment column in obs
    label_key        // val:     cell type label column (or 'Unknown')

    main:
    // Step 1: guide assignment
    MAGECK_COUNT(fastq_files, library_csv, sample_label)

    // Step 2: hit calling from count table
    MAGECK_MLE(MAGECK_COUNT.out.count_table, design_matrix)

    // Step 3: scVI perturbation state inference
    SCVI_PERTURBATION(anndata_h5ad, batch_key, guide_key, label_key)

    emit:
    count_table             = MAGECK_COUNT.out.count_table
    count_normalized        = MAGECK_COUNT.out.count_normalized
    guide_library_qc        = MAGECK_COUNT.out.qc_summary
    gene_summary            = MAGECK_MLE.out.gene_summary
    hits_table              = MAGECK_MLE.out.hits_table
    anndata_with_embeddings = SCVI_PERTURBATION.out.anndata_with_embeddings
    perturbation_summary    = SCVI_PERTURBATION.out.perturbation_summary
    umap_plot               = SCVI_PERTURBATION.out.umap_plot
}

// ─── Standalone entry workflow ───────────────────────────────────────────────

workflow {
    // Build channels from CLI params
    ch_fastq = Channel.of(
        [[id: params.sample_label ?: 'sample'],
         file(params.fastq ?: 'NO_FASTQ')]
    )
    ch_anndata = Channel.of(
        [[id: params.sample_label ?: 'sample'],
         file(params.anndata_h5ad ?: 'NO_H5AD')]
    )

    PERTURB_SEQ_ANALYSIS(
        ch_fastq,
        file(params.library_csv  ?: 'NO_LIBRARY'),
        file(params.design_matrix ?: 'NO_DESIGN'),
        ch_anndata,
        params.sample_label ?: 'sample',
        params.batch_key    ?: 'none',
        params.guide_key    ?: 'guide',
        params.label_key    ?: 'Unknown',
    )

    PERTURB_SEQ_ANALYSIS.out.hits_table.view { meta, hits ->
        "Hits table written: ${hits}"
    }
    PERTURB_SEQ_ANALYSIS.out.perturbation_summary.view { meta, csv ->
        "Perturbation summary: ${csv}"
    }
}
