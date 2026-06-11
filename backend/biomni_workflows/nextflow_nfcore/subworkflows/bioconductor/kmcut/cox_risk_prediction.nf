#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — cox_risk_prediction
// Fit univariate Cox proportional hazard models on training data and calculate risk scores for a test dataset.
// Input: expression_data_1.txt, expression_data_2.txt, survival_data.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// R packages: kmcut
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT_COX_RISK_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0"

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
    
    # Define the input file paths as specified by the user
    fdat1 <- "expression_data_1.txt"
    fdat2 <- "expression_data_2.txt"
    sdat <- "survival_data.txt"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(fdat1)) {
      stop(paste("Required training expression file not found:", fdat1))
    }
    if (!file.exists(fdat2)) {
      stop(paste("Required test expression file not found:", fdat2))
    }
    if (!file.exists(sdat)) {
      stop(paste("Required survival data file not found:", sdat))
    }
    
    # 1. Create SummarizedExperiment for training data
    message("Creating SummarizedExperiment for training data...")
    se1 <- create_se_object(efile = fdat1, sfile = sdat)
    
    # 2. Create SummarizedExperiment for test data
    message("Creating SummarizedExperiment for test data...")
    se2 <- create_se_object(efile = fdat2, sfile = sdat)
    
    # 3. Fit Cox models on training data and calculate risk scores for test data
    message("Fitting Cox models and predicting risk scores...")
    tryCatch({
      ucox_pred(obj1 = se1, obj2 = se2, bfname = "demo", min_uval = 40)
      message("Pipeline completed successfully. Outputs written to 'demo_cox_train_sum.txt', 'demo_train_score.txt', and 'demo_test_score.txt'.")
    }, error = function(e) {
      stop(paste("Error during Cox risk prediction:", e\$message))
    })

    writeLines(c(
        '"BIOC_KMCUT_COX_RISK_PREDICTION":',
        paste0('        kmcut: ', as.character(packageVersion("kmcut")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cox_risk_prediction.csv versions.yml
    """
}

workflow BIOC_KMCUT_COX_RISK_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data_1.txt, expression_data_2.txt, survival_data.txt ] ]

    main:
    BIOC_KMCUT_COX_RISK_PREDICTION(ch_input)

    emit:
    tables   = BIOC_KMCUT_COX_RISK_PREDICTION.out.tables
    plots    = BIOC_KMCUT_COX_RISK_PREDICTION.out.plots
    objects  = BIOC_KMCUT_COX_RISK_PREDICTION.out.objects
    versions = BIOC_KMCUT_COX_RISK_PREDICTION.out.versions
}
