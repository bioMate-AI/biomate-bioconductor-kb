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
params.mock_mode       = true
// Real input (ignored in mock mode)
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
    def mock        = params.mock_mode
    def cluster_key = params.monocle_cluster
    def root_cell   = params.root_cell ?: 'NULL'
    """
    #!/usr/bin/env Rscript
    suppressPackageStartupMessages({
        library(monocle3)
        library(Matrix)
    })

    mock_mode   <- ${mock}
    prefix      <- "${prefix}"
    cluster_key <- "${cluster_key}"
    root_cell   <- if ("${root_cell}" == "NULL") NULL else "${root_cell}"

    if (mock_mode) {
        # ── Mock mode ──────────────────────────────────────────
        # 200 cells arranged along a linear trajectory (0–100 pseudotime)
        set.seed(2024)
        n_cells     <- 200
        barcodes    <- paste0("CELL_", seq_len(n_cells))

        # Simulate a noisy linear trajectory
        true_pt     <- sort(runif(n_cells, 0, 100))
        noise       <- rnorm(n_cells, 0, 3)
        pseudotime  <- pmax(0, true_pt + noise)

        # Assign cells to 4 clusters along the trajectory
        cluster_labels <- cut(true_pt, breaks = 4,
                              labels = paste0("Cluster_", 1:4))

        pt_df <- data.frame(
            cell_barcode = barcodes,
            pseudotime   = round(pseudotime, 4),
            cluster      = as.character(cluster_labels),
            stringsAsFactors = FALSE
        )

        write.csv(pt_df, paste0(prefix, "_trajectory_pseudotime.csv"), row.names = FALSE)

        # Build a minimal CellDataSet for the RDS output
        # (sparse count matrix: 50 genes × 200 cells)
        n_genes <- 50
        gene_ids <- paste0("GENE_", seq_len(n_genes))
        counts_mat <- Matrix::rsparsematrix(n_genes, n_cells, density = 0.3,
                                            rand.x = function(n) rpois(n, 5))
        rownames(counts_mat) <- gene_ids
        colnames(counts_mat) <- barcodes

        gene_meta   <- data.frame(gene_short_name = gene_ids, row.names = gene_ids)
        cell_meta   <- data.frame(
            cell_barcode = barcodes,
            cluster      = as.character(cluster_labels),
            pseudotime   = round(pseudotime, 4),
            row.names    = barcodes,
            stringsAsFactors = FALSE
        )

        cds <- new_cell_data_set(
            counts_mat,
            cell_metadata = cell_meta,
            gene_metadata = gene_meta
        )
        cds <- preprocess_cds(cds, num_dim = 10)
        cds <- reduce_dimension(cds, reduction_method = "UMAP")
        cds <- cluster_cells(cds)
        cds <- learn_graph(cds)

        saveRDS(cds, paste0(prefix, "_monocle3_cds.rds"))

        # ── Simple trajectory plot (base graphics) ─────────────
        umap_coords <- reducedDims(cds)[["UMAP"]]
        png(paste0(prefix, "_trajectory_plot.png"), width = 800, height = 700)
        par(mar = c(5, 5, 4, 2))
        color_scale <- colorRampPalette(c("#440154", "#31688E", "#35B779", "#FDE725"))(101)
        pt_norm     <- round(pseudotime / max(pseudotime) * 100) + 1
        plot(
            umap_coords[, 1], umap_coords[, 2],
            col  = color_scale[pt_norm],
            pch  = 20, cex = 0.8,
            main = sprintf("Monocle3 Trajectory\\n%s (%d cells, mock)", prefix, n_cells),
            xlab = "UMAP_1", ylab = "UMAP_2"
        )
        legend("topright", legend = c("0 (root)", "50", "100 (tip)"),
               col = color_scale[c(1, 51, 101)], pch = 20, title = "Pseudotime")
        dev.off()

        message(sprintf("Monocle3 mock complete: %d cells, pseudotime 0–%.1f",
                        n_cells, max(pseudotime)))

    } else {
        # ── Live mode ──────────────────────────────────────────
        h5ad_path <- "${adata_h5ad}"
        if (!file.exists(h5ad_path))
            stop("AnnData file not found: ", h5ad_path)

        # Convert h5ad to CellDataSet via zellkonverter/SummarizedExperiment
        suppressPackageStartupMessages({
            library(zellkonverter)
            library(SingleCellExperiment)
        })

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

        message(sprintf("Monocle3 live: %d cells processed", ncol(cds)))
    }

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
    container 'biomate/biomni-tools:latest'

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
    def mock     = params.mock_mode
    def vel_mode = params.velocity_mode
    """
    export NUMBA_DISABLE_JIT=1
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    export MPLCONFIGDIR=/tmp/matplotlib
    mkdir -p /tmp/numba_cache /tmp/matplotlib

    python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

PREFIX    = "${prefix}"
MOCK_MODE = ${mock ? 'True' : 'False'}
VEL_MODE  = "${vel_mode}"
H5AD_PATH = "${adata_h5ad}"

