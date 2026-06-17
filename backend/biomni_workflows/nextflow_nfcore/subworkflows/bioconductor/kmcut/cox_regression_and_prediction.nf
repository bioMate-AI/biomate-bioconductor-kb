#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — cox_regression_and_prediction
// Fit univariate Cox proportional hazard models to calculate hazard ratios or predict risk scores on test data.
// Input: expression_data_1.txt, expression_data_2.txt, survival_data.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// R packages: kmcut
// Bioconductor: 3.20 | R: 4.4
// Requires: kmcut
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create SummarizedExperiment objects for training and test data
//  * 2. [Core Analysis] Run ucox_batch to perform batch univariate Cox regression on a single dataset, or run ucox_pred to fit models on training data and

nextflow.enable.dsl = 2

process BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("kmcut")
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
    
    # Load the required package
    library(kmcut)
    
    # Define paths to the user input files in the working directory
    fdat1 <- "expression_data_1.txt"
    fdat2 <- "expression_data_2.txt"
    sdat <- "survival_data.txt"
    
    # Verify that the required input files exist
    if (!file.exists(fdat1)) {
      stop("Required input file 'expression_data_1.txt' is missing from the working directory.")
    }
    if (!file.exists(fdat2)) {
      stop("Required input file 'expression_data_2.txt' is missing from the working directory.")
    }
    if (!file.exists(sdat)) {
      stop("Required input file 'survival_data.txt' is missing from the working directory.")
    }
    
    # Step 1: Create SummarizedExperiment objects for training and test data
    se1 <- create_se_object(efile = fdat1, sfile = sdat)
    se2 <- create_se_object(efile = fdat2, sfile = sdat)
    
    # Step 2: Fit Cox model on the training data and predict risk scores on test data
    # This function automatically writes the following files to the working directory:
    # - demo_cox_train_sum.txt (Cox regression summary for training data)
    # - demo_train_score.txt (Risk scores for training data)
    # - demo_test_score.txt (Risk scores for test data)
    ucox_pred(obj1 = se1, obj2 = se2, bfname = "demo", min_uval = 40)
    
    # Print execution summary
    cat("Cox regression and prediction workflow completed successfully.\n")
    cat("Generated output files:\n")
    cat("  - demo_cox_train_sum.txt\n")
    cat("  - demo_train_score.txt\n")
    cat("  - demo_test_score.txt\n")

    writeLines(c(
        '"BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION":',
        paste0('    kmcut: ', as.character(packageVersion('kmcut')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cox_regression_and_prediction.csv versions.yml
    """
}

workflow BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data_1.txt, expression_data_2.txt, survival_data.txt ] ]

    main:
    BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION(ch_input)

    emit:
    tables   = BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION.out.tables
    plots    = BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION.out.plots
    objects  = BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION.out.objects
    versions = BIOC_KMCUT_COX_REGRESSION_AND_PREDICTION.out.versions
}
