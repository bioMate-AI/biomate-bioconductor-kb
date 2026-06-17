#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Doscheda — doscheda_chemoproteomics
// Quantitative chemoproteomics analysis pipeline to determine protein-small molecule interaction profiles from peptide/protein intensity data.
// Input: intensity.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Doscheda
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("Doscheda")
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
    library(Doscheda)
    
    # Define parameters (can be configured)
    pearson_threshold <- 0.4
    normalization_method <- "loess" # Options: 'loess', 'median', 'none'
    
    # --- Read and validate input files ---
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'intensity.csv' and/or 'coldata.csv' are missing.")
    }
    
    intensity <- read.csv("intensity.csv", stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    if (!"feature_id" %in% colnames(intensity)) {
      stop("intensity.csv must contain a 'feature_id' column representing protein/peptide IDs.")
    }
    
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
      stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Align coldata with intensity columns
    common_samples <- intersect(coldata\$sample, colnames(intensity))
    if (length(common_samples) == 0) {
      stop("No matching sample columns found between intensity.csv and coldata.csv.")
    }
    
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # --- Replicate and Channel Ordering ---
    # Doscheda expects channels to be ordered by replicate, then by concentration/condition.
    # We dynamically assign replicate indices based on the occurrence of each condition.
    coldata <- coldata[order(coldata\$condition), ]
    coldata\$replicate <- ave(seq_len(nrow(coldata)), coldata\$condition, FUN = seq_along)
    coldata <- coldata[order(coldata\$replicate, coldata\$condition), ]
    
    channelNames <- coldata\$sample
    chansVal <- length(unique(coldata\$condition))
    repsVal <- length(unique(coldata\$replicate))
    
    message(paste("Detected", chansVal, "channels and", repsVal, "replicates."))
    
    # --- Prepare Data Frame for Doscheda ---
    # Doscheda requires specific columns for peptide intensity datasets:
    # 'Master.Protein.Accessions', 'Sequence', and 'Qvality.PEP'
    intensity\$Master.Protein.Accessions <- intensity\$feature_id
    intensity\$Sequence <- intensity\$feature_id
    intensity\$Qvality.PEP <- 1e-5 # Assign a high-quality default PEP score to prevent filtering
    
    # --- Initialize ChemoProtSet and Set Parameters ---
    ex <- new('ChemoProtSet')
    ex <- setParameters(
      x = ex,
      chansVal = chansVal,
      repsVal = repsVal,
      dataTypeStr = 'intensity',
      modelTypeStr = 'linear',
      PDBool = FALSE,
      removePepsBool = FALSE,
      incPDofPDBool = FALSE,
      incGeneFileBool = FALSE,
      organismStr = 'H.sapiens',
      pearsonThrshVal = pearson_threshold
    )
    
    # Set Data
    ex <- setData(
      x = ex,
      dataFrame = intensity,
      dataChannels = channelNames,
      accessionChannel = "Master.Protein.Accessions",
      sequenceChannel = "Sequence",
      qualityChannel = "Qvality.PEP"
    )
    
    # --- Run Doscheda Pipeline Steps ---
    message("Running peptide removal process...")
    ex <- removePeptides(ex, removePeps = FALSE)
    
    message(paste("Running normalization using method:", normalization_method))
    ex <- runNormalisation(ex, normalise = normalization_method)
    
    # Fit model if we have at least 3 channels (required for quadratic linear model fit)
    model_fitted <- FALSE
    if (chansVal >= 3) {
      message("Fitting quadratic linear model to the data...")
      ex <- fitModel(ex)
      model_fitted <- TRUE
    } else {
      warning("Model fitting skipped: Doscheda linear model requires at least 3 channels/concentrations.")
    }
    
    # --- Export Results ---
    if (model_fitted) {
      results <- getFinal(ex)
    } else {
      results <- getNorm(ex)
      results\$warning <- "Model not fitted: requires >= 3 channels."
    }
    write.csv(results, "doscheda_results.csv", row.names = FALSE)
    message("Results successfully written to 'doscheda_results.csv'.")
    
    # --- Generate Diagnostic and Results Plots ---
    message("Generating diagnostic plots...")
    pdf("doscheda_plots.pdf", width = 10, height = 8)
    
    # Boxplot of channels
    tryCatch({
      print(boxplot(ex))
    }, error = function(e) {
      message("Skipped boxplot: ", e\$message)
    })
    
    # Correlation Plot
    tryCatch({
      corrPlot(ex)
    }, error = function(e) {
      message("Skipped corrPlot: ", e\$message)
    })
    
    # Density Plot
    tryCatch({
      print(densityPlot(ex))
    }, error = function(e) {
      message("Skipped densityPlot: ", e\$message)
    })
    
    # PCA Plot
    tryCatch({
      print(pcaPlot(ex))
    }, error = function(e) {
      message("Skipped pcaPlot: ", e\$message)
    })
    
    # Mean-SD Plot
    tryCatch({
      print(meanSdPlot(ex))
    }, error = function(e) {
      message("Skipped meanSdPlot: ", e\$message)
    })
    
    # Replicate Plot (only if multiple replicates exist)
    if (repsVal >= 2) {
      tryCatch({
        replicatePlot(ex, conc = coldata\$condition[1], repIndex1 = 1, repIndex2 = 2)
      }, error = function(e) {
        message("Skipped replicatePlot: ", e\$message)
      })
    }
    
    # Model-specific plots
    if (model_fitted) {
      tryCatch({
        print(plot(ex))
      }, error = function(e) {
        message("Skipped default model plot: ", e\$message)
      })
      
      tryCatch({
        print(volcanoPlot(ex))
      }, error = function(e) {
        message("Skipped volcanoPlot: ", e\$message)
      })
    }
    
    dev.off()
    message("Plots successfully saved to 'doscheda_plots.pdf'.")

    writeLines(c(
        '"BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS":',
        paste0('    Doscheda: ', as.character(packageVersion('Doscheda')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doscheda_chemoproteomics.csv versions.yml
    """
}

workflow BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS(ch_input)

    emit:
    tables   = BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS.out.tables
    plots    = BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS.out.plots
    objects  = BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS.out.objects
    versions = BIOC_DOSCHEDA_DOSCHEDA_CHEMOPROTEOMICS.out.versions
}
