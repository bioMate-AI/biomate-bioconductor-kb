#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RnaSeqSampleSize — user_prior_data_estimation
// Estimate power or sample size using the user's own pilot RNA-seq count matrix.
// Input: dataMatrix
// Container: quay.io/biocontainers/bioconductor-rnaseqsamplesize:2.20.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RnaSeqSampleSize
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Estimate gene read count and dispersion distribution using est_count_dispersion
//  * 2. [Core Analysis] Estimate power using est_power_distribution with the estimated distribution object

nextflow.enable.dsl = 2

process BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION {
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
    .bm_deps <- c("RnaSeqSampleSize")
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
        
        # Load required library
        library(RnaSeqSampleSize)
        
        # 1. Read User Input
        # The pipeline expects 'dataMatrix.csv', 'dataMatrix.tsv', or 'dataMatrix.txt' in the working directory.
        input_file <- NULL
        for (ext in c("csv", "tsv", "txt")) {
          filename <- paste0("dataMatrix.", ext)
          if (file.exists(filename)) {
            input_file <- filename
            break
          }
        }
        
        if (is.null(input_file)) {
          stop("Required input file (dataMatrix.csv, dataMatrix.tsv, or dataMatrix.txt) not found in the working directory.")
        }
        
        # Read the matrix
        if (grepl("\\\\.csv\$", input_file)) {
          dataMatrix <- as.matrix(read.csv(input_file, row.names = 1, check.names = FALSE))
        } else if (grepl("\\\\.tsv\$", input_file)) {
          dataMatrix <- as.matrix(read.delim(input_file, row.names = 1, check.names = FALSE))
        } else {
          dataMatrix <- as.matrix(read.table(input_file, header = TRUE, row.names = 1, check.names = FALSE))
        }
        
        # Ensure dataMatrix is numeric
        class(dataMatrix) <- "numeric"
        
        # Determine group vector dynamically based on the number of columns
        # If column names contain "control" or "treatment" (case-insensitive), use that to assign 0 and 1.
        # Otherwise, split the samples 50/50.
        if (any(grepl("treatment", colnames(dataMatrix), ignore.case = TRUE))) {
          group_vector <- as.integer(grepl("treatment", colnames(dataMatrix), ignore.case = TRUE))
        } else if (any(grepl("control", colnames(dataMatrix), ignore.case = TRUE))) {
          group_vector <- as.integer(!grepl("control", colnames(dataMatrix), ignore.case = TRUE))
        } else {
          n_samples <- ncol(dataMatrix)
          group_vector <- c(rep(0, floor(n_samples / 2)), rep(1, ceiling(n_samples / 2)))
        }
        
        # 2. Estimate gene read count and dispersion distribution
        dataMatrixDistribution <- est_count_dispersion(dataMatrix, group = group_vector)
        
        # Save the distribution object
        saveRDS(dataMatrixDistribution, "dataMatrixDistribution.rds")
        
        # 3. Estimate power using the estimated distribution object
        power_result <- est_power_distribution(n = 65, f = 0.01, rho = 2, distributionObject = dataMatrixDistribution, repNumber = 100)
        
        # Save the power estimation results
        saveRDS(power_result, "power_estimation_results.rds")
        write.csv(data.frame(Power = power_result), "power_estimation_results.csv", row.names = FALSE)
        
        cat("Pipeline completed successfully. Results saved to 'dataMatrixDistribution.rds', 'power_estimation_results.rds', and 'power_estimation_results.csv'.\n")

    writeLines(c(
        '"BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION":',
        paste0('    RnaSeqSampleSize: ', as.character(packageVersion('RnaSeqSampleSize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_user_prior_data_estimation.csv versions.yml
    """
}

workflow BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataMatrix ] ]

    main:
    BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION.out.tables
    plots    = BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION.out.plots
    objects  = BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION.out.objects
    versions = BIOC_RNASEQSAMPLESIZE_USER_PRIOR_DATA_ESTIMATION.out.versions
}
