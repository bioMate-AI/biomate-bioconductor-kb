#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mungesumstats — quick_format_from_disk
// Quickly standardise column headers and convert file formats without running the full QC pipeline.
// Input: eduAttainOkbay.txt
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// R packages: MungeSumstats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0"

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
    
    # Define input path (reading from the working directory as requested)
    eduAttainOkbayPth <- "eduAttainOkbay.txt"
    
    # Define output path in the working directory
    formatted_path <- "eduAttainOkbay_standardised.tsv.gz"
    
    # 1. Read in the data and standardise header names
    dat <- MungeSumstats::read_sumstats(path = eduAttainOkbayPth, standardise_headers = TRUE)
    
    # 2. Write to disk as a compressed, tab-delimited, tabix-indexed file
    formatted_path <- MungeSumstats::write_sumstats(
      sumstats_dt = dat, 
      save_path = formatted_path, 
      tabix_index = TRUE, 
      write_vcf = FALSE, 
      return_path = TRUE
    )
    
    # Print the path to the formatted file
    cat("Formatted summary statistics saved to:", formatted_path, "\n")

    writeLines(c(
        '"BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK":',
        paste0('        mungesumstats: ', as.character(packageVersion("mungesumstats")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_format_from_disk.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eduAttainOkbay.txt ] ]

    main:
    BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.tables
    plots    = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.plots
    objects  = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.objects
    versions = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.versions
}
