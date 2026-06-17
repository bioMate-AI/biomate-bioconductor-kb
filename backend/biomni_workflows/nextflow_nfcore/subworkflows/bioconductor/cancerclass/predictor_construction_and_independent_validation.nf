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
    .bm_deps <- c("Biobase", "cancerclass")
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
