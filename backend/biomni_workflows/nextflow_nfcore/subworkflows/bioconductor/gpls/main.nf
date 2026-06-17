#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gpls — two_group_classification
// Fit a two-group classification model using generalized partial least squares and evaluate performance via cross-validation or test set error.
// Input: x, y, x1, y1
// Container: quay.io/biocontainers/bioconductor-gpls:1.82.0--r45hdfd78af_0
// R packages: gpls, MASS
// Bioconductor: 3.20 | R: 4.4
// Requires: gpls
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the two-group model using glpls1a
//  * 2. [Core Analysis] Calculate leave-one-out cross-validation error using glpls1a.cv.error
//  * 3. [Core Analysis] Calculate test set error and predict probabilities using glpls1a.train.test.error

nextflow.enable.dsl = 2

process BIOC_GPLS_TWO_GROUP_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("gpls", "MASS")
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
    
    # Load required library
    library(gpls)
    
    # ---------------------------------------------------------
    # 1. Read User Input Files
    # ---------------------------------------------------------
    # The pipeline reads x, y, x1, y1 from the working directory.
    # We support both CSV and RDS formats for robustness.
    
    # Read x (training predictors)
    if (file.exists("x.csv")) {
      x <- as.matrix(read.csv("x.csv", header = FALSE))
    } else if (file.exists("x.rds")) {
      x <- readRDS("x.rds")
    } else {
      stop("Required input file 'x.csv' or 'x.rds' not found in the working directory.")
    }
    
    # Read y (binary training responses 0/1)
    if (file.exists("y.csv")) {
      y_df <- read.csv("y.csv", header = FALSE)
      y <- as.numeric(y_df[[1]])
    } else if (file.exists("y.rds")) {
      y <- readRDS("y.rds")
    } else {
      stop("Required input file 'y.csv' or 'y.rds' not found in the working directory.")
    }
    
    # Read x1 (test predictors)
    if (file.exists("x1.csv")) {
      x1 <- as.matrix(read.csv("x1.csv", header = FALSE))
    } else if (file.exists("x1.rds")) {
      x1 <- readRDS("x1.rds")
    } else {
      stop("Required input file 'x1.csv' or 'x1.rds' not found in the working directory.")
    }
    
    # Read y1 (binary test responses 0/1)
    if (file.exists("y1.csv")) {
      y1_df <- read.csv("y1.csv", header = FALSE)
      y1 <- as.numeric(y1_df[[1]])
    } else if (file.exists("y1.rds")) {
      y1 <- readRDS("y1.rds")
    } else {
      stop("Required input file 'y1.csv' or 'y1.rds' not found in the working directory.")
    }
    
    # ---------------------------------------------------------
    # 2. Fit Two-Group Classification Models (glpls1a)
    # ---------------------------------------------------------
    # Fit model without bias reduction
    fit1 <- glpls1a(x, y, br = FALSE)
    
    # Fit model without bias reduction and 1 PLS component
    fit2 <- glpls1a(x, y, K.prov = 1, br = FALSE)
    
    # Fit model with bias reduction
    fit3 <- glpls1a(x, y, br = TRUE)
    
    # ---------------------------------------------------------
    # 3. Calculate Leave-One-Out Cross-Validation Error
    # ---------------------------------------------------------
    # CV error without bias reduction
    cv1 <- glpls1a.cv.error(x, y, br = FALSE)
    
    # CV error with bias reduction and 1 PLS component
    cv2 <- glpls1a.cv.error(x, y, K.prov = 1, br = TRUE)
    
    # ---------------------------------------------------------
    # 4. Calculate Test Set Error and Predict Probabilities
    # ---------------------------------------------------------
    # Test error without bias reduction
    tt1 <- glpls1a.train.test.error(x, y, x1, y1, br = FALSE)
    
    # Test error with bias reduction and 1 PLS component
    tt2 <- glpls1a.train.test.error(x, y, x1, y1, K.prov = 1, br = TRUE)
    
    # ---------------------------------------------------------
    # 5. Save Outputs
    # ---------------------------------------------------------
    # Save fit objects
    saveRDS(fit1, "fit_no_br.rds")
    saveRDS(fit2, "fit_no_br_k1.rds")
    saveRDS(fit3, "fit_br.rds")
    
    # Save coefficients
    coef_df <- data.frame(
      Model_NoBR = as.vector(fit1\$coefficients),
      Model_NoBR_K1 = as.vector(fit2\$coefficients),
      Model_BR = as.vector(fit3\$coefficients)
    )
    rownames(coef_df) <- names(fit1\$coefficients)
    write.csv(coef_df, "model_coefficients.csv", row.names = TRUE)
    
    # Save CV and Test Error Summary
    summary_errors <- data.frame(
      Metric = c("CV_Error_NoBR", "CV_Error_BR_K1", "Test_Error_NoBR", "Test_Error_BR_K1"),
      Error_Rate = c(cv1\$error, cv2\$error, tt1\$error, tt2\$error)
    )
    write.csv(summary_errors, "classification_errors.csv", row.names = FALSE)
    
    # Save Predictions
    predictions <- data.frame(
      True_Y1 = y1,
      Pred_Prob_NoBR = as.vector(tt1\$predict.test),
      Pred_Prob_BR_K1 = as.vector(tt2\$predict.test)
    )
    write.csv(predictions, "test_predictions.csv", row.names = FALSE)
    
    # Generate and save diagnostic plot
    pdf("prediction_plots.pdf", width = 7, height = 5)
    plot(predictions\$True_Y1, predictions\$Pred_Prob_NoBR,
         xlab = "True Labels (Test)", ylab = "Predicted Probabilities",
         main = "Test Predictions vs True Labels", pch = 19, col = "blue",
         ylim = c(0, 1))
    points(predictions\$True_Y1, predictions\$Pred_Prob_BR_K1, col = "red", pch = 17)
    legend("topleft", legend = c("No Bias Reduction", "Bias Reduction (K=1)"),
           col = c("blue", "red"), pch = c(19, 17))
    dev.off()

    writeLines(c(
        '"BIOC_GPLS_TWO_GROUP_CLASSIFICATION":',
        paste0('    gpls: ', as.character(packageVersion('gpls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_classification.csv versions.yml
    """
}

workflow BIOC_GPLS_TWO_GROUP_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x, y, x1, y1 ] ]

    main:
    BIOC_GPLS_TWO_GROUP_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_GPLS_TWO_GROUP_CLASSIFICATION.out.tables
    plots    = BIOC_GPLS_TWO_GROUP_CLASSIFICATION.out.plots
    objects  = BIOC_GPLS_TWO_GROUP_CLASSIFICATION.out.objects
    versions = BIOC_GPLS_TWO_GROUP_CLASSIFICATION.out.versions
}
