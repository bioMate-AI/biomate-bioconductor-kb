#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BEclear — one_step_batch_correction
// Perform automated batch effect detection, clearing, and imputation in a single function call.
// Input: beta_values.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-beclear:2.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BEclear
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Run the Overall Batch Correction Wrapper Function
//  * 3. [Core Analysis] Save Results

nextflow.enable.dsl = 2

process BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION {
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
    .bm_deps <- c("BEclear")
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
    library(BEclear)
    
    # --- Read User Input Files ---
    # The pipeline expects 'beta_values.csv' and 'sample_metadata.csv' in the working directory.
    if (!file.exists("beta_values.csv")) {
      stop("Error: 'beta_values.csv' not found in the working directory.")
    }
    if (!file.exists("sample_metadata.csv")) {
      stop("Error: 'sample_metadata.csv' not found in the working directory.")
    }
    
    # Load beta values matrix (genes/probes as rows, samples as columns)
    ex.data <- as.matrix(read.csv("beta_values.csv", row.names = 1, check.names = FALSE))
    
    # Load sample metadata
    ex.samples <- read.csv("sample_metadata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Ensure the sample metadata has the correct column names as required by BEclear
    # First column must be "sample_id", second column must be "batch_id"
    if (ncol(ex.samples) < 2) {
      stop("Error: 'sample_metadata.csv' must have at least two columns (sample_id and batch_id).")
    }
    colnames(ex.samples)[1:2] <- c("sample_id", "batch_id")
    
    # --- Run the Overall Batch Correction Wrapper Function ---
    # This performs batch effect detection, clearing, and imputation in a single call.
    message("Running BEclear batch correction...")
    result <- correctBatchEffect(data = ex.data, samples = ex.samples)
    
    # --- Save Results ---
    message("Saving results...")
    
    # Save the complete result object as an RDS file
    saveRDS(result, "batch_correction_result.rds")
    
    # Handle different potential return formats of correctBatchEffect
    if (is.matrix(result) || is.data.frame(result)) {
      # If it directly returned the corrected matrix
      write.csv(result, "corrected_beta_values.csv", row.names = TRUE)
      message("Corrected beta values saved to 'corrected_beta_values.csv'.")
    } else if (is.list(result)) {
      # If it returned a list of results (e.g., corrected matrix, intermediate steps)
      for (name in names(result)) {
        val <- result[[name]]
        if (is.matrix(val) || is.data.frame(val)) {
          write.csv(val, paste0("corrected_", name, ".csv"), row.names = TRUE)
        } else {
          saveRDS(val, paste0("corrected_", name, ".rds"))
        }
      }
      message("List of results saved to individual CSV/RDS files.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION":',
        paste0('    BEclear: ', as.character(packageVersion('BEclear')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_batch_correction.csv versions.yml
    """
}

workflow BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta_values.csv, sample_metadata.csv ] ]

    main:
    BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION.out.tables
    plots    = BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION.out.plots
    objects  = BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION.out.objects
    versions = BIOC_BECLEAR_ONE_STEP_BATCH_CORRECTION.out.versions
}
