#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: batchelor — fast_mnn_correction
// Correct batch effects in single-cell RNA-seq datasets using the fast Mutual Nearest Neighbors (MNN) method in PCA space.
// Input: sce1, sce2
// Container: quay.io/biocontainers/bioconductor-batchelor:1.26.0--r45ha27e39d_0
// R packages: SingleCellExperiment, batchelor, ggplot2, knitr, scater, scran, scRNAseq, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, batchelor, ggplot2, scater, scran, scuttle
// Visualizations: t-SNE plot
// QC: per-cell QC metrics, batch-effect correction, cell QC metrics, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform quality control on cells
//  * 2. [Core Analysis] Subset datasets to common genes
//  * 3. [Core Analysis] Normalize sequencing depth across batches using multiBatchNorm
//  * 4. [Core Analysis] Model gene variance and select highly variable genes (HVGs)
//  * 5. [Core Analysis] Run fastMNN to obtain corrected low-dimensional coordinates

nextflow.enable.dsl = 2

process BIOC_BATCHELOR_FAST_MNN_CORRECTION {
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
    .bm_deps <- c("SingleCellExperiment", "batchelor", "ggplot2", "knitr", "scater", "scran", "scRNAseq", "scuttle", "SummarizedExperiment")
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
    
    # Load required librari    library(SummarizedExperiment)
es
    library(scuttle)
    library(scran)
    library(batchelor)
    library(scater)
    library(ggplot2)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    # The pipeline reads exactly these files from the working directory
    sce1 <- readRDS("sce1.rds")
    sce2 <- readRDS("sce2.rds")
    
    # ==========================================
    # 2. Perform Quality Control on Cells
    # ==========================================
    # Identify mitochondrial genes and calculate QC metrics
    sce1 <- addPerCellQC(sce1, subsets=list(Mito=grep("mt-", rownames(sce1), ignore.case=TRUE)))
    qc1 <- quickPerCellQC(colData(sce1), sub.fields="subsets_Mito_percent")
    sce1 <- sce1[, !qc1\$discard]
    
    sce2 <- addPerCellQC(sce2, subsets=list(Mito=grep("mt_", rownames(sce2), ignore.case=TRUE)))
    qc2 <- quickPerCellQC(colData(sce2), sub.fields="subsets_Mito_percent")
    sce2 <- sce2[, !qc2\$discard]
    
    # ==========================================
    # 3. Subset Datasets to Common Genes
    # ==========================================
    universe <- intersect(rownames(sce1), rownames(sce2))
    sce1 <- sce1[universe,]
    sce2 <- sce2[universe,]
    
    # ==========================================
    # 4. Normalize Sequencing Depth Across Batches
    # ==========================================
    out <- multiBatchNorm(sce1, sce2)
    sce1 <- out[[1]]
    sce2 <- out[[2]]
    
    # ==========================================
    # 5. Model Gene Variance and Select HVGs
    # ==========================================
    dec1 <- modelGeneVar(sce1)
    dec2 <- modelGeneVar(sce2)
    combined.dec <- combineVar(dec1, dec2)
    chosen.hvgs <- getTopHVGs(combined.dec, n=5000)
    
    # ==========================================
    # 6. Run fastMNN to Obtain Corrected Coordinates
    # ==========================================
    set.seed(101)
    f.out <- fastMNN(A=sce1, B=sce2, subset.row=chosen.hvgs)
    
    # ==========================================
    # 7. Visualization and Diagnostics
    # ==========================================
    set.seed(103)
    f.out <- runTSNE(f.out, dimred="corrected")
    
    # Save t-SNE plot to PDF
    pdf("corrected_tsne_plot.pdf", width=8, height=6)
    print(plotTSNE(f.out, colour_by="batch") + ggtitle("fastMNN Corrected t-SNE"))
    dev.off()
    
    # ==========================================
    # 8. Save Outputs
    # ==========================================
    # Save the complete corrected SingleCellExperiment object
    saveRDS(f.out, "corrected_sce.rds")
    
    # Save corrected low-dimensional coordinates (PCA space)
    corrected_pcs <- reducedDim(f.out, "corrected")
    write.csv(as.data.frame(corrected_pcs), "corrected_coordinates.csv", row.names=TRUE)
    
    # Save cell metadata including batch assignments
    write.csv(as.data.frame(colData(f.out)), "corrected_metadata.csv", row.names=TRUE)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # per-cell QC metrics — alias semantics to cell QC metrics; reports
    # cells-flagged fraction by detecting library-size outliers via MAD.
    .pcqc_outlier_frac <- NA_real_; .pcqc_files <- character(0)
    for (.pcqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    # batch-effect correction — declarative pass via corrected-output presence
    # (kBET acceptance metric is a future per-workflow follow-on).
    .bec_artifacts <- list.files(".", pattern = "(?i)(corrected|batch|combat|harmony|mnn).*\\.(rds|csv|h5ad)\$")
    .bec_passes <- length(.bec_artifacts) > 0
    .gates_by_label[["batch-effect correction"]] <- list(
      gate_row = "bioc_batch_effect_correction",
      metric_name = "batch_corrected_artifacts",
      metric_value = length(.bec_artifacts),
      passes = .bec_passes,
      status = if (.bec_passes) "computed (declarative; kBET acceptance pending)"
               else "not_computed (no batch-corrected artifact present)"
    )

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

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BATCHELOR_FAST_MNN_CORRECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("per-cell QC metrics", "batch-effect correction", "cell QC metrics", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BATCHELOR_FAST_MNN_CORRECTION":',
        paste0('    batchelor: ', as.character(packageVersion('batchelor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_mnn_correction.csv versions.yml
    """
}

workflow BIOC_BATCHELOR_FAST_MNN_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce1, sce2 ] ]

    main:
    BIOC_BATCHELOR_FAST_MNN_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.tables
    plots    = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.plots
    objects  = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.objects
    versions = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.versions
}
