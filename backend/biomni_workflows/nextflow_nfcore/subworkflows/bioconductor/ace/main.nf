#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ACE — run_ace_pipeline
// Run the full absolute copy number estimation pipeline on a directory of BAM or RDS files to generate diagnostic plots and fitpicker tables.
// Input: Aligned BAM files in a directory OR segmented QDNAseq RDS files.
// Container: quay.io/biocontainers/bioconductor-ace:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ACE, Biobase, QDNAseq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run runACE to process files, perform segmentation, and
//  * 2. [Visualization & Output] Inspect output directories, likelyfits, and fitpicker

nextflow.enable.dsl = 2

process BIOC_ACE_RUN_ACE_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("ACE", "Biobase", "QDNAseq", "ggplot2")
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
    library(ACE)
    library(Biobase)
    library(QDNAseq)
    library(ggplot2)
    
    # Define the userpath as the current working directory containing the input files
    userpath <- getwd()
    
    # Detect input files in the working directory
    bam_files <- list.files(userpath, pattern = "\\\\.bam\$", ignore.case = TRUE)
    rds_files <- list.files(userpath, pattern = "\\\\.rds\$", ignore.case = TRUE)
    
    # --- Run runACE to process files, perform segmentation, and ---
    if (length(bam_files) > 0) {
      message("Found BAM files in the working directory. Running runACE for BAM workflow...")
      runACE(userpath, filetype='bam', binsizes = c(100, 1000),
             ploidies = c(2,4), imagetype='png')
    } else if (length(rds_files) > 0) {
      message("Found RDS files in the working directory. Running runACE for RDS workflow...")
      runACE(userpath, filetype='rds', ploidies = c(2,4), imagetype='png')
    } else {
      stop("Error: No BAM or RDS files found in the working directory. Please provide aligned BAM files or segmented QDNAseq RDS files.")
    }
    
    # --- Inspect output directories, likelyfits, and fitpicker ---
    message("Searching for generated fitpicker tables and diagnostic plots...")
    
    fitpicker_files <- list.files(userpath, pattern = "fitpicker", recursive = TRUE, full.names = TRUE)
    if (length(fitpicker_files) > 0) {
      message("Processing fitpicker tables:")
      for (f in fitpicker_files) {
        message("Reading: ", f)
        tryCatch({
          tbl <- read.delim(f, header = TRUE, sep = "\t")
          print(head(tbl))
          # Write a clean CSV copy of the fitpicker table to the working directory
          out_name <- paste0("summary_", gsub("\\\\.tsv\$|\\\\.txt\$", "", basename(f)), ".csv")
          write.csv(tbl, file = out_name, row.names = FALSE)
          message("Saved CSV summary to: ", out_name)
        }, error = function(e) {
          warning("Could not process fitpicker file: ", f, " - ", e\$message)
        })
      }
    } else {
      message("No fitpicker tables found. Please check if runACE completed successfully.")
    }
    
    # List generated diagnostic plots
    plots <- list.files(userpath, pattern = "\\\\.png\$", recursive = TRUE, full.names = TRUE)
    if (length(plots) > 0) {
      message("Generated diagnostic plots:")
      for (p in plots) {
        message("- ", p)
      }
    } else {
      message("No diagnostic plots found.")
    }
    
    message("ACE pipeline execution completed.")

    writeLines(c(
        '"BIOC_ACE_RUN_ACE_PIPELINE":',
        paste0('    ACE: ', as.character(packageVersion('ACE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_run_ace_pipeline.csv versions.yml
    """
}

workflow BIOC_ACE_RUN_ACE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Aligned BAM files in a directory OR segmented QDNAseq RDS files. ] ]

    main:
    BIOC_ACE_RUN_ACE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ACE_RUN_ACE_PIPELINE.out.tables
    plots    = BIOC_ACE_RUN_ACE_PIPELINE.out.plots
    objects  = BIOC_ACE_RUN_ACE_PIPELINE.out.objects
    versions = BIOC_ACE_RUN_ACE_PIPELINE.out.versions
}
