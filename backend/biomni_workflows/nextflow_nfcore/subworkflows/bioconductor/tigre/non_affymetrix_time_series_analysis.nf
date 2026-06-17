#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tigre — non_affymetrix_time_series_analysis
// Preprocess non-Affymetrix expression data or data without associated uncertainty information.
// Input: data, times, experiments
// Container: quay.io/biocontainers/bioconductor-tigre:1.64.0--r45h01b2380_0
// R packages: tigre
// Bioconductor: 3.20 | R: 4.4
// Requires: tigre
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Save the complete ExpressionTimeSeries object as an RDS
//  * 2. [Core Analysis] Export the processed expression matrix to a CSV file

nextflow.enable.dsl = 2

process BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS {
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
    .bm_deps <- c("tigre")
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
    
    # Load the required Bioconductor package
    library(tigre)
    
    # Read the user input files from the working directory
    # 'data' is a matrix of raw expression values (genes as rows, samples as columns)
    data_df <- read.table("data", header=TRUE, row.names=1, check.names=FALSE)
    data <- as.matrix(data_df)
    
    # 'times' is a vector of observation times
    times <- as.numeric(scan("times", quiet=TRUE))
    
    # 'experiments' is a vector of experiment indices
    experiments <- as.integer(scan("experiments", quiet=TRUE))
    
    # Preprocess raw data using processRawData
    procData <- processRawData(data, times=times,
                               experiments=experiments)
    
    # Save the meaningful results
    # --- Save the complete ExpressionTimeSeries object as an RDS ---
    saveRDS(procData, file="procData.rds")
    
    # --- Export the processed expression matrix to a CSV file ---
    tryCatch({
      write.csv(exprs(procData), file="processed_expression.csv", row.names=TRUE)
    }, error = function(e) {
      # Fallback if exprs() is not supported on the returned object
      write.csv(as.matrix(procData), file="processed_expression.csv", row.names=TRUE)
    })
    
    cat("Pipeline completed successfully. Outputs saved to 'procData.rds' and 'processed_expression.csv'.\n")

    writeLines(c(
        '"BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS":',
        paste0('    tigre: ', as.character(packageVersion('tigre')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_affymetrix_time_series_analysis.csv versions.yml
    """
}

workflow BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data, times, experiments ] ]

    main:
    BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.tables
    plots    = BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.plots
    objects  = BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.objects
    versions = BIOC_TIGRE_NON_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.versions
}
