#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HDTD — mean_matrix_analysis
// Test and estimate the mean relationship of row variables across column variables in transposable data.
// Input: user_data.csv
// Container: quay.io/biocontainers/bioconductor-hdtd:1.44.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HDTD
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the transposable dataset
//  * 2. [Core Analysis] Test for constant mean vector across all columns using meanmat.ts
//  * 3. [Core Analysis] Reorder columns using orderdata to group specific columns of interest
//  * 4. [Core Analysis] Test for constant mean vector within specific column groups using meanmat.ts with group.sizes
//  * 5. [Core Analysis] Estimate the unstructured mean matrix using meanmat.hat

nextflow.enable.dsl = 2

process BIOC_HDTD_MEAN_MATRIX_ANALYSIS {
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
        
        # Load the required library
        library("HDTD")
        
        # Read the user-provided transposable dataset
        # The file 'user_data.csv' is expected to have row names in the first column
        VEGFmouse <- as.matrix(read.csv("user_data.csv", row.names = 1, check.names = FALSE))
        
        # Infer the number of column variables and subjects from the column names
        # Assuming column names repeat for each subject, potentially with a suffix like .1 or _1
        base_colnames <- sub("[_\\\\.][0-9]+\$", "", colnames(VEGFmouse))
        col_vars <- length(unique(base_colnames))
        N_subjects <- ncol(VEGFmouse) / col_vars
        
        # 1. Test for constant mean vector across all columns
        test1 <- meanmat.ts(VEGFmouse, N = N_subjects, group.sizes = col_vars)
        
        # 2. Reorder columns to group specific columns of interest
        # Dynamically create a column order: group the first two columns (if available), 
        # and leave the rest as individual groups to avoid hardcoding dataset-specific indices.
        if (col_vars >= 2) {
            columnorder <- c(2, 1, if (col_vars > 2) 3:col_vars else NULL)
            group_sizes_test2 <- c(2, rep(1, col_vars - 2))
        } else {
            columnorder <- 1
            group_sizes_test2 <- 1
        }
        VEGForder <- orderdata(VEGFmouse, N = N_subjects, order.cols = columnorder)
        
        # 3. Test for constant mean vector within specific column groups
        test2 <- meanmat.ts(VEGForder, N = N_subjects, group.sizes = group_sizes_test2)
        
        # 4. Estimate the unstructured mean matrix
        sample_mean <- meanmat.hat(VEGFmouse, N = N_subjects)
        
        # Save results to output files
        saveRDS(test1, "meanmat_test_all_columns.rds")
        saveRDS(test2, "meanmat_test_grouped_columns.rds")
        saveRDS(sample_mean, "sample_mean_object.rds")
        
        # Export the estimated mean matrix to a CSV file
        write.csv(sample_mean\$estmeanmat, "estimated_mean_matrix.csv", row.names = TRUE)
        
        # Write a text summary of the analysis results
        sink("analysis_summary.txt")
        cat("=== HDTD Mean Matrix Analysis Summary ===\n\n")
        cat("1. Test for constant mean vector across all columns:\n")
        print(test1)
        cat("\n--------------------------------------------------\n\n")
        cat("2. Test for constant mean vector within specific column groups:\n")
        print(test2)
        cat("\n--------------------------------------------------\n\n")
        cat("3. Estimated Mean Matrix (First 10 rows):\n")
        print(head(sample_mean\$estmeanmat, n = 10))
        sink()

    writeLines(c(
        '"BIOC_HDTD_MEAN_MATRIX_ANALYSIS":',
        paste0('    HDTD: ', as.character(packageVersion('HDTD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mean_matrix_analysis.csv versions.yml
    """
}

workflow BIOC_HDTD_MEAN_MATRIX_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_data.csv ] ]

    main:
    BIOC_HDTD_MEAN_MATRIX_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HDTD_MEAN_MATRIX_ANALYSIS.out.tables
    plots    = BIOC_HDTD_MEAN_MATRIX_ANALYSIS.out.plots
    objects  = BIOC_HDTD_MEAN_MATRIX_ANALYSIS.out.objects
    versions = BIOC_HDTD_MEAN_MATRIX_ANALYSIS.out.versions
}
