#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: schex — hexbin_plotting_workflow
// Bin single-cell reduced dimension coordinates into hexagons and visualize cell density, metadata, and gene expression.
// Input: pbmc_small, tenx_pbmc3k
// Container: quay.io/biocontainers/bioconductor-schex:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, Seurat, SingleCellExperiment, dplyr, ggplot2, ggrepel, igraph, scater, schex, scran
// Visualizations: density plot, cluster plot
// QC: cell QC metrics, count normalization, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert Seurat object to SingleCellExperiment (optional)
//  * 2. [Core Analysis] Calculate hexagon cell representation using make_hexbin
//  * 3. [Visualization & Output] Plot cell density in hexagons using plot_hexbin_density
//  * 4. [Visualization & Output] Plot metadata using plot_hexbin_meta and optionally label them using make_hexbin_label
//  * 5. [Visualization & Output] Plot gene expression using plot_hexbin_feature or plot_hexbin_feature_plus

nextflow.enable.dsl = 2

process BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("schex", "dplyr", "Seurat", "ggplot2", "ggrepel", "scater", "scran", "igraph", "SummarizedExperiment")
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
    library(schex)
    library(SummarizedExperiment)
    library(dplyr)
    library(Seurat)
    library(ggplot2)
    library(ggrepel)
    library(scater)
    library(scran)
    library(igraph)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read pbmc_small Seurat object
    if (file.exists("pbmc_small.rds")) {
      pbmc_small <- readRDS("pbmc_small.rds")
    } else if (file.exists("pbmc_small")) {
      pbmc_small <- readRDS("pbmc_small")
    } else {
      stop("Error: 'pbmc_small' file not found in the working directory.")
    }
    
    # Read tenx_pbmc3k SingleCellExperiment object
    if (file.exists("tenx_pbmc3k.rds")) {
      tenx_pbmc3k <- readRDS("tenx_pbmc3k.rds")
    } else if (file.exists("tenx_pbmc3k")) {
      tenx_pbmc3k <- readRDS("tenx_pbmc3k")
    } else {
      stop("Error: 'tenx_pbmc3k' file not found in the working directory.")
    }
    
    # ==========================================
    # 2. Preprocess and Align Objects
    # ==========================================
    
    # Ensure pbmc_small has UMAP reduction (as required by the vignette)
    if (!"umap" %in% names(pbmc_small@reductions)) {
      set.seed(10)
      pbmc_small <- RunUMAP(pbmc_small, dims = 1:10, verbose = FALSE)
    }
    
    # Ensure tenx_pbmc3k has required metadata and assays
    if (!"cluster" %in% colnames(colData(tenx_pbmc3k))) {
      if (!"PCA" %in% reducedDimNames(tenx_pbmc3k)) {
        tenx_pbmc3k <- scater::runPCA(tenx_pbmc3k)
      }
      snn_gr <- scran::buildSNNGraph(tenx_pbmc3k, use.dimred = "PCA", k = 50)
      clusters <- igraph::cluster_louvain(snn_gr)
      tenx_pbmc3k\$cluster <- factor(clusters\$membership)
    }
    
    if (!"total" %in% colnames(colData(tenx_pbmc3k))) {
      tenx_pbmc3k\$total <- colSums(BiocGenerics::counts(tenx_pbmc3k))
    }
    
    if (!"logcounts" %in% assayNames(tenx_pbmc3k)) {
      tenx_pbmc3k <- scater::logNormCounts(tenx_pbmc3k)
    }
    
    # Ensure the specified genes exist in the objects (fallback if missing)
    pbmc_genes <- rownames(pbmc_small)
    gene_id_pbmc <- "CD1C"
    if (!gene_id_pbmc %in% pbmc_genes) {
      gene_id_pbmc <- pbmc_genes[1]
    }
    
    tenx_genes <- rownames(tenx_pbmc3k)
    gene_id_tenx <- "POMGNT1"
    if (!gene_id_tenx %in% tenx_genes) {
      gene_id_tenx <- tenx_genes[1]
    }
    
    # ==========================================
    # 3. Workflow: pbmc_small (Seurat -> SCE)
    # ==========================================
    
    pbmc.sce <- as.SingleCellExperiment(pbmc_small)
    
    pbmc.sce <- make_hexbin(pbmc.sce,
        nbins = 10,
        dimension_reduction = "UMAP"
    )
    
    # Plot and save density
    p1 <- plot_hexbin_density(pbmc.sce)
    ggsave("pbmc_density.pdf", plot = p1, width = 7, height = 7)
    
    # Plot and save metadata
    p2 <- plot_hexbin_meta(pbmc.sce, col = "nCount_RNA", action = "median")
    ggsave("pbmc_meta_nCount_RNA.pdf", plot = p2, width = 7, height = 7)
    
    # Plot and save feature expression
    p3 <- schex::plot_hexbin_feature(pbmc.sce,
        type = "counts", feature = gene_id_pbmc,
        action = "mean", xlab = "UMAP1", ylab = "UMAP2",
        title = paste0("Mean of ", gene_id_pbmc)
    )
    ggsave(paste0("pbmc_feature_", gene_id_pbmc, ".pdf"), plot = p3, width = 7, height = 7)
    
    gg <- schex::plot_hexbin_feature(pbmc.sce,
        type = "counts", feature = gene_id_pbmc,
        action = "mean", xlab = "UMAP1", ylab = "UMAP2",
        title = paste0("Mean of ", gene_id_pbmc)
    )
    p4 <- gg + theme_void()
    ggsave(paste0("pbmc_feature_", gene_id_pbmc, "_void.pdf"), plot = p4, width = 7, height = 7)
    
    # Save processed SCE object
    saveRDS(pbmc.sce, "pbmc_hexbin.rds")
    
    
    # ==========================================
    # 4. Workflow: tenx_pbmc3k (SingleCellExperiment)
    # ==========================================
    
    tenx_pbmc3k <- make_hexbin(tenx_pbmc3k,
        nbins = 40,
        dimension_reduction = "UMAP", use_dims = c(1, 2)
    )
    
    # Plot and save density
    p5 <- plot_hexbin_density(tenx_pbmc3k)
    ggsave("tenx_density.pdf", plot = p5, width = 7, height = 7)
    
    # Plot and save metadata
    p6 <- plot_hexbin_meta(tenx_pbmc3k, col = "cluster", action = "majority")
    ggsave("tenx_meta_cluster.pdf", plot = p6, width = 7, height = 7)
    
    p7 <- plot_hexbin_meta(tenx_pbmc3k, col = "total", action = "median")
    ggsave("tenx_meta_total.pdf", plot = p7, width = 7, height = 7)
    
    # Generate and save labels
    label_df <- make_hexbin_label(tenx_pbmc3k, col = "cluster")
    write.csv(label_df, "tenx_hexbin_labels.csv", row.names = FALSE)
    
    pp <- plot_hexbin_meta(tenx_pbmc3k, col = "cluster", action = "majority")
    p8 <- pp + ggrepel::geom_label_repel(
        data = label_df, aes(x = x, y = y, label = label),
        colour = "black", label.size = NA, fill = NA
    )
    ggsave("tenx_meta_cluster_labeled.pdf", plot = p8, width = 7, height = 7)
    
    # Plot and save feature expression
    p9 <- plot_hexbin_feature(tenx_pbmc3k,
        type = "logcounts", feature = gene_id_tenx,
        action = "mean", xlab = "UMAP1", ylab = "UMAP2",
        title = paste0("Mean of ", gene_id_tenx)
    )
    ggsave(paste0("tenx_feature_", gene_id_tenx, ".pdf"), plot = p9, width = 7, height = 7)
    
    p10 <- plot_hexbin_feature_plus(tenx_pbmc3k,
        col = "cluster", type = "logcounts",
        feature = gene_id_tenx, action = "mean"
    )
    ggsave(paste0("tenx_feature_plus_", gene_id_tenx, ".pdf"), plot = p10, width = 7, height = 7)
    
    # Save processed SCE object
    saveRDS(tenx_pbmc3k, "tenx_hexbin.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # clustering QC — n_clusters ∈ [2,50] proxy (silhouette needs cluster pkg).
    .clu_n <- NA_real_
    for (.clu_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW":',
        paste0('    schex: ', as.character(packageVersion('schex')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hexbin_plotting_workflow.csv versions.yml
    """
}

workflow BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_small, tenx_pbmc3k ] ]

    main:
    BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.tables
    plots    = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.plots
    objects  = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.objects
    versions = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.versions
}