# ── Mock mode ─────────────────────────────────────────────────
if MOCK_MODE:
    import anndata as ad
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.cm as cm

    np.random.seed(2024)
    N_CELLS = 200
    N_GENES = 50

    barcodes  = [f"CELL_{i+1}" for i in range(N_CELLS)]
    gene_ids  = [f"GENE_{j+1}" for j in range(N_GENES)]

    # Simulate spliced / unspliced counts (Poisson noise along a trajectory)
    trajectory = np.linspace(0, 1, N_CELLS)
    spliced    = np.random.poisson(
        lam=np.outer(trajectory * 8 + 1, np.ones(N_GENES)) *
            np.random.uniform(0.5, 2.0, N_GENES),
    ).astype(np.float32)
    unspliced  = np.random.poisson(
        lam=np.outer(np.gradient(trajectory) * 5 + 0.5, np.ones(N_GENES)) *
            np.random.uniform(0.3, 1.5, N_GENES),
    ).astype(np.float32)

    # 2-D UMAP coordinates arranged along a curve
    angle     = np.linspace(0, np.pi, N_CELLS)
    umap_1    = np.cos(angle) + np.random.normal(0, 0.08, N_CELLS)
    umap_2    = np.sin(angle) + np.random.normal(0, 0.08, N_CELLS)
    umap_emb  = np.column_stack([umap_1, umap_2])

    # Synthetic velocity vectors tangent to the curve
    vel_1     = -np.sin(angle) + np.random.normal(0, 0.05, N_CELLS)
    vel_2     =  np.cos(angle) + np.random.normal(0, 0.05, N_CELLS)
    scale     = np.random.uniform(0.05, 0.15, N_CELLS)
    velocity  = np.column_stack([vel_1 * scale, vel_2 * scale])

    # Build AnnData
    adata = ad.AnnData(
        X    = spliced,
        obs  = {"cell_barcode": barcodes,
                "pseudotime":   trajectory * 100},
        var  = {"gene_ids": gene_ids},
    )
    adata.obs_names  = barcodes
    adata.var_names  = gene_ids
    adata.layers["spliced"]   = spliced
    adata.layers["unspliced"] = unspliced
    adata.obsm["X_umap"]      = umap_emb
    adata.obsm["velocity_umap"] = velocity
    adata.uns["velocity_mode"]  = f"{VEL_MODE}_mock"

    # ── UMAP + velocity arrow plot ────────────────────────────
    fig, ax = plt.subplots(figsize=(8, 7))
    sc = ax.scatter(
        umap_emb[:, 0], umap_emb[:, 1],
        c=trajectory * 100, cmap="plasma", s=18, alpha=0.85, zorder=2
    )
    plt.colorbar(sc, ax=ax, label="Pseudotime (mock)")

    # Subsample arrows every 10 cells to keep the plot readable
    step = max(1, N_CELLS // 20)
    ax.quiver(
        umap_emb[::step, 0], umap_emb[::step, 1],
        velocity[::step, 0], velocity[::step, 1],
        color='black', alpha=0.6, scale=2.5, width=0.003,
        zorder=3, label='RNA velocity'
    )

    ax.set_title(f"scVelo RNA Velocity\\n{PREFIX} ({N_CELLS} cells, mock mode)", fontsize=13)
    ax.set_xlabel("UMAP_1")
    ax.set_ylabel("UMAP_2")
    ax.legend(loc='upper right', fontsize=9)
    plt.tight_layout()
    plt.savefig(f"{PREFIX}_velocity_umap.png", dpi=150, bbox_inches='tight')
    plt.close()

    # Save AnnData
    adata.write_h5ad(f"{PREFIX}_velocity_anndata.h5ad")
    print(f"scVelo mock complete: {N_CELLS} cells, {N_GENES} genes")

# ── Live mode ─────────────────────────────────────────────────
else:
    try:
        import scvelo as scv
        import scanpy as sc
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError as e:
        print(f"ERROR: Required package not available — {e}", file=sys.stderr)
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
            print(f"WARNING: '{layer}' layer not found — computing from raw counts proxy")
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
        ax=ax, show=False, title=f"RNA Velocity — {PREFIX}"
    )
    plt.savefig(f"{PREFIX}_velocity_umap.png", dpi=150, bbox_inches='tight')
    plt.close()

    adata.write_h5ad(f"{PREFIX}_velocity_anndata.h5ad")
    print(f"scVelo live complete: {adata.n_obs} cells, mode={VEL_MODE}")

# ── versions.yml ─────────────────────────────────────────────
try:
    import anndata; ad_ver = anndata.__version__
except Exception:
    ad_ver = "unknown"
try:
    import scvelo; scv_ver = scvelo.__version__
except Exception:
    scv_ver = "mock"
try:
    import scanpy; sc_ver = scanpy.__version__
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
    def h5ad_path = params.adata_h5ad
        ? file(params.adata_h5ad)
        : file('NO_FILE')

    ch_input = Channel.of([[id: 'run'], h5ad_path])

    TRAJECTORY_INFERENCE(ch_input)

    TRAJECTORY_INFERENCE.out.pseudotime.view { meta, f ->
        "Pseudotime CSV: ${f}"
    }
    TRAJECTORY_INFERENCE.out.velocity_plot.view { meta, f ->
        "Velocity UMAP: ${f}"
    }
}
