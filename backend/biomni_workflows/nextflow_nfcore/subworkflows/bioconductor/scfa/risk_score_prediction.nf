#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SCFA — risk_score_prediction
// Predict patient risk scores using survival information from training data and multi-omics profiles.
// Input: trainList, trainSurvival, testList
// Container: quay.io/biocontainers/bioconductor-scfa:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SCFA, survival
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the SCFA and survival packages
//  * 2. [Input & Preparation] Prepare training and testing multi-omics data lists and survival objects (ensuring survival times are positive)
//  * 3. [Core Analysis] Run the SCFA.class function to predict risk scores for the test set
//  * 4. [Core Analysis] Validate the predicted risk scores using the concordance index

nextflow.enable.dsl = 2

process BIOC_SCFA_RISK_SCORE_PREDICTION {
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
    .bm_deps <- c("SCFA", "survival")
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
    library(SCFA)
    library(survival)
    
    # 1. Read user input files from the working directory
    trainList <- readRDS("trainList.rds")
    trainSurvival <- readRDS("trainSurvival.rds")
    testList <- readRDS("testList.rds")
    
    # Read testSurvival if available for validation
    testSurvival <- NULL
    if (file.exists("testSurvival.rds")) {
      testSurvival <- readRDS("testSurvival.rds")
    }
    
    # 2. Ensure survival times are positive
    # For trainSurvival
    train_time <- as.numeric(trainSurvival[, 1])
    train_event <- as.numeric(trainSurvival[, 2])
    if (any(train_time <= 0, na.rm = TRUE)) {
      train_time <- train_time - min(train_time, na.rm = TRUE) + 1
      trainSurvival <- survival::Surv(time = train_time, event = train_event)
    }
    
    # For testSurvival (if available)
    if (!is.null(testSurvival)) {
      test_time <- as.numeric(testSurvival[, 1])
      test_event <- as.numeric(testSurvival[, 2])
      if (any(test_time <= 0, na.rm = TRUE)) {
        test_time <- test_time - min(test_time, na.rm = TRUE) + 1
        testSurvival <- survival::Surv(time = test_time, event = test_event)
      }
    }
    
    # 3. Run the SCFA.class function to predict risk scores for the test set
    result <- SCFA.class(trainList, trainSurvival, testList, seed = 1, ncores = 4L)
    
    # Save the predicted risk scores
    saveRDS(result, "predicted_risk_scores.rds")
    
    # Export predicted risk scores to a CSV table
    sample_names <- names(result)
    if (is.null(sample_names)) {
      sample_names <- paste0("Sample_", seq_along(result))
    }
    results_df <- data.frame(
      SampleID = sample_names,
      RiskScore = as.numeric(result),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "predicted_risk_scores.csv", row.names = FALSE)
    
    # 4. Validate the predicted risk scores using the concordance index
    if (!is.null(testSurvival)) {
      c.index <- survival::concordance(coxph(testSurvival ~ result))\$concordance
      print(c.index)
      writeLines(as.character(c.index), "concordance_index.txt")
    } else {
      message("testSurvival.rds not found; skipping concordance index validation.")
    }

    writeLines(c(
        '"BIOC_SCFA_RISK_SCORE_PREDICTION":',
        paste0('    SCFA: ', as.character(packageVersion('SCFA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_risk_score_prediction.csv versions.yml
    """
}

workflow BIOC_SCFA_RISK_SCORE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainList, trainSurvival, testList ] ]

    main:
    BIOC_SCFA_RISK_SCORE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_SCFA_RISK_SCORE_PREDICTION.out.tables
    plots    = BIOC_SCFA_RISK_SCORE_PREDICTION.out.plots
    objects  = BIOC_SCFA_RISK_SCORE_PREDICTION.out.objects
    versions = BIOC_SCFA_RISK_SCORE_PREDICTION.out.versions
}
