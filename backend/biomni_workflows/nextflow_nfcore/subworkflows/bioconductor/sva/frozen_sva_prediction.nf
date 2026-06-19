#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sva — frozen_sva_prediction
// Remove batch effects and latent variation in a test dataset using "frozen" surrogate variables estimated from a training dataset for prediction tasks.
// Input: train_expression.csv, test_expression.csv, train_phenotype.csv
// Container: quay.io/biocontainers/bioconductor-sva:3.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pamr, sva
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Split data into training and test sets
//  * 2. [Core Analysis] Train a baseline classifier on unadjusted training data and predict on test data
//  * 3. [Core Analysis] Estimate surrogate variables on the training data using sva
//  * 4. [Core Analysis] Adjust both training and test datasets using fsva
//  * 5. [Core Analysis] Train and test a classifier on the adjusted datasets

nextflow.enable.dsl = 2

process BIOC_SVA_FROZEN_SVA_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("sva", "pamr")
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
    library(sva)
    library(pamr)
    
    # Set seed for reproducibility
    set.seed(12354)
    
    # Read user input files from the working directory
    trainData = as.matrix(read.csv("train_expression.csv", row.names=1, check.names=FALSE))
    testData = as.matrix(read.csv("test_expression.csv", row.names=1, check.names=FALSE))
    trainPheno = read.csv("train_phenotype.csv", row.names=1, check.names=FALSE)
    
    # Dynamically identify the class column (assuming it's the first column)
    class_col = colnames(trainPheno)[1]
    
    # Ensure the class column is treated as a factor
    trainPheno[[class_col]] = as.factor(trainPheno[[class_col]])
    
    # Handle test phenotype robustly (if provided, use it; otherwise create dummy for evaluation)
    if (file.exists("test_phenotype.csv")) {
      testPheno = read.csv("test_phenotype.csv", row.names=1, check.names=FALSE)
      testPheno[[class_col]] = as.factor(testPheno[[class_col]])
    } else {
      testPheno = data.frame(rep("Unknown", ncol(testData)), row.names = colnames(testData))
      colnames(testPheno) = class_col
      testPheno[[class_col]] = as.factor(testPheno[[class_col]])
    }
    
    # --- Documented Workflow Steps ---
    
    # 1. Train a baseline classifier on unadjusted training data and predict on test data
    mydata = list(x=trainData, y=trainPheno[[class_col]])
    mytrain = pamr.train(mydata)
    
    # Find optimal threshold using cross-validation
    mycv = pamr.cv(mytrain, mydata)
    opt_thresh = mycv\$threshold[which.min(mycv\$error)]
    
    table(pamr.predict(mytrain, testData, threshold=opt_thresh), testPheno[[class_col]])
    
    # 2. Estimate surrogate variables on the training data using sva
    trainMod = model.matrix(~ ., data=trainPheno[class_col])
    trainMod0 = model.matrix(~1, data=trainPheno)
    trainSv = sva(trainData, trainMod, trainMod0)
    
    # 3. Adjust both training and test datasets using fsva
    fsvaobj = fsva(trainData, trainMod, trainSv, testData)
    
    # 4. Train and test a classifier on the adjusted datasets
    mydataSv = list(x=fsvaobj\$db, y=trainPheno[[class_col]])
    mytrainSv = pamr.train(mydataSv)
    
    # Find optimal threshold for adjusted data using cross-validation
    mycvSv = pamr.cv(mytrainSv, mydataSv)
    opt_threshSv = mycvSv\$threshold[which.min(mycvSv\$error)]
    
    table(pamr.predict(mytrainSv, fsvaobj\$new, threshold=opt_threshSv), testPheno[[class_col]])
    
    # --- Save Outputs ---
    
    # Save evaluation tables
    tab_unadj = table(pamr.predict(mytrain, testData, threshold=opt_thresh), testPheno[[class_col]])
    write.csv(as.data.frame(tab_unadj), "evaluation_table_unadjusted.csv")
    
    tab_adj = table(pamr.predict(mytrainSv, fsvaobj\$new, threshold=opt_threshSv), testPheno[[class_col]])
    write.csv(as.data.frame(tab_adj), "evaluation_table_adjusted.csv")
    
    # Save predictions
    unadj_pred = pamr.predict(mytrain, testData, threshold=opt_thresh)
    unadj_pred_df = data.frame(Sample = colnames(testData), Predicted_Class = unadj_pred)
    write.csv(unadj_pred_df, "predictions_unadjusted.csv", row.names=FALSE)
    
    adj_pred = pamr.predict(mytrainSv, fsvaobj\$new, threshold=opt_threshSv)
    adj_pred_df = data.frame(Sample = colnames(testData), Predicted_Class = adj_pred)
    write.csv(adj_pred_df, "predictions_adjusted.csv", row.names=FALSE)
    
    # Save adjusted expression matrices
    write.csv(fsvaobj\$db, "fsva_adjusted_train_expression.csv")
    write.csv(fsvaobj\$new, "fsva_adjusted_test_expression.csv")
    
    # Save SVA and FSVA objects
    saveRDS(list(trainSv = trainSv, fsvaobj = fsvaobj), "fsva_objects.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # batch-effect correction — declarative pass via corrected-output presence
    # (kBET acceptance metric is a future per-workflow follow-on).
    .bec_artifacts <- list.files(".", pattern = "(?i)(corrected|batch|combat|harmony|mnn).*\\.(rds|csv|h5ad)\$")
    .bec_passes <- length(.bec_artifacts) > 0
    .gates_by_label[["batch-effect correction"]] <- list(
      gate_row = "bioc_batch_effect_correction",
      metric_name = "batch_corrected_artifacts",
      metric_value = length(.bec_artifacts),
      passes = .bec_passes,
      status = if (.bec_passes) "computed (declarative; kBET acceptance pending)"
               else "not_computed (no batch-corrected artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SVA_FROZEN_SVA_PREDICTION",
      domain  = "bioconductor",
      declared_qc_steps = c("batch-effect correction"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SVA_FROZEN_SVA_PREDICTION":',
        paste0('    sva: ', as.character(packageVersion('sva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frozen_sva_prediction.csv versions.yml
    """
}

workflow BIOC_SVA_FROZEN_SVA_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ train_expression.csv, test_expression.csv, train_phenotype.csv ] ]

    main:
    BIOC_SVA_FROZEN_SVA_PREDICTION(ch_input)

    emit:
    tables   = BIOC_SVA_FROZEN_SVA_PREDICTION.out.tables
    plots    = BIOC_SVA_FROZEN_SVA_PREDICTION.out.plots
    objects  = BIOC_SVA_FROZEN_SVA_PREDICTION.out.objects
    versions = BIOC_SVA_FROZEN_SVA_PREDICTION.out.versions
}
