#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: idr2d — one_dimensional_idr
// Identify reproducible genomic peaks between two replicates of 1D genomic data (e.g., ChIP-seq).
// Input: rep1_df, rep2_df
// Container: quay.io/biocontainers/bioconductor-idr2d:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: idr2d
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load replicate data frames
//  * 2. [Core Analysis] Estimate 1D IDR using estimate_idr1d
//  * 3. [Visualization & Output] Summarize results using summary
//  * 4. [Visualization & Output] Visualize IDR distribution and dependencies using draw_idr_distribution_histogram, draw_rank_idr_scatterplot, and draw_value_idr_s

nextflow.enable.dsl = 2

process BIOC_IDR2D_ONE_DIMENSIONAL_IDR {
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
    .bm_deps <- c("idr2d")
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
        
        # 1. Load required libraries
        library(idr2d)
        
        # 2. Load replicate data frames from user input files
        # Supports both RDS and CSV formats
        if (file.exists("rep1_df.rds")) {
          rep1_df <- readRDS("rep1_df.rds")
        } else if (file.exists("rep1_df.csv")) {
          rep1_df <- read.csv("rep1_df.csv")
        } else {
          stop("Error: Replicate 1 input file (rep1_df.rds or rep1_df.csv) not found in the working directory.")
        }
        
        if (file.exists("rep2_df.rds")) {
          rep2_df <- readRDS("rep2_df.rds")
        } else if (file.exists("rep2_df.csv")) {
          rep2_df <- read.csv("rep2_df.csv")
        } else {
          stop("Error: Replicate 2 input file (rep2_df.rds or rep2_df.csv) not found in the working directory.")
        }
        
        # 3. Estimate 1D IDR using estimate_idr1d
        idr_results <- estimate_idr1d(rep1_df, rep2_df, 
                                      value_transformation = "log")
        rep1_idr_df <- idr_results\$rep1_df
        
        # Save the primary results to disk
        saveRDS(idr_results, file = "idr_results.rds")
        write.csv(rep1_idr_df, file = "rep1_idr_df.csv", row.names = FALSE)
        
        # 4. Summarize results and save summary text
        summary_output <- capture.output(summary(idr_results))
        writeLines(summary_output, con = "idr_summary.txt")
        cat(summary_output, sep = "\n")
        
        # 5. Visualize IDR distribution and dependencies, saving plots to PDF files
        pdf("idr_distribution_histogram.pdf", width = 7, height = 7)
        tryCatch({
          print(draw_idr_distribution_histogram(rep1_idr_df))
        }, error = function(e) {
          warning("Could not plot IDR distribution histogram: ", e\$message)
        })
        dev.off()
        
        pdf("rank_idr_scatterplot.pdf", width = 7, height = 7)
        tryCatch({
          print(draw_rank_idr_scatterplot(rep1_idr_df))
        }, error = function(e) {
          warning("Could not plot rank-IDR scatterplot: ", e\$message)
        })
        dev.off()
        
        pdf("value_idr_scatterplot.pdf", width = 7, height = 7)
        tryCatch({
          print(draw_value_idr_scatterplot(rep1_idr_df))
        }, error = function(e) {
          warning("Could not plot value-IDR scatterplot: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_IDR2D_ONE_DIMENSIONAL_IDR":',
        paste0('    idr2d: ', as.character(packageVersion('idr2d')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_dimensional_idr.csv versions.yml
    """
}

workflow BIOC_IDR2D_ONE_DIMENSIONAL_IDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rep1_df, rep2_df ] ]

    main:
    BIOC_IDR2D_ONE_DIMENSIONAL_IDR(ch_input)

    emit:
    tables   = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.tables
    plots    = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.plots
    objects  = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.objects
    versions = BIOC_IDR2D_ONE_DIMENSIONAL_IDR.out.versions
}
