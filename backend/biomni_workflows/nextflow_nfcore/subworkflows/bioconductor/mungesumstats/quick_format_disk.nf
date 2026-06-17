#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MungeSumstats — quick_format_disk
// Quickly standardise column headers and write the data to disk without running the full QC pipeline.
// Input: eduAttainOkbay.txt
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// R packages: MungeSumstats
// Bioconductor: 3.20 | R: 4.4
// Requires: MungeSumstats
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the summary statistics file and standardise headers
//  * 2. [Visualization & Output] Write the standardised data to disk as a compressed,

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK {
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
    .bm_deps <- c("MungeSumstats")
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
    library(MungeSumstats)
    
    # Define input path from working directory
    eduAttainOkbayPth <- "eduAttainOkbay.txt"
    
    # Define output path in the working directory
    formatted_path <- "eduAttainOkbay_standardised.tsv.gz"
    
    # --- Read the summary statistics file and standardise headers ---
    dat <- MungeSumstats::read_sumstats(path = eduAttainOkbayPth, standardise_headers = TRUE)
    
    # --- Write the standardised data to disk as a compressed, ---
    formatted_path <- MungeSumstats::write_sumstats(sumstats_dt = dat, save_path = formatted_path, tabix_index = TRUE, write_vcf = FALSE, return_path = TRUE)
    
    # Print the final path of the formatted file
    cat("Formatted summary statistics saved to:", formatted_path, "\n")

    writeLines(c(
        '"BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK":',
        paste0('    MungeSumstats: ', as.character(packageVersion('MungeSumstats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_format_disk.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eduAttainOkbay.txt ] ]

    main:
    BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.tables
    plots    = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.plots
    objects  = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.objects
    versions = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.versions
}
