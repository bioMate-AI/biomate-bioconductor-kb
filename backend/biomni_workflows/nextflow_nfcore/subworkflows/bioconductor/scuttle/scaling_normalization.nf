#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scuttle — scaling_normalization
// Perform scaling normalization on single-cell RNA-seq data using median-based, pooling-based (deconvolution), or spike-in-based methods to remove cell-specific t
// Input: sce
// Container: quay.io/biocontainers/bioconductor-scuttle:1.20.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scran, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scran, scuttle
// QC: clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute median-based size factors using medianSizeFactors
//  * 2. [Core Analysis] Perform pooling normalization by first clustering cells (using scran::quickCluster or metadata) and then computing pooled size fac
//  * 3. [Core Analysis] Alternatively, compute spike-in-based size factors using computeSpikeFactors if spike-in controls are available

nextflow.enable.dsl = 2

process BIOC_SCUTTLE_SCALING_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("SingleCellExperiment", "scran", "scuttle")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(scuttle)
    library(scran)
    
    # Read user input
    # The pipeline reads the SingleCellExperiment object 'sce' from the working directory.
    sce <- readRDS("sce.rds")
    
    # Open a text file to log the summaries of the size factors
    sink("normalization_summaries.txt")
    
    # 1. Compute median-based size factors using medianSizeFactors
    cat("=== Median-based Size Factors ===\n")
    print(summary(medianSizeFactors(sce)))
    cat("\n")
    
    # 2. Perform pooling normalization by first clustering cells and then computing pooled size factors
    cat("=== Pooling Normalization (quickCluster) ===\n")
    clusters <- quickCluster(sce)
    sce <- computePooledFactors(sce, clusters=clusters)
    print(summary(sizeFactors(sce)))
    cat("\n")
    
    # Save the primary normalized object
    saveRDS(sce, "sce_normalized.rds")
    
    # Optional sub-step: pooling using metadata (level1class) if available
    cat("=== Pooling Normalization (level1class) ===\n")
    tryCatch({
      sce_meta <- computePooledFactors(sce, clusters=sce\$level1class)
      print(summary(sizeFactors(sce_meta)))
      saveRDS(sce_meta, "sce_normalized_level1class.rds")
    }, error = function(e) {
      cat("Skipped level1class pooling normalization: ", e\$message, "\n")
    })
    cat("\n")
    
    # 3. Compute spike-in-based size factors using computeSpikeFactors if ERCC controls are available
    cat("=== Spike-in Normalization (ERCC) ===\n")
    tryCatch({
      sce2 <- computeSpikeFactors(sce, "ERCC")
      print(summary(sizeFactors(sce2)))
      saveRDS(sce2, "sce_spike_normalized.rds")
    }, error = function(e) {
      cat("Skipped spike-in normalization: ", e\$message, "\n")
    })
    
    # Close the log file
    sink()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_SCUTTLE_SCALING_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCUTTLE_SCALING_NORMALIZATION":',
        paste0('    scuttle: ', as.character(packageVersion('scuttle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scaling_normalization.csv versions.yml
    """
}

workflow BIOC_SCUTTLE_SCALING_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_SCUTTLE_SCALING_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.tables
    plots    = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.plots
    objects  = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.objects
    versions = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.versions
}
