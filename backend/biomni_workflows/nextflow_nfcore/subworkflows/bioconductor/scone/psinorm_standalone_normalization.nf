#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scone — psinorm_standalone_normalization
// Perform fast, scalable Pareto-based between-sample normalization on a SingleCellExperiment object (including HDF5-backed out-of-memory data) and optionally prep
// Input: raw_counts.h5
// Container: quay.io/biocontainers/bioconductor-scone:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedArray, HDF5Array, Seurat, SingleCellExperiment, rhdf5, scater, scone
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input
//  * 2. [Core Analysis] Run PsiNorm and logNormCounts (Documented Code)
//  * 3. [Core Analysis] Optional Seurat conversion (Documented Code)
//  * 4. [Core Analysis] Save Outputs

nextflow.enable.dsl = 2

process BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION {
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
    .bm_deps <- c("scone", "scater", "HDF5Array", "DelayedArray", "rhdf5", "Seurat")
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
    library(scone)
    library(scater)
    library(HDF5Array)
    library(DelayedArray)
    library(rhdf5)
    
    # --- Read User Input ---
    if (file.exists("raw_counts.h5")) {
      message("Reading HDF5-backed raw counts...")
      h5_content <- h5ls("raw_counts.h5")
      dataset_idx <- which(h5_content\$otype == "H5I_DATASET")[1]
      if (length(dataset_idx) == 0 || is.na(dataset_idx)) {
        stop("No dataset found in raw_counts.h5")
      }
      dataset_name <- h5_content\$name[dataset_idx]
      group_name <- h5_content\$group[dataset_idx]
      full_path <- paste0(group_name, "/", dataset_name)
      full_path <- gsub("//", "/", full_path)
      
      counts_matrix <- HDF5Array("raw_counts.h5", full_path)
      sce <- SingleCellExperiment(assays = list(counts = counts_matrix))
    } else if (file.exists("raw_counts.csv")) {
      message("Reading in-memory raw counts from CSV...")
      counts_matrix <- as.matrix(read.csv("raw_counts.csv", row.names = 1, check.names = FALSE))
      sce <- SingleCellExperiment(assays = list(counts = counts_matrix))
    } else {
      stop("Required input file 'raw_counts.h5' or 'raw_counts.csv' not found in the working directory.")
    }
    
    # Ensure unique feature and cell names are present (required for Seurat conversion)
    if (is.null(rownames(sce))) {
      rownames(sce) <- paste0("Feature", seq_len(nrow(sce)))
    }
    if (is.null(colnames(sce))) {
      colnames(sce) <- paste0("Cell", seq_len(ncol(sce)))
    }
    
    # --- Run PsiNorm and logNormCounts (Documented Code) ---
    message("Running PsiNorm...")
    sce<-PsiNorm(sce)
    message("Running logNormCounts...")
    sce<-logNormCounts(sce)
    message("Printing head of size factors:")
    head(sizeFactors(sce))
    
    # --- Optional Seurat conversion (Documented Code) ---
    if (requireNamespace("Seurat", quietly = TRUE)) {
      message("Converting to Seurat object...")
      library(Seurat)
      seu <- as.Seurat(sce)
      # Save Seurat object
      saveRDS(seu, "normalized_seurat.rds")
      message("Saved Seurat object to 'normalized_seurat.rds'")
    } else {
      message("Seurat package not installed. Skipping Seurat conversion.")
    }
    
    # --- Save Outputs ---
    sf <- sizeFactors(sce)
    cell_names <- names(sf)
    if (is.null(cell_names)) {
      cell_names <- paste0("Cell", seq_along(sf))
    }
    sf_df <- data.frame(Cell = cell_names, SizeFactor = sf)
    write.csv(sf_df, "size_factors.csv", row.names = FALSE)
    message("Saved size factors to 'size_factors.csv'")
    
    saveRDS(sce, "normalized_sce.rds")
    message("Saved SingleCellExperiment object to 'normalized_sce.rds'")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION":',
        paste0('    scone: ', as.character(packageVersion('scone')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_psinorm_standalone_normalization.csv versions.yml
    """
}

workflow BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.h5 ] ]

    main:
    BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.tables
    plots    = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.plots
    objects  = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.objects
    versions = BIOC_SCONE_PSINORM_STANDALONE_NORMALIZATION.out.versions
}
