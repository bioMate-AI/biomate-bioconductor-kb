#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scran — quick_clustering_and_normalization
// Perform quick clustering to assist in cluster-based normalization factor calculation and subsequent subclustering.
// Input: sce.ready
// Container: quay.io/biocontainers/bioconductor-scran:1.38.0--r45ha27e39d_0
// R packages: SingleCellExperiment, bluster, knitr, pheatmap, scater, scran, scRNAseq, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scran, scuttle
// QC: cell QC metrics, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate quick-and-dirty clusters using quickCluster()
//  * 2. [Core Analysis] Compute size factors within clusters using computeSumFactors()
//  * 3. [Core Analysis] Perform subclustering within identified clusters using quickSubCluster()

nextflow.enable.dsl = 2

process BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("SingleCellExperiment", "bluster", "knitr", "pheatmap", "scater", "scran", "scRNAseq", "scuttle")
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
    library(scran)
    library(scuttle)
    
    # 1. Read the input SingleCellExperiment object
    if (!file.exists("sce.ready")) {
      stop("Error: Input file 'sce.ready' not found in the working directory.")
    }
    
    message("Reading input SingleCellExperiment object...")
    sce.ready <- readRDS("sce.ready")
    
    # 2. Perform quick clustering
    message("Performing quick clustering...")
    clusters <- quickCluster(sce.ready)
    
    # Save quick clustering results
    clusters_df <- data.frame(
      Cell = colnames(sce.ready),
      Cluster = clusters,
      stringsAsFactors = FALSE
    )
    write.csv(clusters_df, "quick_clusters.csv", row.names = FALSE)
    
    # 3. Compute size factors within clusters
    message("Computing sum factors...")
    sce.normed <- computeSumFactors(sce.ready, clusters=clusters)
    
    # Extract and save size factors summary
    sf_summary <- summary(sizeFactors(sce.normed))
    message("Size factors summary:")
    print(sf_summary)
    
    sink("size_factors_summary.txt")
    print(sf_summary)
    sink()
    
    # Save the normalized SingleCellExperiment object
    saveRDS(sce.normed, "sce_normed.rds")
    
    # 4. Perform subclustering within identified clusters
    message("Performing subclustering...")
    subout <- quickSubCluster(sce.ready, groups=clusters)
    
    # Extract and save subcluster table
    subcluster_table <- table(metadata(subout)\$subcluster)
    message("Subcluster table:")
    print(subcluster_table)
    
    subcluster_df <- as.data.frame(subcluster_table)
    colnames(subcluster_df) <- c("Subcluster", "CellCount")
    write.csv(subcluster_df, "subcluster_table.csv", row.names = FALSE)
    
    # Save the subclustering output object
    saveRDS(subout, "subout.rds")
    
    message("Workflow completed successfully. Outputs saved: 'quick_clusters.csv', 'sce_normed.rds', 'size_factors_summary.txt', 'subcluster_table.csv', 'subout.rds'.")
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
      process = "BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION":',
        paste0('    scran: ', as.character(packageVersion('scran')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_clustering_and_normalization.csv versions.yml
    """
}

workflow BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.ready ] ]

    main:
    BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.tables
    plots    = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.plots
    objects  = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.objects
    versions = BIOC_SCRAN_QUICK_CLUSTERING_AND_NORMALIZATION.out.versions
}
