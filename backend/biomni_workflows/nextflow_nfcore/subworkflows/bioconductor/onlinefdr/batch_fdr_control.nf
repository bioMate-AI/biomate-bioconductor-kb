#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: onlineFDR — batch_fdr_control
// Control the False Discovery Rate (FDR) when hypothesis tests are performed and arrive in distinct batches.
// Input: sample.df
// Container: quay.io/biocontainers/bioconductor-onlinefdr:2.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: onlineFDR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the dataset with p-values grouped into sequential
//  * 2. [Input & Preparation] Run the BatchPRDS algorithm to control FDR for positively
//  * 3. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_ONLINEFDR_BATCH_FDR_CONTROL {
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
    .bm_deps <- c("onlineFDR")
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
    library(onlineFDR)
    
    # --- Define the dataset with p-values grouped into sequential ---
    # Read the user input file 'sample.df' from the working directory.
    # We use a robust reader that handles RDS, CSV, or tab-delimited formats.
    if (file.exists("sample.df")) {
      sample.df <- tryCatch({
        readRDS("sample.df")
      }, error = function(e) {
        tryCatch({
          read.csv("sample.df", stringsAsFactors = FALSE)
        }, error = function(e2) {
          read.table("sample.df", header = TRUE, stringsAsFactors = FALSE)
        })
      })
    } else {
      stop("Required input file 'sample.df' not found in the working directory.")
    }
    
    # Ensure the input has the required columns: 'id', 'pval', and 'batch'
    required_cols <- c("id", "pval", "batch")
    missing_cols <- setdiff(required_cols, colnames(sample.df))
    if (length(missing_cols) > 0) {
      stop(paste("Input data is missing required column(s):", paste(missing_cols, collapse = ", ")))
    }
    
    # --- Run the BatchPRDS algorithm to control FDR for positively ---
    # We reproduce the documented function call and argument names exactly.
    batchprds_results <- BatchPRDS(sample.df)
    
    # --- Write named output files for the meaningful results ---
    # Save the full results table as a CSV file
    write.csv(batchprds_results, "batchprds_results.csv", row.names = FALSE)
    
    # Save the results as an RDS object for downstream R analyses
    saveRDS(batchprds_results, "batchprds_results.rds")
    
    # Generate a PDF plot visualizing the p-values, adjusted significance thresholds, and rejections
    pdf("batchprds_plot.pdf", width = 8, height = 6)
    plot(
      batchprds_results\$pval, 
      type = "p", 
      pch = 19, 
      col = ifelse(batchprds_results\$R == 1, "red", "black"),
      xlab = "Hypothesis Index", 
      ylab = "p-value / Alpha threshold",
      main = "BatchPRDS Results: p-values and Thresholds"
    )
    lines(batchprds_results\$alphai, type = "s", col = "blue", lwd = 2)
    legend(
      "topright", 
      legend = c("Rejected", "Not Rejected", "Threshold (alphai)"),
      col = c("red", "black", "blue"), 
      pch = c(19, 19, NA), 
      lty = c(NA, NA, 1), 
      lwd = c(NA, NA, 2)
    )
    dev.off()

    writeLines(c(
        '"BIOC_ONLINEFDR_BATCH_FDR_CONTROL":',
        paste0('    onlineFDR: ', as.character(packageVersion('onlineFDR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_fdr_control.csv versions.yml
    """
}

workflow BIOC_ONLINEFDR_BATCH_FDR_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.df ] ]

    main:
    BIOC_ONLINEFDR_BATCH_FDR_CONTROL(ch_input)

    emit:
    tables   = BIOC_ONLINEFDR_BATCH_FDR_CONTROL.out.tables
    plots    = BIOC_ONLINEFDR_BATCH_FDR_CONTROL.out.plots
    objects  = BIOC_ONLINEFDR_BATCH_FDR_CONTROL.out.objects
    versions = BIOC_ONLINEFDR_BATCH_FDR_CONTROL.out.versions
}
