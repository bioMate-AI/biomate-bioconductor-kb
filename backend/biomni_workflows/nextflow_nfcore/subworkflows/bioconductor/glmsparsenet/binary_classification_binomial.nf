#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: glmSparseNet — binary_classification_binomial
// Fit a network-penalized binomial logistic regression model to classify samples using a correlation-based network.
// Input: xdata, ydata
// Container: quay.io/biocontainers/bioconductor-glmsparsenet:1.28.0--r45hdfd78af_0
// R packages: ggplot2, glmSparseNet
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, glmSparseNet
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the network-penalized binomial model using cv.glmHub with network = "correlation"
//  * 2. [Core Analysis] Extract coefficients of the selected model at lambda.min

nextflow.enable.dsl = 2

process BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL {
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
    .bm_deps <- c("ggplot2", "glmSparseNet")
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
    library(glmSparseNet)
    library(ggplot2)
    
    # -------------------------------------------------------------------------
    # 1. Read User Input Files
    # -------------------------------------------------------------------------
    # The pipeline expects 'xdata' (matrix of gene expression) and 'ydata' (factor of binary labels)
    # to be present in the working directory as RDS or CSV files.
    
    if (file.exists("xdata.rds")) {
      xdata <- readRDS("xdata.rds")
    } else if (file.exists("xdata.csv")) {
      xdata <- as.matrix(read.csv("xdata.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: xdata file not found. Please provide 'xdata.rds' or 'xdata.csv' in the working directory.")
    }
    
    if (file.exists("ydata.rds")) {
      ydata <- readRDS("ydata.rds")
    } else if (file.exists("ydata.csv")) {
      ydata_df <- read.csv("ydata.csv", row.names = 1, check.names = FALSE)
      ydata <- factor(ydata_df[[1]])
      names(ydata) <- rownames(ydata_df)
    } else {
      stop("Error: ydata file not found. Please provide 'ydata.rds' or 'ydata.csv' in the working directory.")
    }
    
    # Ensure alignment of samples between xdata and ydata
    common_samples <- intersect(rownames(xdata), names(ydata))
    if (length(common_samples) == 0) {
      stop("Error: No common sample names found between xdata and ydata.")
    }
    xdata <- xdata[common_samples, , drop = FALSE]
    ydata <- ydata[common_samples]
    
    # -------------------------------------------------------------------------
    # 2. Fit Network-Penalized Binomial Model
    # -------------------------------------------------------------------------
    # Exact documented code call
    fitted <- cv.glmHub(xdata, ydata, family = "binomial", network = "correlation", nlambda = 1000, options = networkOptions( cutoff = .6, minDegree = .2 ) )
    
    # -------------------------------------------------------------------------
    # 3. Extract Coefficients of Selected Model
    # -------------------------------------------------------------------------
    # Exact documented code call
    coefsCV <- Filter(function(.x) .x != 0, coef(fitted, s = "lambda.min")[, 1])
    
    # -------------------------------------------------------------------------
    # 4. Save Outputs
    # -------------------------------------------------------------------------
    # Save the fitted model object
    saveRDS(fitted, "fitted_model.rds")
    
    # Save the selected coefficients as a CSV table
    coefs_df <- data.frame(
      feature = names(coefsCV),
      coefficient = as.numeric(coefsCV),
      stringsAsFactors = FALSE
    )
    write.csv(coefs_df, "selected_coefficients.csv", row.names = FALSE)
    
    # Save the cross-validation plot as a PDF
    pdf("cv_plot.pdf", width = 7, height = 5)
    plot(fitted)
    dev.off()
    
    cat("Pipeline completed successfully.\n")
    cat("Outputs saved:\n")
    cat(" - fitted_model.rds (Fitted cv.glmHub object)\n")
    cat(" - selected_coefficients.csv (Non-zero coefficients at lambda.min)\n")
    cat(" - cv_plot.pdf (Cross-validation error plot)\n")

    writeLines(c(
        '"BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL":',
        paste0('    glmSparseNet: ', as.character(packageVersion('glmSparseNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_classification_binomial.csv versions.yml
    """
}

workflow BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ xdata, ydata ] ]

    main:
    BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL(ch_input)

    emit:
    tables   = BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL.out.tables
    plots    = BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL.out.plots
    objects  = BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL.out.objects
    versions = BIOC_GLMSPARSENET_BINARY_CLASSIFICATION_BINOMIAL.out.versions
}
