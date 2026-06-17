#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miQC — one_dimensional_miqc
// Perform quality control filtering based solely on mitochondrial percentage using a 1D Gaussian mixture model to calculate a single threshold.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-miqc:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, miQC, scater
// Visualizations: plot (ggplot/base)
// QC: per-cell QC metrics, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify mitochondrial genes and calculate per-cell QC metrics using scater::addPerCellQC
//  * 2. [Core Analysis] Fit a 1D mixture model using mixtureModel with model_type = "one_dimensional"
//  * 3. [Visualization & Output] Visualize the model and filtering using plotModel and plotFiltering
//  * 4. [Core Analysis] Calculate the single mitochondrial percentage cutoff using get1DCutoff

nextflow.enable.dsl = 2

process BIOC_MIQC_ONE_DIMENSIONAL_MIQC {
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
    .bm_deps <- c("scater", "miQC", "ggplot2")
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
    suppressPackageStartupMessages({
        library(scater)
        library(miQC)
        library(ggplot2)
    })
    
    # 1. Read User Input
    message("Reading input SingleCellExperiment object...")
    if (file.exists("sce")) {
        sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
        sce <- readRDS("sce.rds")
    } else {
        stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # 2. Identify mitochondrial genes and calculate per-cell QC metrics
    message("Identifying mitochondrial genes and calculating QC metrics...")
    mt_genes <- grepl("^mt-",  rownames(sce))
    # Fallback to human mitochondrial prefix if no mouse mitochondrial genes are found
    if (sum(mt_genes) == 0) {
        mt_genes <- grepl("^MT-", rownames(sce))
    }
    feature_ctrls <- list(mito = rownames(sce)[mt_genes])
    sce <- addPerCellQC(sce, subsets = feature_ctrls)
    
    # 3. Fit a 1D mixture model
    message("Fitting 1D mixture model...")
    model4 <- mixtureModel(sce, model_type = "one_dimensional")
    
    # Save the fitted model object
    saveRDS(model4, "model4.rds")
    
    # 4. Visualize the model and filtering
    message("Generating diagnostic plots...")
    pdf("miqc_1d_plots.pdf", width = 7, height = 5)
    print(plotModel(sce, model4))
    print(plotFiltering(sce, model4))
    dev.off()
    
    # 5. Calculate the single mitochondrial percentage cutoff
    message("Calculating 1D mitochondrial cutoff...")
    cutoff <- get1DCutoff(sce, model4)
    
    # Write the cutoff value to output files
    writeLines(as.character(cutoff), "cutoff_1d.txt")
    write.csv(data.frame(mitochondrial_cutoff_percent = cutoff), "cutoff_1d.csv", row.names = FALSE)
    
    # Save the updated SingleCellExperiment object containing the QC metrics
    saveRDS(sce, "sce_processed.rds")
    
    message("Pipeline completed successfully!")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MIQC_ONE_DIMENSIONAL_MIQC",
      domain  = "bioconductor",
      declared_qc_steps = c("per-cell QC metrics", "cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIQC_ONE_DIMENSIONAL_MIQC":',
        paste0('    miQC: ', as.character(packageVersion('miQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_dimensional_miqc.csv versions.yml
    """
}

workflow BIOC_MIQC_ONE_DIMENSIONAL_MIQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_MIQC_ONE_DIMENSIONAL_MIQC(ch_input)

    emit:
    tables   = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.tables
    plots    = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.plots
    objects  = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.objects
    versions = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.versions
}
