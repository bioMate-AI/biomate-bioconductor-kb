#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: amplican — amplican_standard_pipeline
// Align amplicon reads, normalize editing events against controls, and generate comprehensive HTML reports.
// Input: config.csv, fastq_folder
// Container: quay.io/biocontainers/bioconductor-amplican:1.32.1--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: amplican
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define paths to the configuration file and fastq folder
//  * 2. [Visualization & Output] Run the complete amplican pipeline to perform alignment,
//  * 3. [Visualization & Output] Load alignment results and look up specific alignments in

nextflow.enable.dsl = 2

process BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE {
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
    .bm_deps <- c("amplican")
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
    library(amplican)
    
    # --- Define paths to the configuration file and fastq folder ---
    config <- "config.csv"
    fastq_folder <- "fastq_folder"
    results_folder <- "results_output"
    
    # Ensure output directory exists
    if (!dir.exists(results_folder)) {
      dir.create(results_folder, recursive = TRUE)
    }
    
    # --- Run the complete amplican pipeline to perform alignment, ---
    amplicanPipeline(config, fastq_folder, results_folder)
    
    # --- Load alignment results and look up specific alignments in ---
    # Dynamically locate the generated RDS alignment file to adapt the system.file call
    rds_files <- list.files(file.path(results_folder, "alignments", "temp"), pattern = "\\\\.rds\$", full.names = TRUE)
    if (length(rds_files) > 0) {
      aln <- rds_files[1]
    } else {
      stop("No alignment RDS files found in the results folder.")
    }
    
    aln <- readRDS(aln)
    
    # Write the lookup alignment output to a text file
    output_txt <- "alignment_lookup.txt"
    sink(output_txt)
    tryCatch({
      # Exact documented function call
      amplican::lookupAlignment(aln, ID = "ID_1")
    }, error = function(e) {
      # Fallback to the first ID in the user's config if "ID_1" does not exist
      config_df <- read.csv(config)
      if (nrow(config_df) > 0) {
        amplican::lookupAlignment(aln, ID = as.character(config_df\$ID[1]))
      } else {
        stop("Config file is empty.")
      }
    })
    sink()
    
    # Copy key summary files to the working directory as named outputs
    summary_source <- file.path(results_folder, "config_summary.csv")
    if (file.exists(summary_source)) {
      file.copy(summary_source, "amplican_config_summary.csv", overwrite = TRUE)
    }
    
    barcode_summary_source <- file.path(results_folder, "barcode_reads_filters.csv")
    if (file.exists(barcode_summary_source)) {
      file.copy(barcode_summary_source, "amplican_barcode_reads_filters.csv", overwrite = TRUE)
    }

    writeLines(c(
        '"BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE":',
        paste0('    amplican: ', as.character(packageVersion('amplican')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amplican_standard_pipeline.csv versions.yml
    """
}

workflow BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ config.csv, fastq_folder ] ]

    main:
    BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE.out.tables
    plots    = BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE.out.plots
    objects  = BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE.out.objects
    versions = BIOC_AMPLICAN_AMPLICAN_STANDARD_PIPELINE.out.versions
}
