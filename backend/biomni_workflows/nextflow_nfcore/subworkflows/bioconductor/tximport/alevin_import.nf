#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — alevin_import
// Import single-cell RNA-seq gene-by-cell count matrices quantified with Alevin.
// Input: quants_mat.gz
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// R packages: tximport
// Bioconductor: 3.20 | R: 4.4
// Requires: tximport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define path to the Alevin quants matrix file
//  * 2. [Input & Preparation] Import the matrix using tximport with type="alevin"

nextflow.enable.dsl = 2

process BIOC_TXIMPORT_ALEVIN_IMPORT {
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
    .bm_deps <- c("tximport")
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
    library(tximport)
    
    # 1. Define path to the Alevin quants matrix file
    files <- "quants_mat.gz"
    
    # 2. Import the matrix using tximport with type="alevin"
    txi <- tximport(files, type="alevin")
    
    # 3. Write named output files for the meaningful results
    # Save the complete tximport list object as an RDS file
    saveRDS(txi, file = "txi_alevin.rds")
    
    # Extract and save a summary of the imported single-cell matrix
    if ("counts" %in% names(txi)) {
      summary_info <- data.frame(
        Metric = c("Number_of_Genes", "Number_of_Cells", "Total_Estimated_Counts"),
        Value = c(nrow(txi\$counts), ncol(txi\$counts), sum(txi\$counts))
      )
      write.csv(summary_info, "alevin_import_summary.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_TXIMPORT_ALEVIN_IMPORT":',
        paste0('    tximport: ', as.character(packageVersion('tximport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alevin_import.csv versions.yml
    """
}

workflow BIOC_TXIMPORT_ALEVIN_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quants_mat.gz ] ]

    main:
    BIOC_TXIMPORT_ALEVIN_IMPORT(ch_input)

    emit:
    tables   = BIOC_TXIMPORT_ALEVIN_IMPORT.out.tables
    plots    = BIOC_TXIMPORT_ALEVIN_IMPORT.out.plots
    objects  = BIOC_TXIMPORT_ALEVIN_IMPORT.out.objects
    versions = BIOC_TXIMPORT_ALEVIN_IMPORT.out.versions
}
