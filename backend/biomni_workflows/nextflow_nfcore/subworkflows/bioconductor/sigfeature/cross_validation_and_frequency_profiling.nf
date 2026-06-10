#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sigFeature — cross_validation_and_frequency_profiling
// Perform external k-fold cross-validation, rank features based on their selection frequency across folds, and estimate classification error rates.
// Input: expression_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sigfeature:1.28.0--r45hdfd78af_0
// R packages: e1071, sigFeature
// Bioconductor: 3.20 | R: 4.4
// Requires: e1071, sigFeature
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run external cross-validation using sigFeature.enfold
//  * 2. [Core Analysis] Rank features based on frequency across folds using sigFeatureFrequency
//  * 3. [Core Analysis] Calculate cross-validation errors using sigCVError
//  * 4. [Visualization & Output] Plot validation errors using PlotErrors
//  * 5. [Visualization & Output] Write results using WritesigFeature

nextflow.enable.dsl = 2

process BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("e1071", "sigFeature")
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
            library(sigFeature)
            library(e1071)
            
            # -----------------------------------------------------------------------------
            # 1. Read and Preprocess Input Data
            # -----------------------------------------------------------------------------
            
            if (!file.exists("expression_matrix.csv")) {
              stop("Error: expression_matrix.csv not found in the working directory.")
            }
            if (!file.exists("sample_metadata.csv")) {
              stop("Error: sample_metadata.csv not found in the working directory.")
            }
            
            # Read expression matrix (features as rows, samples as columns)
            expr <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
            
            # Read sample metadata
            meta <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
            
            # Align samples between expression matrix and metadata
            common_samples <- intersect(colnames(expr), rownames(meta))
            if (length(common_samples) == 0) {
              stop("Error: No common samples found between expression matrix columns and metadata rows.")
            }
            
            expr <- expr[, common_samples, drop = FALSE]
            meta <- meta[common_samples, , drop = FALSE]
            
            # Transpose expression matrix so samples are rows and features are columns
            x <- t(as.matrix(expr))
            
            # Identify binary class label column in metadata and map to -1 and 1
            label_col <- NULL
            for (col in colnames(meta)) {
              if (length(unique(meta[[col]])) == 2) {
                label_col <- col
                break
              }
            }
            
            if (is.null(label_col)) {
              stop("Error: Could not find a binary class column in sample_metadata.csv")
            }
            
            raw_y <- meta[[label_col]]
            unique_vals <- unique(raw_y)
            y <- ifelse(raw_y == unique_vals[1], -1, 1)
            
            # -----------------------------------------------------------------------------
            # 2. Run External Cross-Validation
            # -----------------------------------------------------------------------------
            set.seed(1234)
            results = sigFeature.enfold(x, y, "kfold", 10)
            
            # -----------------------------------------------------------------------------
            # 3. Rank Features Based on Frequency Across Folds
            # -----------------------------------------------------------------------------
            num_features <- min(ncol(x), 400)
            FeatureBasedonFrequency <- sigFeatureFrequency(x, results, num_features, num_features, pf=FALSE)
            
            # -----------------------------------------------------------------------------
            # 4. Calculate Cross-Validation Errors
            # -----------------------------------------------------------------------------
            inputdata <- data.frame(y=as.factor(y) ,x=x)
            featsweepSigFe = lapply(1:num_features, sigCVError, FeatureBasedonFrequency, inputdata)
            
            # -----------------------------------------------------------------------------
            # 5. Plot Validation Errors
            # -----------------------------------------------------------------------------
            pdf("validation_errors.pdf", width = 10, height = 6)
            max_err <- max(sapply(featsweepSigFe, function(res) res\$error + res\$errorSD), na.rm = TRUE)
            y_max <- max(0.4, max_err)
            PlotErrors(featsweepSigFe, 0, y_max)
            dev.off()
            
            # -----------------------------------------------------------------------------
            # 6. Write Results
            # -----------------------------------------------------------------------------
            # WritesigFeature writes output files directly to the working directory
            WritesigFeature(results, x)
            
            # Save key R objects to RDS files
            saveRDS(results, "results.rds")
            saveRDS(FeatureBasedonFrequency, "FeatureBasedonFrequency.rds")
            saveRDS(featsweepSigFe, "featsweepSigFe.rds")

    writeLines(c(
        '"BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING":',
        paste0('    sigFeature: ', as.character(packageVersion('sigFeature')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_validation_and_frequency_profiling.csv versions.yml
    """
}

workflow BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING(ch_input)

    emit:
    tables   = BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING.out.tables
    plots    = BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING.out.plots
    objects  = BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING.out.objects
    versions = BIOC_SIGFEATURE_CROSS_VALIDATION_AND_FREQUENCY_PROFILING.out.versions
}
