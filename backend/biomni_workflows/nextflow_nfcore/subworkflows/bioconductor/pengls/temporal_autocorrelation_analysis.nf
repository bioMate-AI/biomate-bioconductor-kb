#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pengls — temporal_autocorrelation_analysis
// Fit a penalized generalized least squares model to high-dimensional time-series data using a temporal correlation structure and cross-validation.
// Input: dfTime
// Container: quay.io/biocontainers/bioconductor-pengls:1.16.0--r45hdfd78af_0
// R packages: BiocParallel, nlme, pengls
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, nlme, pengls
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the temporal correlation structure using nlme::corAR1
//  * 2. [Core Analysis] Fit the pengls model with cross-validation to find the optimal lambda, optionally specifying elastic net mixing parameter alpha
//  * 3. [Visualization & Output] Visualize or inspect the cross-validation folds using makeFolds
//  * 4. [Core Analysis] Perform cross-validation with custom settings such as random/blocked CV, outcome centering, or MSE loss

nextflow.enable.dsl = 2

process BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS {
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
    .bm_deps <- c("BiocParallel", "nlme", "pengls")
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
    
    # Register serial param for safe execution across environments
    register(SerialParam())
    
    # Read user input
    if (file.exists("dfTime.csv")) {
      dfTime <- read.csv("dfTime.csv")
    } else if (file.exists("dfTime.rds")) {
      dfTime <- readRDS("dfTime.rds")
    } else {
      stop("Error: dfTime file (dfTime.csv or dfTime.rds) not found in the working directory.")
    }
    
    # Dynamically determine outcome and regressor column names
    # Assuming the first column is the outcome and 't' is the time variable
    outVarName <- names(dfTime)[1]
    xVarNames <- setdiff(names(dfTime), c(outVarName, "t"))
    
    # Define the temporal correlation structure
    corStructTime <- corAR1(form = ~ t, value = 0.5)
    
    # Fit the pengls model with cross-validation to find the optimal lambda
    penglsFitTime <- pengls(
      data = dfTime, 
      outVar = outVarName, 
      verbose = TRUE, 
      xNames = xVarNames, 
      glsSt = corStructTime, 
      nfolds = 5, 
      alpha = 0.5
    )
    print(penglsFitTime)
    
    # Define nfolds for subsequent cross-validation steps
    nfolds <- 5
    
    # Visualize or inspect the cross-validation folds
    randomFolds <- makeFolds(nfolds = nfolds, dfTime, "random", "t")
    blockedFolds <- makeFolds(nfolds = nfolds, dfTime, "blocked", "t")
    
    # Save the folds visualization plot
    pdf("folds_comparison.pdf", width = 8, height = 7)
    plot(dfTime\$t, randomFolds, xlab = "Time", ylab = "Fold")
    points(dfTime\$t, blockedFolds, col = "red")
    legend("topleft", legend = c("random", "blocked"), pch = 1, col = c("black", "red"))
    dev.off()
    
    # Perform cross-validation with custom settings: random CV
    penglsFitCVtime <- cv.pengls(
      data = dfTime, 
      outVar = outVarName, 
      xNames = xVarNames, 
      glsSt = corStructTime, 
      nfolds = nfolds, 
      cvType = "random"
    )
    
    # Perform cross-validation with custom settings: blocked CV and outcome centering
    penglsFitCVtimeCenter <- cv.pengls(
      data = dfTime, 
      outVar = outVarName, 
      xNames = xVarNames, 
      glsSt = corStructTime, 
      nfolds = nfolds, 
      cvType = "blocked", 
      transFun = function(x) x - mean(x)
    )
    print(penglsFitCVtimeCenter\$cvOpt)
    
    # Perform cross-validation with custom settings: MSE loss
    penglsFitCVtimeMSE <- cv.pengls(
      data = dfTime, 
      outVar = outVarName, 
      xNames = xVarNames, 
      glsSt = corStructTime, 
      nfolds = nfolds, 
      loss = "MSE"
    )
    
    # Save meaningful results to files
    saveRDS(penglsFitTime, "penglsFitTime.rds")
    saveRDS(penglsFitCVtime, "penglsFitCVtime_random.rds")
    saveRDS(penglsFitCVtimeCenter, "penglsFitCVtime_centered.rds")
    saveRDS(penglsFitCVtimeMSE, "penglsFitCVtime_mse.rds")
    
    # Write out the optimal CV performance metric
    write.csv(
      data.frame(
        Model = c("Centered_Blocked_CV", "MSE_CV"),
        cvOpt = c(penglsFitCVtimeCenter\$cvOpt, penglsFitCVtimeMSE\$cvOpt)
      ), 
      "cv_performance_metrics.csv", 
      row.names = FALSE
    )

    writeLines(c(
        '"BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS":',
        paste0('    pengls: ', as.character(packageVersion('pengls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_temporal_autocorrelation_analysis.csv versions.yml
    """
}

workflow BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dfTime ] ]

    main:
    BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS.out.tables
    plots    = BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS.out.plots
    objects  = BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS.out.objects
    versions = BIOC_PENGLS_TEMPORAL_AUTOCORRELATION_ANALYSIS.out.versions
}
