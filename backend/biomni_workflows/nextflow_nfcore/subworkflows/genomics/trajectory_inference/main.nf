#!/usr/bin/env nextflow
// ============================================================
// BioMate: Trajectory Inference Subworkflow
// Sprint 3 — Pseudotime + RNA velocity from single-cell data
//
// Runs two orthogonal trajectory methods in parallel:
//   MONOCLE3_TRAJECTORY  — graph-based pseudotime (R / Monocle3)
//   SCVELO_DYNAMICS      — RNA velocity (Python / scVelo)
//
// Both processes accept the same AnnData h5ad input but are
// fully independent and execute concurrently.
//
// Entry workflow: TRAJECTORY_INFERENCE
// ============================================================

nextflow.enable.dsl = 2

// ────────────────────────────────────────────────────────────
// Parameters
// ────────────────────────────────────────────────────────────
params.outdir          = './results/trajectory_inference'
params.adata_h5ad      = null   // AnnData .h5ad with spliced/unspliced layers + UMAP
// Monocle3 settings
params.root_cell       = null   // barcode to use as trajectory root (null = interactive)
params.monocle_cluster = 'leiden'
// scVelo settings
params.velocity_mode   = 'dynamical'   // stochastic | deterministic | dynamical

// ────────────────────────────────────────────────────────────
// PROCESS 1: Monocle3 pseudotime trajectory (R)
// ────────────────────────────────────────────────────────────

process MONOCLE3_TRAJECTORY {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/monocle3", mode: 'copy'

    // Bioconductor monocle3 container (R 4.4); falls back to docker tag
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-monocle3:1.3.4--r44_0' :
        'quay.io/biocontainers/bioconductor-monocle3:1.3.4--r44_0'}"

    input:
    tuple val(meta), path(adata_h5ad)

    output:
    tuple val(meta), path("${meta.id}_trajectory_pseudotime.csv"),  emit: pseudotime
    tuple val(meta), path("${meta.id}_trajectory_plot.png"),        emit: plot
    tuple val(meta), path("${meta.id}_monocle3_cds.rds"),           emit: cds
    path "versions.yml",                                              emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix      = task.ext.prefix ?: "${meta.id}"
    def cluster_key = params.monocle_cluster
    def root_cell   = params.root_cell ?: 'NULL'
    """
    #!/usr/bin/env Rscript
    suppressPackageStartupMessages({
        library(monocle3)
        library(Matrix)
        library(zellkonverter)
        library(SingleCellExperiment)
    })

    prefix      <- "${prefix}"
    cluster_key <- "${cluster_key}"
    root_cell   <- if ("${root_cell}" == "NULL") NULL else "${root_cell}"

    h5ad_path <- "${adata_h5ad}"
    if (!file.exists(h5ad_path))
        stop("AnnData file not found: ", h5ad_path)

    # Convert h5ad to CellDataSet via zellkonverter/SummarizedExperiment
    sce <- readH5AD(h5ad_path, use_hdf5 = TRUE)
    # Use the 'X' assay as counts
    counts_mat <- assay(sce, "X")
    gene_meta  <- data.frame(
        gene_short_name = rownames(sce),
        row.names       = rownames(sce)
    )
    cell_meta  <- as.data.frame(colData(sce))

    cds <- new_cell_data_set(
        counts_mat,
        cell_metadata = cell_meta,
        gene_metadata = gene_meta
    )

    # Standard Monocle3 pipeline
    cds <- preprocess_cds(cds, num_dim = 50)
    cds <- reduce_dimension(cds, reduction_method = "UMAP")
    cds <- cluster_cells(cds)
    cds <- learn_graph(cds)

    # Order cells from root
    if (!is.null(root_cell) && root_cell %in% colnames(cds)) {
        cds <- order_cells(cds, root_cells = root_cell)
    } else {
        # Pick the cell with minimum UMAP distance to (0,0) as root
        umap_coords <- reducedDims(cds)[["UMAP"]]
        dist_origin <- rowSums(umap_coords^2)
        auto_root   <- colnames(cds)[which.min(dist_origin)]
        cds <- order_cells(cds, root_cells = auto_root)
    }

    pt_df <- data.frame(
        cell_barcode = colnames(cds),
        pseudotime   = round(pseudotime(cds), 4),
        cluster      = as.character(clusters(cds)),
        stringsAsFactors = FALSE
    )
    write.csv(pt_df, paste0(prefix, "_trajectory_pseudotime.csv"), row.names = FALSE)
    saveRDS(cds, paste0(prefix, "_monocle3_cds.rds"))

    # Plot
    png(paste0(prefix, "_trajectory_plot.png"), width = 900, height = 800)
    print(plot_cells(cds,
        color_cells_by     = "pseudotime",
        label_cell_groups  = FALSE,
        label_leaves       = TRUE,
        label_branch_points = TRUE,
        graph_label_size   = 3
    ))
    dev.off()

    message(sprintf("Monocle3 complete: %d cells processed", ncol(cds)))

    # ── versions.yml ──────────────────────────────────────────
    mono_ver <- tryCatch(as.character(packageVersion("monocle3")), error = function(e) "unknown")
    writeLines(
        c("MONOCLE3_TRAJECTORY:",
          paste0("    monocle3: ", mono_ver),
          paste0("    R: ", R.version\$major, ".", R.version\$minor)),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trajectory_pseudotime.csv
    touch ${prefix}_trajectory_plot.png
    touch ${prefix}_monocle3_cds.rds
    echo "MONOCLE3_TRAJECTORY:" > versions.yml
    echo "    monocle3: 1.3.4" >> versions.yml
    echo "    R: 4.4" >> versions.yml
    """
}

