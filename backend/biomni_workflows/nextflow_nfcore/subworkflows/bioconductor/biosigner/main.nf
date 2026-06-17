#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biosigner — matrix_and_dataframe_analysis
// Perform feature selection, model training, signature visualization, and class prediction using standard matrix or data frame inputs.
// Input: dataMatrix, sampleMetadata
// Container: quay.io/biocontainers/bioconductor-biosigner:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: biosigner
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs
//  * 2. [Visualization & Output] Run feature selection and model training using biosign
//  * 3. [Visualization & Output] Visualize individual boxplots of the selected features
//  * 4. [Visualization & Output] Extract the names of the selected features in the final
//  * 5. [Visualization & Output] Train a model on a training subset and predict classes on
//  * 6. [Visualization & Output] Retrieve the balanced accuracy of the models

nextflow.enable.dsl = 2

process BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS {
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
    .bm_deps <- c("biosigner")
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
        library(biosigner)
        
        # Helper function to read input files robustly
        read_input <- function(filename) {
          if (file.exists(paste0(filename, ".rds"))) {
            return(readRDS(paste0(filename, ".rds")))
          } else if (file.exists(paste0(filename, ".csv"))) {
            return(read.csv(paste0(filename, ".csv"), row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          } else if (file.exists(paste0(filename, ".tsv"))) {
            return(read.delim(paste0(filename, ".tsv"), row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          } else if (file.exists(filename)) {
            # Try reading as CSV first, then TSV
            tryCatch({
              return(read.csv(filename, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
            }, error = function(e) {
              return(read.delim(filename, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
            })
          } else {
            stop(paste("Required input file not found:", filename))
          }
        }
        
        # --- Read User Inputs ---
        dataMatrix <- as.matrix(read_input("dataMatrix"))
        sampleMetadata <- read_input("sampleMetadata")
        
        # Ensure the "type" column exists in sampleMetadata (fallback to first column if missing)
        if (!"type" %in% colnames(sampleMetadata)) {
          message("Column 'type' not found in sampleMetadata. Using the first column as 'type'.")
          colnames(sampleMetadata)[1] <- "type"
        }
        sampleMetadata\$type <- as.factor(sampleMetadata\$type)
        
        # Construct variableMetadata dynamically from dataMatrix column names
        variableMetadata <- data.frame(
          row.names = colnames(dataMatrix),
          feature_id = colnames(dataMatrix),
          stringsAsFactors = FALSE
        )
        
        # --- Run feature selection and model training using biosign ---
        diaSign <- biosign(dataMatrix, sampleMetadata[, "type"], bootI = 5)
        
        # Save the biosign object
        saveRDS(diaSign, "diaSign.rds")
        
        # --- Visualize individual boxplots of the selected features ---
        pdf("signature_boxplot.pdf", width = 8, height = 8)
        plot(diaSign, typeC = "boxplot")
        dev.off()
        
        # --- Extract the names of the selected features in the final ---
        selected_features <- variableMetadata[getSignatureLs(diaSign)[["complete"]], , drop = FALSE]
        write.csv(selected_features, "selected_features.csv", row.names = TRUE)
        
        # --- Train a model on a training subset and predict classes on ---
        trainVi <- 1:floor(0.8 * nrow(dataMatrix))
        testVi <- setdiff(1:nrow(dataMatrix), trainVi)
        
        diaTrain <- biosign(dataMatrix[trainVi, , drop = FALSE], sampleMetadata[trainVi, "type"], bootI = 5)
        saveRDS(diaTrain, "diaTrain.rds")
        
        diaFitDF <- predict(diaTrain)
        write.csv(as.data.frame(diaFitDF), "train_predictions.csv", row.names = TRUE)
        
        # --- Retrieve the balanced accuracy of the models ---
        accuracy_S <- round(getAccuracyMN(diaTrain)["S", ], 3)
        write.csv(as.data.frame(t(accuracy_S)), "train_accuracy_S.csv", row.names = FALSE)
        
        # Predict on test data
        diaTestDF <- predict(diaTrain, newdata = dataMatrix[testVi, , drop = FALSE])
        write.csv(as.data.frame(diaTestDF), "test_predictions.csv", row.names = TRUE)
        
        message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS":',
        paste0('    biosigner: ', as.character(packageVersion('biosigner')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_and_dataframe_analysis.csv versions.yml
    """
}

workflow BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataMatrix, sampleMetadata ] ]

    main:
    BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS.out.tables
    plots    = BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS.out.plots
    objects  = BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS.out.objects
    versions = BIOC_BIOSIGNER_MATRIX_AND_DATAFRAME_ANALYSIS.out.versions
}
