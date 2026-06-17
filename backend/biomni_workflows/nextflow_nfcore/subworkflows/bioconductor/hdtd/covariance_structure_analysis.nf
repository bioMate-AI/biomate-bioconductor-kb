#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HDTD — covariance_structure_analysis
// Estimate and test the covariance and correlation structure of row and column variables in transposable data.
// Input: user_data.csv
// Container: quay.io/biocontainers/bioconductor-hdtd:1.44.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HDTD
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the transposable dataset
//  * 2. [Core Analysis] Estimate row and column covariance matrices with shrinkage using covmat.hat
//  * 3. [Core Analysis] Extract the estimated column (or row) covariance matrix
//  * 4. [Core Analysis] Perform hypothesis tests (diagonality, sphericity, identity) on the covariance matrix using covmat.ts

nextflow.enable.dsl = 2

process BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("HDTD")
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
        
        # Load required library
        library("HDTD")
        
        # 1. Load the transposable dataset
        # The input file 'user_data.csv' is expected to be in the working directory.
        # It is a matrix of dimensions row_vars x (col_vars * N), stacked column-wise.
        if (!file.exists("user_data.csv")) {
          stop("Error: 'user_data.csv' not found in the working directory.")
        }
        
        # Read the CSV file
        user_data <- read.csv("user_data.csv", row.names = 1, check.names = FALSE)
        user_matrix <- as.matrix(user_data)
        
        # Determine the sample size N (number of subjects)
        # We attempt to auto-detect N from the column names (e.g., "adrenal.1", "cerebrum.1" -> subject 1)
        cols <- colnames(user_matrix)
        suffixes <- sub(".*\\\\.", "", cols)
        suppressWarnings(nums <- as.integer(suffixes))
        
        if (!all(is.na(nums))) {
          N <- length(unique(nums[!is.na(nums)]))
        } else {
          # Try underscore delimiter as fallback
          suffixes_us <- sub(".*_", "", cols)
          suppressWarnings(nums_us <- as.integer(suffixes_us))
          if (!all(is.na(nums_us))) {
            N <- length(unique(nums_us[!is.na(nums_us)]))
          } else {
            # Stop if N cannot be determined from column names
            stop("Error: Cannot determine sample size N from column names. Please ensure column names contain subject identifiers (e.g., 'tissue.1' or 'tissue_1').")
          }
        }
        
        # 2. Estimate row and column covariance matrices with shrinkage using covmat.hat
        est_cov_mat <- covmat.hat(datamat = user_matrix, N = N)
        
        # 3. Extract the estimated column covariance matrix
        col_cov <- round(est_cov_mat\$cols.covmat, 3)
        
        # Save the estimated covariance matrices to CSV files
        write.csv(as.data.frame(est_cov_mat\$rows.covmat), "estimated_row_covariance.csv", row.names = TRUE)
        write.csv(as.data.frame(col_cov), "estimated_column_covariance.csv", row.names = TRUE)
        
        # Save the complete estimation object as an RDS file
        saveRDS(est_cov_mat, "estimated_covariance_structure.rds")
        
        # 4. Perform hypothesis tests (diagonality, sphericity, identity) on the covariance matrix using covmat.ts
        # Capture the output of the hypothesis tests and write to a text file
        sink("covariance_hypothesis_tests.txt")
        cat("=== COVARIANCE HYPOTHESIS TESTS ===\n\n")
        test_results <- covmat.ts(datamat = user_matrix, N = N, voi = "columns")
        print(test_results)
        sink()
        
        # Also print the test results to standard output
        cat("\n=== COVARIANCE HYPOTHESIS TESTS ===\n")
        print(test_results)
        cat("\nAnalysis complete. Outputs saved to 'estimated_row_covariance.csv', 'estimated_column_covariance.csv', 'estimated_covariance_structure.rds', and 'covariance_hypothesis_tests.txt'.\n")

    writeLines(c(
        '"BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS":',
        paste0('    HDTD: ', as.character(packageVersion('HDTD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covariance_structure_analysis.csv versions.yml
    """
}

workflow BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_data.csv ] ]

    main:
    BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS.out.tables
    plots    = BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS.out.plots
    objects  = BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS.out.objects
    versions = BIOC_HDTD_COVARIANCE_STRUCTURE_ANALYSIS.out.versions
}
