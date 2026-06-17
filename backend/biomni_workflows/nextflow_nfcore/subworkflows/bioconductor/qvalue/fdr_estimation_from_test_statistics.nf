#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qvalue — fdr_estimation_from_test_statistics
// Calculate empirical p-values from observed and null test statistics, and then estimate q-values and local FDR.
// Input: hedenfalk$stat, hedenfalk$stat0
// Container: quay.io/biocontainers/bioconductor-qvalue:2.42.0--r45hdfd78af_0
// R packages: qvalue
// Bioconductor: 3.20 | R: 4.4
// Requires: qvalue
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input statistics
//  * 2. [Core Analysis] Calculate empirical p-values using the empPvals function
//  * 3. [Core Analysis] Run the qvalue function on the calculated p-values to estimate FDR

nextflow.enable.dsl = 2

process BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS {
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
    .bm_deps <- c("qvalue")
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
    
    # Load the required library
    library(qvalue)
    
    # Helper function to robustly read a vector from various possible file names/extensions
    read_vector <- function(base_names) {
      extensions <- c("", ".csv", ".txt", ".tsv")
      for (base in base_names) {
        for (ext in extensions) {
          file_path <- paste0(base, ext)
          if (file.exists(file_path)) {
            # Try reading as a simple scan first
            val <- tryCatch({
              scan(file_path, quiet = TRUE)
            }, error = function(e) NULL)
            if (!is.null(val) && length(val) > 0) {
              return(val)
            }
            # Try reading as a single-column CSV
            val <- tryCatch({
              as.numeric(read.csv(file_path, header = FALSE)[[1]])
            }, error = function(e) NULL)
            if (!is.null(val) && length(val) > 0) {
              return(val)
            }
          }
        }
      }
      stop(paste("Could not find or read vector file from options:", paste(base_names, collapse = ", ")))
    }
    
    # Helper function to robustly read a matrix from various possible file names/extensions
    read_matrix <- function(base_names) {
      extensions <- c("", ".csv", ".txt", ".tsv")
      for (base in base_names) {
        for (ext in extensions) {
          file_path <- paste0(base, ext)
          if (file.exists(file_path)) {
            # Try reading as a table
            val <- tryCatch({
              as.matrix(read.table(file_path, header = FALSE))
            }, error = function(e) NULL)
            if (!is.null(val) && ncol(val) > 0) {
              return(val)
            }
            # Try reading as a CSV
            val <- tryCatch({
              as.matrix(read.csv(file_path, header = FALSE))
            }, error = function(e) NULL)
            if (!is.null(val) && ncol(val) > 0) {
              return(val)
            }
          }
        }
      }
      stop(paste("Could not find or read matrix file from options:", paste(base_names, collapse = ", ")))
    }
    
    # 1. Load the input statistics from the working directory
    obs_stats <- read_vector(c("hedenfalk\$stat", "hedenfalk_stat", "stat"))
    null_stats <- read_matrix(c("hedenfalk\$stat0", "hedenfalk_stat0", "stat0"))
    
    # 2. Calculate empirical p-values using the empPvals function
    pvalues <- empPvals(stat = obs_stats, stat0 = null_stats)
    
    # 3. Run the qvalue function on the calculated p-values to estimate FDR
    qobj <- qvalue(p = pvalues)
    
    # 4. Write named output files for the meaningful results
    # Save the main results as a CSV table
    output_df <- data.frame(
      observed_statistic = obs_stats,
      pvalue = qobj\$pvalues,
      qvalue = qobj\$qvalues,
      local_fdr = qobj\$lfdr
    )
    write.csv(output_df, "qvalue_results.csv", row.names = FALSE)
    
    # Save the full qvalue object as an RDS file
    saveRDS(qobj, "qvalue_object.rds")
    
    # Save the summary text output
    sink("qvalue_summary.txt")
    cat("=== Q-VALUE ANALYSIS SUMMARY ===\n\n")
    summary(qobj)
    cat("\nEstimated proportion of true null hypotheses (pi0):", qobj\$pi0, "\n")
    sink()
    
    # Save diagnostic and visualization plots to a PDF
    pdf("qvalue_plots.pdf", width = 8, height = 8)
    plot(qobj)
    hist(qobj)
    dev.off()

    writeLines(c(
        '"BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS":',
        paste0('    qvalue: ', as.character(packageVersion('qvalue')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fdr_estimation_from_test_statistics.csv versions.yml
    """
}

workflow BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hedenfalk$stat, hedenfalk$stat0 ] ]

    main:
    BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS(ch_input)

    emit:
    tables   = BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS.out.tables
    plots    = BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS.out.plots
    objects  = BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS.out.objects
    versions = BIOC_QVALUE_FDR_ESTIMATION_FROM_TEST_STATISTICS.out.versions
}