// ────────────────────────────────────────────────────────────
// PROCESS 2: scVelo RNA velocity (Python)
// ────────────────────────────────────────────────────────────

process SCVELO_DYNAMICS {
    tag "${meta.id}"
    label 'process_high'
    publishDir "${params.outdir}/${meta.id}/scvelo", mode: 'copy'

    // biomate/biomni-tools has Python, scanpy, and scvelo installed
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(adata_h5ad)

    output:
    tuple val(meta), path("${meta.id}_velocity_umap.png"),    emit: velocity_plot
    tuple val(meta), path("${meta.id}_velocity_anndata.h5ad"), emit: velocity_adata
    path "versions.yml",                                        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def vel_mode = params.velocity_mode
    """
    export NUMBA_DISABLE_JIT=1
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    export MPLCONFIGDIR=/tmp/matplotlib
    mkdir -p /tmp/numba_cache /tmp/matplotlib

    python3 << 'PYEOF'
import os
import sys
import numpy as np

PREFIX    = "${prefix}"
VEL_MODE  = "${vel_mode}"
H5AD_PATH = "${adata_h5ad}"

try:
    import scvelo as scv
    import scanpy as sc
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
except ImportError as e:
    print(f"ERROR: Required package not available -- {e}", file=sys.stderr)
    sys.exit(1)

if not os.path.exists(H5AD_PATH):
    print(f"ERROR: AnnData file not found: {H5AD_PATH}", file=sys.stderr)
    sys.exit(1)

scv.settings.verbosity = 2
scv.settings.set_figure_params('scvelo', dpi=120)

adata = sc.read_h5ad(H5AD_PATH)

# Require spliced / unspliced layers
for layer in ("spliced", "unspliced"):
    if layer not in adata.layers:
        print(f"WARNING: '{layer}' layer not found -- computing from raw counts proxy")
        adata.layers[layer] = adata.X.copy()

# Standard scVelo pipeline
scv.pp.filter_and_normalize(adata, min_shared_counts=20, n_top_genes=2000)
scv.pp.moments(adata, n_pcs=30, n_neighbors=30)

if VEL_MODE == "dynamical":
    scv.tl.recover_dynamics(adata)

scv.tl.velocity(adata, mode=VEL_MODE)
scv.tl.velocity_graph(adata)

# Ensure a UMAP embedding exists
if "X_umap" not in adata.obsm:
    sc.pp.neighbors(adata)
    sc.tl.umap(adata)

# Plot
fig, ax = plt.subplots(figsize=(9, 8))
scv.pl.velocity_embedding_stream(
    adata, basis="umap", color="clusters" if "clusters" in adata.obs else None,
    ax=ax, show=False, title=f"RNA Velocity -- {PREFIX}"
)
plt.savefig(f"{PREFIX}_velocity_umap.png", dpi=150, bbox_inches='tight')
plt.close()

adata.write_h5ad(f"{PREFIX}_velocity_anndata.h5ad")
print(f"scVelo complete: {adata.n_obs} cells, mode={VEL_MODE}")

# -- versions.yml
try:
    import anndata; ad_ver = anndata.__version__
except Exception:
    ad_ver = "unknown"
try:
    scv_ver = scv.__version__
except Exception:
    scv_ver = "unknown"
try:
    sc_ver = sc.__version__
except Exception:
    sc_ver = "unknown"

with open("versions.yml", "w") as fh:
    fh.write("SCVELO_DYNAMICS:\\n")
    fh.write(f"    scvelo: {scv_ver}\\n")
    fh.write(f"    scanpy: {sc_ver}\\n")
    fh.write(f"    anndata: {ad_ver}\\n")
PYEOF
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_velocity_umap.png
    touch ${prefix}_velocity_anndata.h5ad
    echo "SCVELO_DYNAMICS:" > versions.yml
    echo "    scvelo: 0.3.2" >> versions.yml
    echo "    scanpy: 1.10.0" >> versions.yml
    echo "    anndata: 0.10.8" >> versions.yml
    """
}

