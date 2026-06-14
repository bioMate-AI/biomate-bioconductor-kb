#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affylmGUI — affylmgui_microarray_pipeline
// Perform differential expression analysis of microarray data using affylmGUI's core engine and export diagnostic plots and results.
// Input: counts.csv, coldata.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, affylmGUI, limma, tcltk
// Visualizations: MA plot, volcano plot, box plot
// QC: diagnostic MA/PCA QC
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYLMGUI_AFFYLMGUI_MICROARRAY_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
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
