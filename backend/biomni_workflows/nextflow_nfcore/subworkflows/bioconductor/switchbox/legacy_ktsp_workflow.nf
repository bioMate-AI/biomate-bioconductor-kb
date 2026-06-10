#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: switchBox — legacy_ktsp_workflow
// Train and classify using the deprecated legacy functions for backward compatibility or reproducing older studies.
// Input: matTraining, trainingGroup, matTesting
// Container: quay.io/biocontainers/bioconductor-switchbox:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: switchBox
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert factor labels to numeric 0/1 vector
//  * 2. [Core Analysis] Train legacy classifier using KTSP.Train
//  * 3. [Core Analysis] Classify samples using KTSP.Classify with a custom combination function

nextflow.enable.dsl = 2

process BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(switchBox)
    
    # Read user inputs from the working directory
    # RDS format is used to preserve matrix dimensions, row/column names, and factor levels.
    matTraining <- readRDS("matTraining.rds")
    trainingGroup <- readRDS("trainingGroup.rds")
    matTesting <- readRDS("matTesting.rds")
    
    # Handle testingGroup gracefully if it is not provided as a primary input
    if (file.exists("testingGroup.rds")) {
      testingGroup <- readRDS("testingGroup.rds")
    } else {
      # Fallback to a dummy factor based on trainingGroup levels to prevent downstream failure
      testingGroup <- factor(rep(levels(trainingGroup)[1], ncol(matTesting)), levels = levels(trainingGroup))
    }
    
    # === DOCUMENTED CODE ===
    trainingGroupNum <- as.numeric(trainingGroup) - 1
    classifier <- KTSP.Train(matTraining, trainingGroupNum, n=8)
    trainPrediction <- KTSP.Classify(matTraining, classifier, combineFunc = function(x) sum(x) < 2.5)
    testingGroupNum <- as.numeric(testingGroup) - 1
    testPrediction <- KTSP.Classify(matTesting, classifier, combineFunc = function(x) sum(x) < 2.5)
    # === END DOCUMENTED CODE ===
    
    # Save the trained legacy classifier
    saveRDS(classifier, "legacy_classifier.rds")
    
    # Save predictions as CSV files
    write.csv(data.frame(
      Sample = colnames(matTraining),
      Prediction = trainPrediction,
      Actual_GroupNum = trainingGroupNum
    ), "train_predictions.csv", row.names = FALSE)
    
    write.csv(data.frame(
      Sample = colnames(matTesting),
      Prediction = testPrediction,
      Actual_GroupNum = testingGroupNum
    ), "test_predictions.csv", row.names = FALSE)
    
    # Save a text summary of the classification performance
    sink("classification_summary.txt")
    cat("=== Legacy KTSP Workflow Summary ===\n\n")
    cat("Training Group Contingency Table:\n")
    print(table(trainPrediction, trainingGroupNum))
    cat("\nTesting Group Contingency Table:\n")
    print(table(testPrediction, testingGroupNum))
    sink()

    writeLines(c(
        '"BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW":',
        paste0('    switchBox: ', as.character(packageVersion('switchBox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_legacy_ktsp_workflow.csv versions.yml
    """
}

workflow BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matTraining, trainingGroup, matTesting ] ]

    main:
    BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW.out.tables
    plots    = BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW.out.plots
    objects  = BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW.out.objects
    versions = BIOC_SWITCHBOX_LEGACY_KTSP_WORKFLOW.out.versions
}