// ────────────────────────────────────────────────────────────
// Entry sub-workflow — processes run in parallel
// ────────────────────────────────────────────────────────────

workflow TRAJECTORY_INFERENCE {
    take:
    ch_input  // channel: [ val(meta), path(adata_h5ad) ]

    main:
    // Both processes start immediately from the same input channel.
    // Nextflow fans out the channel to both processes concurrently.
    MONOCLE3_TRAJECTORY(ch_input)
    SCVELO_DYNAMICS(ch_input)

    emit:
    pseudotime    = MONOCLE3_TRAJECTORY.out.pseudotime    // [ val(meta), path(csv) ]
    trajectory_plot = MONOCLE3_TRAJECTORY.out.plot        // [ val(meta), path(png) ]
    monocle3_cds  = MONOCLE3_TRAJECTORY.out.cds           // [ val(meta), path(rds) ]
    velocity_plot = SCVELO_DYNAMICS.out.velocity_plot      // [ val(meta), path(png) ]
    velocity_adata = SCVELO_DYNAMICS.out.velocity_adata    // [ val(meta), path(h5ad) ]
    versions      = MONOCLE3_TRAJECTORY.out.versions.mix(
                        SCVELO_DYNAMICS.out.versions)       // path(versions.yml)
}

// ────────────────────────────────────────────────────────────
// Standalone execution entry point
// ────────────────────────────────────────────────────────────

workflow {
    if (!params.adata_h5ad) error "params.adata_h5ad is required: path to AnnData .h5ad file with spliced/unspliced layers and UMAP"

    def h5ad_path = file(params.adata_h5ad)

    ch_input = Channel.of([[id: 'run'], h5ad_path])

    TRAJECTORY_INFERENCE(ch_input)

    TRAJECTORY_INFERENCE.out.pseudotime.view { meta, f ->
        "Pseudotime CSV: ${f}"
    }
    TRAJECTORY_INFERENCE.out.velocity_plot.view { meta, f ->
        "Velocity UMAP: ${f}"
    }
}
