#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: supersigs — partial_signature_adjustment
// Remove the contribution of a supervised signature from a mutation data frame to adjust for a confounding factor.
// Input: input_dt, supersig
// Container: quay.io/biocontainers/bioconductor-supersigs:1.18.0--r45hdfd78af_0
// R packages: supersigs
// Bioconductor: 3.20 | R: 4.4
// Requires: supersigs
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Adjust the mutation matrix by removing the signature's contribution using partial_signature

nextflow.enable.dsl = 2

process BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("supersigs")
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
    library(supersigs)
    
    # Read user input files from the working directory
    if (file.exists("input_dt.csv")) {
      input_dt <- read.csv("input_dt.csv", check.names = FALSE)
    } else if (file.exists("input_dt.rds")) {
      input_dt <- readRDS("input_dt.rds")
    } else {
      stop("Required input file 'input_dt.csv' or 'input_dt.rds' not found in the working directory.")
    }
    
    if (file.exists("supersig.rds")) {
      supersig <- readRDS("supersig.rds")
    } else {
      stop("Required input file 'supersig.rds' not found in the working directory.")
    }
    
    # Execute the documented workflow step
    adjusted_dt <- partial_signature(data = input_dt, object = supersig)
    
    # Write the meaningful results to output files
    write.csv(adjusted_dt, "adjusted_dt.csv", row.names = FALSE)
    saveRDS(adjusted_dt, "adjusted_dt.rds")

    writeLines(c(
        '"BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT":',
        paste0('    supersigs: ', as.character(packageVersion('supersigs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_partial_signature_adjustment.csv versions.yml
    """
}

workflow BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_dt, supersig ] ]

    main:
    BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT(ch_input)

    emit:
    tables   = BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT.out.tables
    plots    = BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT.out.plots
    objects  = BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT.out.objects
    versions = BIOC_SUPERSIGS_PARTIAL_SIGNATURE_ADJUSTMENT.out.versions
}
