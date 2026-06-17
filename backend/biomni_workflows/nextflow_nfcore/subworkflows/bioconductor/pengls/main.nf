#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pengls — spatial_autocorrelation_analysis
// Fit a penalized generalized least squares model to high-dimensional data with spatial coordinates using a spatial correlation structure.
// Input: df
// Container: quay.io/biocontainers/bioconductor-pengls:1.16.0--r45hdfd78af_0
// R packages: biocmanager, BiocParallel, nlme, pengls
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, nlme, pengls
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the spatial correlation structure using nlme::corGaus
//  * 2. [Core Analysis] Fit the pengls model with a specified penalty parameter lambda
//  * 3. [Core Analysis] Extract coefficients and make predictions
//  * 4. [Core Analysis] Perform cross-validation using cv.pengls to find the optimal lambda and inspect results

nextflow.enable.dsl = 2

process BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS {
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
    .bm_deps <- c("biocmanager", "BiocParallel", "nlme", "pengls")
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
        library(pengls)
        library(nlme)
        library(BiocParallel)
        
        # Configure safe parallel processing
        register(SerialParam())
        
        # Read user input from the working directory
        if (file.exists("df.rds")) {
          df <- readRDS("df.rds")
        } else if (file.exists("df.csv")) {
          df <- read.csv("df.csv")
        } else {
          stop("Input file 'df.csv' or 'df.rds' not found in the working directory.")
        }
        
        # Dynamically identify outcome variable and regressors
        # Assuming 'x' and 'y' are spatial coordinates, the first remaining column is the outcome, and the rest are regressors
        non_spatial_vars <- setdiff(names(df), c("x", "y"))
        out_var <- non_spatial_vars[1]
        x_names <- non_spatial_vars[-1]
        
        # Define the spatial correlation structure using nlme::corGaus
        corStruct <- corGaus(form = ~ x + y, nugget = TRUE, value = c("range" = 5, "nugget" = 0.5))
        
        # Fit the pengls model with a specified penalty parameter lambda
        penglsFit <- pengls(data = df, outVar = out_var, xNames = x_names, glsSt = corStruct, lambda = 0.2, verbose = TRUE)
        print(penglsFit)
        
        # Extract coefficients and make predictions
        penglsCoef <- coef(penglsFit)
        penglsPred <- predict(penglsFit)
        
        # Perform cross-validation using cv.pengls to find the optimal lambda and inspect results
        nfolds <- 3
        penglsFitCV <- cv.pengls(data = df, outVar = out_var, xNames = x_names, glsSt = corStruct, nfolds = nfolds)
        print(penglsFitCV)
        
        # Inspect CV results
        lambda_1se <- penglsFitCV\$lambda.1se
        cv_opt <- penglsFitCV\$cvOpt
        cv_coef_head <- head(coef(penglsFitCV))
        fold_ids <- penglsFitCV\$foldid
        
        # Save meaningful results to output files
        saveRDS(penglsFit, "pengls_fit.rds")
        saveRDS(penglsFitCV, "pengls_fit_cv.rds")
        
        # Save coefficients and predictions
        write.csv(as.data.frame(as.matrix(penglsCoef)), "pengls_coef.csv", row.names = TRUE)
        write.csv(data.frame(Predicted = penglsPred), "pengls_predictions.csv", row.names = FALSE)
        
        # Save CV coefficients and fold IDs
        write.csv(as.data.frame(as.matrix(coef(penglsFitCV))), "pengls_cv_coef.csv", row.names = TRUE)
        write.csv(data.frame(FoldID = fold_ids), "pengls_cv_foldid.csv", row.names = FALSE)
        
        # Save CV summary metrics
        cv_summary <- data.frame(
          lambda.1se = lambda_1se,
          cvOpt = cv_opt
        )
        write.csv(cv_summary, "pengls_cv_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS":',
        paste0('    pengls: ', as.character(packageVersion('pengls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_autocorrelation_analysis.csv versions.yml
    """
}

workflow BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ df ] ]

    main:
    BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS.out.tables
    plots    = BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS.out.plots
    objects  = BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS.out.objects
    versions = BIOC_PENGLS_SPATIAL_AUTOCORRELATION_ANALYSIS.out.versions
}
