#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MethPed — pediatric_tumor_classification
// Classify pediatric brain tumor samples into subtypes using DNA methylation beta values, handling potential missing values.
// Input: methylation_data.csv
// Container: quay.io/biocontainers/bioconductor-methped:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MethPed, impute
// Visualizations: bar plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check for missing values in the input data using checkNA
//  * 2. [Core Analysis] Impute missing values using impute.knn if necessary
//  * 3. [Core Analysis] Run the MethPed classifier to obtain subtype probabilities or binary classifications
//  * 4. [Core Analysis] Check for missing predictor probes using probeMis
//  * 5. [Visualization & Output] Summarize and visualize classification results using summary and plot

nextflow.enable.dsl = 2

process BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("MethPed", "impute")
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
    library(MethPed)
    library(impute)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input and Prepare Data
    # -----------------------------------------------------------------------------
    input_file <- "methylation_data.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Read the CSV file
    raw_data <- read.csv(input_file, check.names = FALSE)
    
    # Determine probe ID column and format as a numeric matrix with probe IDs as row names
    target_id_col <- grep("targetid", colnames(raw_data), ignore.case = TRUE)
    
    if (length(target_id_col) > 0) {
      row_names <- as.character(raw_data[[target_id_col[1]]])
      meth_matrix <- as.matrix(raw_data[, -target_id_col[1], drop = FALSE])
      rownames(meth_matrix) <- row_names
    } else if (is.character(raw_data[[1]]) || is.factor(raw_data[[1]])) {
      row_names <- as.character(raw_data[[1]])
      meth_matrix <- as.matrix(raw_data[, -1, drop = FALSE])
      rownames(meth_matrix) <- row_names
    } else {
      meth_matrix <- as.matrix(raw_data)
    }
    
    # Ensure the matrix is numeric
    mode(meth_matrix) <- "numeric"
    
    # -----------------------------------------------------------------------------
    # Stage 2: Check for Missing Values and Impute if Necessary
    # -----------------------------------------------------------------------------
    # Check for missing values in the input data using checkNA
    missingIndex <- checkNA(meth_matrix)
    print("Missing value check results:")
    print(missingIndex)
    
    # Determine if imputation is required
    has_missing <- any(is.na(meth_matrix))
    
    if (has_missing) {
      message("Missing values detected. Proceeding with KNN imputation...")
      
      # Remove random seed to ensure randomness as documented
      if (exists(".Random.seed")) rm(.Random.seed)
      
      # Impute missing values using impute.knn
      imputedData <- impute.knn(meth_matrix)
      imputedData <- imputedData\$data
      
      # Verify that missing values have been successfully resolved
      checkNA(imputedData)
      working_data <- imputedData
    } else {
      message("No missing values detected. Proceeding with original data.")
      working_data <- meth_matrix
    }
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run the MethPed Classifier
    # -----------------------------------------------------------------------------
    # Run the classifier to obtain subtype probabilities (prob = TRUE)
    myClassification <- MethPed(working_data)
    
    # Display and extract documented properties of the classification object
    print("Classification Object Summary:")
    print(myClassification)
    
    target_id_val <- myClassification\$target_id
    probes_val <- myClassification\$probes
    sample_val <- myClassification\$sample
    probes_missing_val <- myClassification\$probes_missing
    oob_err_val <- myClassification\$oob_err.rate
    predictions_val <- myClassification\$predictions
    
    # Run the classifier to obtain binary/maximum probability classifications (prob = FALSE)
    myClassification_max <- MethPed(working_data, prob = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Check for Missing Predictor Probes
    # -----------------------------------------------------------------------------
    missing_probes <- probeMis(myClassification)
    print("Missing predictor probes:")
    print(missing_probes)
    
    # -----------------------------------------------------------------------------
    # Stage 5: Summarize and Visualize Classification Results
    # -----------------------------------------------------------------------------
    # Print summaries to console
    message("\n--- Summary (Probabilities) ---")
    summary(myClassification)
    
    message("\n--- Summary (Max Probability / Binary) ---")
    summary(myClassification_max)
    
    # Generate and save visualization plots to PDF
    pdf("classification_plots.pdf", width = 10, height = 7)
    
    # 1. Custom barplot from vignette
    par(mai = c(1, 1, 1, 2), xpd = TRUE)
    mat <- t(myClassification\$predictions)
    mycols <- c("green", rainbow(nrow(mat), start = 0, end = 1)[nrow(mat):1], "red")
    barplot(mat, col = mycols, beside = FALSE, axisnames = TRUE, ylim = c(0, 1), xlab = "Sample", ylab = "Probability")
    legend(ncol(mat) + 0.5, 1, legend = rownames(mat), fill = mycols, xpd = TRUE, cex = 0.6)
    
    # 2. Documented generic plot calls
    plot(myClassification)
    plot(myClassification_max)
    
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 6: Write Outputs to Files
    # -----------------------------------------------------------------------------
    # Save predictions as CSV files
    write.csv(myClassification\$predictions, "methped_predictions_probabilities.csv", row.names = TRUE)
    write.csv(myClassification_max\$predictions, "methped_predictions_max.csv", row.names = TRUE)
    
    # Save missing probes list
    write.csv(data.frame(MissingProbes = missing_probes), "missing_probes.csv", row.names = FALSE)
    
    # Save full classification objects as RDS for downstream analysis
    saveRDS(myClassification, "myClassification.rds")
    saveRDS(myClassification_max, "myClassification_max.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION":',
        paste0('    MethPed: ', as.character(packageVersion('MethPed')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pediatric_tumor_classification.csv versions.yml
    """
}

workflow BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methylation_data.csv ] ]

    main:
    BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION.out.tables
    plots    = BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION.out.plots
    objects  = BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION.out.objects
    versions = BIOC_METHPED_PEDIATRIC_TUMOR_CLASSIFICATION.out.versions
}
