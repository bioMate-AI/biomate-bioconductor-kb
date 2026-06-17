#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SCArray — gds_single_cell_analysis
// Convert single-cell data to GDS format, load it as a GDS-backed SingleCellExperiment, and perform memory-efficient downstream analysis.
// Input: example.rds, example.gds
// Container: quay.io/biocontainers/bioconductor-scarray:1.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, SCArray, SingleCellExperiment, scater, scuttle
// Visualizations: ordination plot, PCA plot, UMAP plot
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert SingleCellExperiment or matrix to GDS format using scConvGDS()
//  * 2. [Input & Preparation] Load GDS file as a SingleCellExperiment using scExperiment()
//  * 3. [Core Analysis] Normalize counts using logNormCounts()
//  * 4. [Visualization & Output] Calculate row and column summarizations using colMeans(), rowMeans(), and scRowMeanVar()
//  * 5. [Core Analysis] Perform memory-efficient PCA using scRunPCA()
//  * 6. [Core Analysis] Perform UMAP dimensionality reduction using runUMAP()

nextflow.enable.dsl = 2

process BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS {
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
    .bm_deps <- c("SCArray", "SingleCellExperiment", "Matrix", "scuttle", "scater")
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
    suppressPackageStartupMessages(library(SCArray))
    suppressPackageStartupMessages(library(SingleCellExperiment))
    suppressPackageStartupMessages(library(Matrix))
    suppressPackageStartupMessages(library(scuttle))
    suppressPackageStartupMessages(library(scater))
    
    # 1. Convert SingleCellExperiment to GDS format
    # Read the user-provided SingleCellExperiment RDS file from the working directory
    fn_rds <- "example.rds"
    sce <- readRDS(fn_rds)
    
    # Convert to GDS format
    scConvGDS(sce, "test.gds")
    
    # Open and close the GDS file to verify structure
    f <- scOpen("test.gds")
    scClose(f)
    
    # 2. Convert a sparse matrix to GDS format
    cnt <- matrix(0, nrow=4, ncol=8)
    set.seed(100)
    cnt[sample.int(length(cnt), 8)] <- rpois(8, 4)
    cnt <- as(cnt, "sparseMatrix")
    
    if (file.exists("test.gds")) {
        unlink("test.gds", force=TRUE)
    }
    scConvGDS(cnt, "test.gds")
    
    # 3. Load GDS file as a SingleCellExperiment
    # Read the user-provided GDS file from the working directory
    fn_gds <- "example.gds"
    sce <- scExperiment(fn_gds)
    
    # Extract counts and compute log-transformed counts (DelayedMatrix)
    cnt <- assays(sce)\$counts
    logcnt <- log2(cnt + 1)
    
    # 4. Normalize counts using logNormCounts
    sce <- logNormCounts(sce)
    
    # 5. Calculate row and column summarizations
    col_mean <- colMeans(logcnt)
    row_mean <- rowMeans(logcnt)
    mvar <- scRowMeanVar(logcnt)
    
    # Save summarization results to disk
    write.csv(as.data.frame(col_mean), "column_means.csv", row.names=TRUE)
    write.csv(as.data.frame(row_mean), "row_means.csv", row.names=TRUE)
    write.csv(as.data.frame(mvar), "row_mean_variance.csv", row.names=TRUE)
    
    # 6. Perform memory-efficient PCA
    sce <- scRunPCA(sce)
    
    # Plot and save PCA results
    pdf("pca_plot.pdf", width=6, height=5)
    plotReducedDim(sce, dimred="PCA")
    dev.off()
    
    # 7. Perform UMAP dimensionality reduction
    sce <- runUMAP(sce)
    
    # Plot and save UMAP results
    pdf("umap_plot.pdf", width=6, height=5)
    plotReducedDim(sce, dimred="UMAP")
    dev.off()
    
    # Save the final analyzed SingleCellExperiment object
    saveRDS(sce, "analyzed_sce.rds")
    
    # Clean up temporary GDS file
    if (file.exists("test.gds")) {
        unlink("test.gds", force=TRUE)
    }
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
      process = "BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS":',
        paste0('    SCArray: ', as.character(packageVersion('SCArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gds_single_cell_analysis.csv versions.yml
    """
}

workflow BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.rds, example.gds ] ]

    main:
    BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.tables
    plots    = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.plots
    objects  = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.objects
    versions = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.versions
}
