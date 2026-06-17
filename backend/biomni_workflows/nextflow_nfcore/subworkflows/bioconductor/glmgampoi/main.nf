#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: glmGamPoi — pseudobulk_differential_expression
// Aggregate single-cell expression data into pseudobulk samples by individual and condition, fit a Gamma-Poisson GLM, and test for differential expression.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-glmgampoi:1.22.0--r45ha27e39d_0
// R packages: SingleCellExperiment, dplyr, ggplot2, glmGamPoi
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, ggplot2, glmGamPoi
// Visualizations: volcano plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate single-cell counts to pseudobulk using pseudobulk()
//  * 2. [Core Analysis] Filter out missing cell types
//  * 3. [Core Analysis] Fit the Gamma-Poisson GLM using glm_gp()
//  * 4. [Core Analysis] Test for differential expression using test_de()

nextflow.enable.dsl = 2

process BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("SingleCellExperiment", "dplyr", "ggplot2", "glmGamPoi", "SummarizedExperiment")
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
    
    # Load required libraries    library(SummarizedExperiment)

    library(glmGamPoi)
    library(ggplot2)
    library(dplyr)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a SingleCellExperiment object named 'sce' or 'sce.rds'
    # in the working directory.
    if (file.exists("sce")) {
      sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
      sce <- readRDS("sce.rds")
    } else {
      stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # Ensure the input is a SingleCellExperiment object
    if (!inherits(sce, "SingleCellExperiment")) {
      stop("Error: The input object is not of class 'SingleCellExperiment'.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 0.5: Identify Metadata Columns and Levels
    # -----------------------------------------------------------------------------
    # To avoid hardcoding dataset-specific columns, we read them from command line arguments
    # or default to the first three columns of colData(sce).
    args <- commandArgs(trailingOnly = TRUE)
    if (length(args) >= 6) {
      sample_col <- args[1]
      condition_col <- args[2]
      celltype_col <- args[3]
      celltype_val <- args[4]
      cond_trt <- args[5]
      cond_ctrl <- args[6]
    } else {
      message("Auto-detecting columns and levels from colData(sce)...")
      meta_cols <- colnames(colData(sce))
      if (length(meta_cols) < 3) {
        stop("Error: colData(sce) must contain at least 3 columns for sample, condition, and cell type.")
      }
      sample_col <- meta_cols[1]
      condition_col <- meta_cols[2]
      celltype_col <- meta_cols[3]
      
      celltype_val <- as.character(na.omit(unique(colData(sce)[[celltype_col]])))[1]
      cond_levels <- as.character(na.omit(unique(colData(sce)[[condition_col]])))
      if (length(cond_levels) < 2) {
        stop("Error: condition column must have at least 2 levels.")
      }
      cond_trt <- cond_levels[1]
      cond_ctrl <- cond_levels[2]
    }
    
    message(sprintf("Using columns: sample='%s', condition='%s', cell='%s'", sample_col, condition_col, celltype_col))
    message(sprintf("Testing: cell='%s', %s vs %s", celltype_val, cond_trt, cond_ctrl))
    
    # Standardize colData names for the pipeline to avoid non-standard evaluation issues
    colData(sce)\$std_sample <- colData(sce)[[sample_col]]
    colData(sce)\$std_condition <- colData(sce)[[condition_col]]
    colData(sce)\$std_cell <- colData(sce)[[celltype_col]]
    
    # -----------------------------------------------------------------------------
    # Stage 1: Aggregate single-cell counts to pseudobulk using pseudobulk()
    # -----------------------------------------------------------------------------
    message("Aggregating single-cell counts to pseudobulk...")
    reduced_sce <- pseudobulk(sce, group_by = vars(sample = std_sample, condition = std_condition, cell = std_cell), 
                              n_cells = n())
    
    # -----------------------------------------------------------------------------
    # Stage 2: Filter out missing cell types
    # -----------------------------------------------------------------------------
    message("Filtering out missing cell types...")
    reduced_sce <- reduced_sce[,!is.na(reduced_sce\$cell)]
    
    # -----------------------------------------------------------------------------
    # Stage 3: Fit the Gamma-Poisson GLM using glm_gp()
    # -----------------------------------------------------------------------------
    message("Fitting Gamma-Poisson GLM...")
    fit <- glm_gp(reduced_sce, design = ~ condition*cell + sample, size_factor = "ratio", verbose = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Test for differential expression using test_de()
    # -----------------------------------------------------------------------------
    message("Testing for differential expression...")
    res <- test_de(fit, contrast = cond(cell = celltype_val, condition = cond_trt) - cond(cell = celltype_val, condition = cond_ctrl))
    
    # -----------------------------------------------------------------------------
    # Stage 5: Write Outputs
    # -----------------------------------------------------------------------------
    message("Writing output files...")
    
    # 1. Save the differential expression results table
    write.csv(res, "differential_expression_results.csv", row.names = FALSE)
    
    # 2. Save the fitted model object and the pseudobulk SCE object
    saveRDS(fit, "glm_gp_fit.rds")
    saveRDS(reduced_sce, "pseudobulk_sce.rds")
    
    # 3. Generate and save a Volcano Plot of the DE results
    pdf("volcano_plot.pdf", width = 7, height = 5)
    p <- ggplot(res, aes(x = lfc, y = -log10(pval))) +
      geom_point(aes(color = adj_pval < 0.05), size = 0.5) +
      scale_color_manual(values = c("black", "red"), name = "FDR < 0.05") +
      theme_minimal() +
      labs(
        title = sprintf("Volcano Plot: %s (%s vs %s)", celltype_val, cond_trt, cond_ctrl),
        x = "Log2 Fold Change (LFC)",
        y = "-log10(p-value)"
      )
    print(p)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION":',
        paste0('    glmGamPoi: ', as.character(packageVersion('glmGamPoi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pseudobulk_differential_expression.csv versions.yml
    """
}

workflow BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_GLMGAMPOI_PSEUDOBULK_DIFFERENTIAL_EXPRESSION.out.versions
}
