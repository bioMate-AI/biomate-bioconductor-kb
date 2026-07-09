#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nebulosa — single_cell_experiment_density
// Perform gene-weighted density estimation and visualization on a SingleCellExperiment object.
// Input: pbmc3k_filtered_gene_bc_matrices.tar.gz
// Container: quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0
// R packages: BiocFileCache, DropletUtils, ggplot2, Nebulosa, patchwork, scater, scran, Seurat
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: density plot
// QC: per-cell QC metrics, low-count filtering, cell QC metrics, highly-variable feature selection, clustering QC

nextflow.enable.dsl = 2

process BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BiocFileCache", "DropletUtils", "ggplot2", "Nebulosa", "patchwork", "scater", "scran", "Seurat")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library("Nebulosa")
    library("scater")
    library("scran")
    library("DropletUtils")
    library("patchwork")
    library("ggplot2")
    
    # --- Import 10X data into a SingleCellExperiment object ---
    # Read the local file from the working directory as specified
    untar("pbmc3k_filtered_gene_bc_matrices.tar.gz", exdir = tempdir())
    pbmc <- read10xCounts(file.path(tempdir(),
      "filtered_gene_bc_matrices",
      "hg19"
    ))
    
    rownames(pbmc) <- uniquifyFeatureNames(rowData(pbmc)[["ID"]],
                                           rowData(pbmc)[["Symbol"]])
    
    # --- Pre-process and filter features and cells ---
    i <- rowSums(counts(pbmc) > 0)
    is_expressed <- i > 3
    pbmc <- pbmc[is_expressed, ]
    
    i <- colSums(counts(pbmc) > 0)
    is_expressed <- i > 200
    pbmc <- pbmc[,is_expressed]
    
    is_mito <- grepl("^MT-", rownames(pbmc))
    qcstats <- perCellQCMetrics(pbmc, subsets = list(Mito = is_mito))
    qcfilter <- quickPerCellQC(qcstats, percent_subsets = c("subsets_Mito_percent"))
    
    # --- Normalize data using log-transformation ---
    logcounts(pbmc) <- log1p(counts(pbmc) / colSums(counts(pbmc)) * 1e4)
    
    # --- Identify highly variable genes and perform PCA and UMAP ---
    dec <- modelGeneVar(pbmc)
    top_hvgs <- getTopHVGs(dec, n = 3000)
    
    set.seed(66)
    pbmc <- runPCA(pbmc, scale = TRUE, subset_row = top_hvgs)
    
    pbmc <- runUMAP(pbmc, dimred = "PCA")
    
    # --- Cluster cells using SNN graph and Louvain clustering ---
    g <- buildSNNGraph(pbmc, k = 10, use.dimred = "PCA")
    clust <- igraph::cluster_louvain(g)\$membership
    colLabels(pbmc) <- factor(clust)
    
    # --- Visualize single-gene density and multi-gene joint ---
    # Plot 1: CD4 single-gene density
    p1 <- plot_density(pbmc, "CD4")
    ggsave("density_CD4.pdf", plot = p1, width = 8, height = 6)
    
    # Plot 2: CD8A and CCR7 density
    p3 <- plot_density(pbmc, c("CD8A", "CCR7"))
    p3_layout <- p3 + plot_layout(ncol = 1)
    ggsave("density_CD8A_CCR7.pdf", plot = p3_layout, width = 8, height = 10)
    
    # Plot 3: CD8A and CCR7 joint density
    p4 <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE)
    p4_layout <- p4 + plot_layout(ncol = 1)
    ggsave("density_CD8A_CCR7_joint.pdf", plot = p4_layout, width = 8, height = 14)
    
    # Plot 4: Extracting the joint density plot from the list
    p_list <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE, combine = FALSE)
    p_joint_single <- p_list[[length(p_list)]]
    ggsave("density_CD8A_CCR7_joint_single.pdf", plot = p_joint_single, width = 8, height = 6)
    
    # Save outputs
    # Save the processed SingleCellExperiment object
    saveRDS(pbmc, "pbmc_processed.rds")
    
    # Save cell metadata including cluster labels to CSV
    metadata_df <- as.data.frame(colData(pbmc))
    write.csv(metadata_df, "cell_metadata.csv", row.names = TRUE)
    
    # Save highly variable genes to CSV
    write.csv(data.frame(Gene = top_hvgs), "highly_variable_genes.csv", row.names = FALSE)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # per-cell QC metrics — alias semantics to cell QC metrics; reports
    # cells-flagged fraction by detecting library-size outliers via MAD.
    .pcqc_outlier_frac <- NA_real_; .pcqc_files <- character(0)
    for (.pcqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pcqc_obj <- tryCatch(readRDS(.pcqc_rds), error = function(e) NULL)
      .pcqc_mat <- if (is.matrix(.pcqc_obj) || is.data.frame(.pcqc_obj)) .pcqc_obj else NULL
      if (!is.null(.pcqc_mat) && ncol(.pcqc_mat) >= 10) {
        .pcqc_lib <- suppressWarnings(colSums(as.matrix(.pcqc_mat), na.rm = TRUE))
        if (length(.pcqc_lib) > 0 && all(is.finite(.pcqc_lib))) {
          .pcqc_med <- median(.pcqc_lib); .pcqc_mad <- mad(.pcqc_lib)
          .pcqc_outlier_frac <- if (.pcqc_mad > 0) mean(abs(.pcqc_lib - .pcqc_med) > 3 * .pcqc_mad) else 0
          .pcqc_files <- c(.pcqc_files, .pcqc_rds); break
        }
      }
    }
    .gates_by_label[["per-cell QC metrics"]] <- list(
      gate_row = "bioc_per_cell_qc_outliers",
      metric_name = "cells_flagged_outlier_fraction",
      metric_value = if (is.finite(.pcqc_outlier_frac)) round(.pcqc_outlier_frac, 4) else NA_real_,
      passes = isTRUE(is.finite(.pcqc_outlier_frac) && .pcqc_outlier_frac <= 0.1),
      status = if (is.finite(.pcqc_outlier_frac)) "computed (nmads=3 on lib sizes; scater::isOutlier proxy)"
               else "not_computed (no cell-count matrix .rds artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    # clustering QC — n_clusters ∈ [2,50] proxy (silhouette needs cluster pkg).
    .clu_n <- NA_real_
    for (.clu_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .clu_obj <- tryCatch(readRDS(.clu_rds), error = function(e) NULL)
      .clu_v <- NULL
      if (!is.null(.clu_obj)) {
        if (inherits(.clu_obj, "SingleCellExperiment")) {
          .clu_cd <- tryCatch(colData(.clu_obj), error = function(e) NULL)
          if (!is.null(.clu_cd)) {
            .clu_col <- intersect(c("cluster","clusters","seurat_clusters","label"), colnames(.clu_cd))
            if (length(.clu_col) > 0) .clu_v <- .clu_cd[[.clu_col[1]]]
          }
        } else if (inherits(.clu_obj, "Seurat")) {
          .clu_md <- tryCatch(.clu_obj@meta.data, error = function(e) NULL)
          if (!is.null(.clu_md)) {
            .clu_col <- intersect(c("seurat_clusters","cluster","clusters"), colnames(.clu_md))
            if (length(.clu_col) > 0) .clu_v <- .clu_md[[.clu_col[1]]]
          }
        }
      }
      if (!is.null(.clu_v) && length(.clu_v) > 0) {
        .clu_n <- length(unique(as.character(.clu_v[!is.na(.clu_v)]))); break
      }
    }
    .gates_by_label[["clustering QC"]] <- list(
      gate_row = "bioc_clustering_qc",
      metric_name = "n_clusters",
      metric_value = .clu_n,
      passes = isTRUE(is.finite(.clu_n) && .clu_n >= 2 && .clu_n <= 50),
      status = if (is.finite(.clu_n)) paste0("computed (n_clusters=", .clu_n, ")")
               else "not_computed (no SCE/Seurat with cluster column present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY",
      domain  = "bioconductor",
      declared_qc_steps = c("per-cell QC metrics", "low-count filtering", "cell QC metrics", "highly-variable feature selection", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY":',
        paste0('        nebulosa: ', as.character(packageVersion("nebulosa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_experiment_density.csv versions.yml
    """
}

workflow BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc3k_filtered_gene_bc_matrices.tar.gz ] ]

    main:
    BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY(ch_input)

    emit:
    tables   = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.tables
    plots    = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.plots
    objects  = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.objects
    versions = BIOC_NEBULOSA_SINGLE_CELL_EXPERIMENT_DENSITY.out.versions
}
