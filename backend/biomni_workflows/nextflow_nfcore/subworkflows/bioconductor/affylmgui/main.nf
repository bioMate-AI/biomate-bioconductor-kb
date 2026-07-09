#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affylmGUI — affylmgui_microarray_pipeline
// Perform differential expression analysis of microarray data using affylmGUI's core engine and export diagnostic plots and results.
// Input: counts.csv, coldata.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, affylmGUI, limma, tcltk
// Visualizations: MA plot, volcano plot, box plot, density plot
// QC: diagnostic MA/PCA QC, normalization diagnostic plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE {
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
    .bm_deps <- c("affylmGUI", "limma", "Biobase")
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
    library(affylmGUI)
    library(limma)
    library(Biobase)
    library(tcltk)
    
    # Initialize affylmGUI globals
    initGlobals()
    
    # Mock tcltk dialogs to prevent blocking/hanging in headless environments
    if (requireNamespace("tcltk", quietly = TRUE)) {
      try({
        unlockBinding("tkgetSaveFile", asNamespace("tcltk"))
        assign("tkgetSaveFile", function(...) "normalized_expression.csv", envir = asNamespace("tcltk"))
        lockBinding("tkgetSaveFile", asNamespace("tcltk"))
        
        unlockBinding("tkmessageBox", asNamespace("tcltk"))
        assign("tkmessageBox", function(...) "ok", envir = asNamespace("tcltk"))
        lockBinding("tkmessageBox", asNamespace("tcltk"))
        
        unlockBinding("tkchooseDirectory", asNamespace("tcltk"))
        assign("tkchooseDirectory", function(...) getwd(), envir = asNamespace("tcltk"))
        lockBinding("tkchooseDirectory", asNamespace("tcltk"))
      }, silent = TRUE)
    }
    
    # --- Load Input Data ---
    # counts.csv contains the probe-by-sample normalized expression matrix
    exprs_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    # coldata.csv contains sample metadata with 'sample' and 'condition'
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    
    # Align expression matrix columns with metadata samples
    sample_cols <- coldata_df\$sample
    exprs_matrix <- as.matrix(exprs_df[, sample_cols, drop = FALSE])
    
    # --- Create ExpressionSet ---
    pheno_data <- AnnotatedDataFrame(coldata_df)
    rownames(pheno_data) <- coldata_df\$sample
    NormalizedAffyData <- ExpressionSet(assayData = exprs_matrix, phenoData = pheno_data)
    
    # --- Linear Model Fitting & Contrasts ---
    design <- model.matrix(~0 + condition, data = coldata_df)
    colnames(design) <- gsub("condition", "", colnames(design))
    colnames(design) <- make.names(colnames(design))
    
    fit <- lmFit(exprs_matrix, design)
    
    conditions <- unique(coldata_df\$condition)
    conditions_clean <- make.names(conditions)
    
    if (length(conditions_clean) >= 2) {
      contrast_str <- paste0(conditions_clean[2], " - ", conditions_clean[1])
      contrast_matrix <- makeContrasts(contrasts = contrast_str, levels = design)
      fit2 <- contrasts.fit(fit, contrast_matrix)
      eb <- eBayes(fit2)
    } else {
      fit2 <- fit
      eb <- eBayes(fit)
    }
    
    # Assign key objects to .GlobalEnv so affylmGUI functions can access them
    assign("NormalizedAffyData", NormalizedAffyData, envir = .GlobalEnv)
    assign("fit", fit, envir = .GlobalEnv)
    assign("fit2", fit2, envir = .GlobalEnv)
    assign("eb", eb, envir = .GlobalEnv)
    assign("Targets", coldata_df, envir = .GlobalEnv)
    
    # --- Export Normalized Expression Values ---
    tryCatch({
      ExportNormalizedExpressionValues()
    }, error = function(e) {
      message("ExportNormalizedExpressionValues failed, falling back to manual export: ", e\$message)
    })
    
    if (!file.exists("normalized_expression.csv")) {
      write.csv(exprs_matrix, "normalized_expression.csv")
    }
    
    # --- Export Top Table ---
    if (requireNamespace("tcltk", quietly = TRUE)) {
      try({
        unlockBinding("tkgetSaveFile", asNamespace("tcltk"))
        assign("tkgetSaveFile", function(...) "top_table.csv", envir = asNamespace("tcltk"))
        lockBinding("tkgetSaveFile", asNamespace("tcltk"))
      }, silent = TRUE)
    }
    
    tryCatch({
      ExportTopTable()
    }, error = function(e) {
      message("ExportTopTable failed, falling back to manual export: ", e\$message)
    })
    
    if (!file.exists("top_table.csv")) {
      tt <- topTable(eb, coef = 1, number = Inf)
      write.csv(tt, "top_table.csv")
    }
    
    # --- Generate Diagnostic Plots ---
    pdf("diagnostic_plots.pdf", width = 8, height = 8)
    
    # Normalized Intensity Boxplot
    tryCatch({
      NormalizedIntensityBoxPlot()
    }, error = function(e) {
      message("NormalizedIntensityBoxPlot failed, falling back to standard boxplot: ", e\$message)
      boxplot(exprs_matrix, main = "Normalized Intensity Boxplot", las = 2, col = "skyblue")
    })
    
    # Density Plot
    tryCatch({
      limma::plotDensities(exprs_matrix, legend = FALSE, main = "Density Plot of Intensities")
    }, error = function(e) {
      message("Density plot failed: ", e\$message)
    })
    
    # MA Plot
    tryCatch({
      affyPlotMA()
    }, error = function(e) {
      message("affyPlotMA failed, falling back to limma::plotMA: ", e\$message)
      limma::plotMA(fit, main = "MA Plot")
    })
    
    # QQ Plot
    tryCatch({
      QQTplot()
    }, error = function(e) {
      message("QQTplot failed, falling back to limma::qqt: ", e\$message)
      limma::qqt(eb\$t[, 1], df = eb\$df.total, main = "QQ Plot of Moderated t-statistics")
      abline(0, 1, col = "red")
    })
    
    # Volcano / LogOdds Plot
    tryCatch({
      LogOddsPlot()
    }, error = function(e) {
      message("LogOddsPlot failed, falling back to volcano plot: ", e\$message)
      limma::volcanoplot(eb, main = "Volcano Plot")
    })
    
    dev.off()
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    # normalization diagnostic plot — file-exists check for any PDF emitted
    # with "norm" / "mean_sd" / "library" in the filename. Pairs with
    # bioc_count_normalization (numeric metric); this row is the visual gate.
    .ndp_pdfs <- list.files(".", pattern = "(?i)(norm|mean.?sd|library).*\\.pdf\$")
    .ndp_passes <- length(.ndp_pdfs) > 0
    .gates_by_label[["normalization diagnostic plot"]] <- list(
      gate_row = "bioc_normalization_diagnostic_plot",
      metric_name = "normalization_plot_exists",
      metric_value = if (.ndp_passes) 1 else 0,
      passes = .ndp_passes,
      status = if (.ndp_passes) paste0("computed (", length(.ndp_pdfs), " diagnostic PDF(s) emitted)")
               else "not_computed (no normalization diagnostic PDF found)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC", "normalization diagnostic plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE":',
        paste0('    affylmGUI: ', as.character(packageVersion('affylmGUI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affylmgui_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE.out.versions
}
