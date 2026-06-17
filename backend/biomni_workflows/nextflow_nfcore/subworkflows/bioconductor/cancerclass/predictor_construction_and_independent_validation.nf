#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cancerclass — predictor_construction_and_independent_validation
// Fit a nearest-centroid predictor on a training dataset and predict/evaluate outcomes on an independent validation dataset.
// Input: ExpressionSet, ExpressionSet
// Container: quay.io/biocontainers/bioconductor-cancerclass:1.54.0--r45h01b2380_0
// R packages: Biobase, cancerclass
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, cancerclass
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit a predictor on the training dataset using fit
//  * 2. [Core Analysis] Predict classes and calculate continuous scores on the validation dataset using predict
//  * 3. [Visualization & Output] Plot score distribution histogram using plot(..., type="histogram")
//  * 4. [Visualization & Output] Plot ROC curve using plot(..., type="roc")
//  * 5. [Visualization & Output] Fit and plot a logistic regression model using plot(..., type="logistic")

nextflow.enable.dsl = 2

process BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "cancerclass")
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
    library(cancerclass)
    library(Biobase)
    
    # Define input file paths
    training_file <- "training_dataset.rds"
    validation_file <- "validation_dataset.rds"
    
    # Validate existence of input files
    if (!file.exists(training_file)) {
      stop(paste("Error: Training dataset file missing. Expected:", training_file))
    }
    if (!file.exists(validation_file)) {
      stop(paste("Error: Validation dataset file missing. Expected:", validation_file))
    }
    
    # Read the ExpressionSet inputs
    train_eset <- readRDS(training_file)
    val_eset <- readRDS(validation_file)
    
    # Dynamically determine a positive class label from the first column of phenoData
    positive_class <- as.character(na.omit(unique(pData(train_eset)[[1]])))[1]
    
    # 1. Fit a predictor on the training dataset
    predictor <- fit(train_eset, method="welch.test")
    
    # 2. Predict classes and calculate continuous scores on the validation dataset
    prediction <- predict(predictor, val_eset, positive=positive_class, dist="cor")
    
    # Save the fitted predictor and prediction objects
    saveRDS(predictor, file="predictor.rds")
    saveRDS(prediction, file="prediction.rds")
    
    # 3. Plot score distribution histogram
    pdf("histogram_plot.pdf")
    plot(prediction, type="histogram", positive=positive_class, score="zeta")
    dev.off()
    
    # 4. Plot ROC curve
    pdf("roc_plot.pdf")
    plot(prediction, type="roc", positive=positive_class, score="zeta")
    dev.off()
    
    # 5. Fit and plot a logistic regression model
    pdf("logistic_plot.pdf")
    plot(prediction, type="logistic", positive=positive_class, score="zeta")
    dev.off()
    
    # Write a summary of the prediction results
    sink("prediction_summary.txt")
    cat("=== Prediction Summary ===\n")
    tryCatch({
      print(summary(prediction))
    }, error = function(e) {
      cat("Could not print summary: ", e\$message, "\n")
    })
    sink()
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION":',
        paste0('    cancerclass: ', as.character(packageVersion('cancerclass')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predictor_construction_and_independent_validation.csv versions.yml
    """
}

workflow BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet, ExpressionSet ] ]

    main:
    BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION(ch_input)

    emit:
    tables   = BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION.out.tables
    plots    = BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION.out.plots
    objects  = BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION.out.objects
    versions = BIOC_CANCERCLASS_PREDICTOR_CONSTRUCTION_AND_INDEPENDENT_VALIDATION.out.versions
}
