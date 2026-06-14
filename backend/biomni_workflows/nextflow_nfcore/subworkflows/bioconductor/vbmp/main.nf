#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vbmp — multiclass_gp_classification_with_ard
// Train a Gaussian Process multinomial probit classifier with Automatic Relevance Determination (ARD) to estimate feature importance and predict classes on low-to
// Input: dataXtTrain$X, dataXtTrain$t.class, dataXtTest$X, dataXtTest$t.class
// Container: quay.io/biocontainers/bioconductor-vbmp:1.78.0--r45hdfd78af_0
// R packages: Biobase, vbmp
// Bioconductor: 3.20 | R: 4.4
// Requires: vbmp
// Visualizations: diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize covariance scale parameters (theta) and maximum iterations
//  * 2. [Core Analysis] Run variational Bayesian multinomial probit regression using vbmp with theta estimation enabled
//  * 3. [Core Analysis] Compute out-of-sample prediction error using predError
//  * 4. [Visualization & Output] Plot convergence and ARD diagnostics using plotDiagnostics

nextflow.enable.dsl = 2

process BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "vbmp")
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
    library(vbmp)
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Helper function to read input files (supporting RDS and CSV)
    read_input <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
        if (ncol(df) == 1) {
          return(df[[1]])
        }
        return(as.matrix(df))
      } else {
        stop(paste("Required input file not found:", base_name))
      }
    }
    
    # Load user inputs
    dataXtTrain <- list(
      X = read_input("dataXtTrain_X"),
      t.class = read_input("dataXtTrain_t.class")
    )
    
    dataXtTest <- list(
      X = read_input("dataXtTest_X"),
      t.class = read_input("dataXtTest_t.class")
    )
    
    # Stage 1: Initialize covariance scale parameters (theta) and maximum iterations
    theta <- rep(1., ncol(dataXtTrain\$X));
    max.train.iter <- 12;
    
    # Stage 2: Run variational Bayesian multinomial probit regression using vbmp with theta estimation enabled
    res <- vbmp( dataXtTrain\$X, dataXtTrain\$t.class,
                 dataXtTest\$X, dataXtTest\$t.class, theta, 
                 control=list(bThetaEstimate=T, bMonitor=T, maxIts=max.train.iter)); 
    
    # Stage 3: Compute out-of-sample prediction error using predError
    pred_err <- predError(res);   
    
    # Stage 4: Plot convergence and ARD diagnostics using plotDiagnostics
    pdf("diagnostics_plot.pdf", width = 10, height = 8)
    plotDiagnostics(res);
    dev.off()
    
    # Save meaningful results
    saveRDS(res, "vbmp_model_fit.rds")
    
    # Save prediction error
    write.csv(data.frame(PredictionError = pred_err), "prediction_error.csv", row.names = FALSE)
    
    # Save predicted classes vs true classes
    pred_classes <- predClass(res)
    predictions_df <- data.frame(
      TrueClass = dataXtTest\$t.class,
      PredictedClass = pred_classes
    )
    write.csv(predictions_df, "predictions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD":',
        paste0('    vbmp: ', as.character(packageVersion('vbmp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiclass_gp_classification_with_ard.csv versions.yml
    """
}

workflow BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataXtTrain$X, dataXtTrain$t.class, dataXtTest$X, dataXtTest$t.class ] ]

    main:
    BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD(ch_input)

    emit:
    tables   = BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD.out.tables
    plots    = BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD.out.plots
    objects  = BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD.out.objects
    versions = BIOC_VBMP_MULTICLASS_GP_CLASSIFICATION_WITH_ARD.out.versions
}
