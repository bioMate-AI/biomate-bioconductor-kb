#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — stringtie_import
// Import transcript coverage and abundance estimates from StringTie.
// Input: t_data.ctab
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// R packages: readr, tximport
// Bioconductor: 3.20 | R: 4.4
// Requires: readr, tximport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read a sample file to extract transcript-to-gene mapping
//  * 2. [Input & Preparation] Import StringTie files using tximport with type="stringtie"

nextflow.enable.dsl = 2

process BIOC_TXIMPORT_STRINGTIE_IMPORT {
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
    .bm_deps <- c("readr", "tximport")
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
    library(readr)
    library(tximport)
    
    # Define the input file(s) as specified by the user
    # The pipeline expects 't_data.ctab' in the working directory
    files <- "t_data.ctab"
    
    # Verify that the input file exists
    if (!file.exists(files[1])) {
      stop("Required input file 't_data.ctab' not found in the working directory.")
    }
    
    # Name the files vector (useful for column naming in tximport output)
    names(files) <- "sample1"
    
    # Stage 1: Read a sample file to extract transcript-to-gene mapping
    tmp <- read_tsv(files[1])
    tx2gene <- tmp[,c("t_name","gene_name")]
    
    # Stage 2: Import StringTie files using tximport with type="stringtie"
    txi <- tximport(files, type="stringtie", tx2gene=tx2gene)
    
    # Write named output files for the meaningful results
    # 1. Save the complete tximport list object as an RDS file
    saveRDS(txi, file = "txi_stringtie.rds")
    
    # 2. Export the gene-level matrices to CSV files
    write.csv(as.data.frame(txi\$counts), file = "stringtie_gene_counts.csv", row.names = TRUE)
    write.csv(as.data.frame(txi\$abundance), file = "stringtie_gene_abundance.csv", row.names = TRUE)
    write.csv(as.data.frame(txi\$length), file = "stringtie_gene_length.csv", row.names = TRUE)
    
    message("StringTie import completed successfully. Outputs saved to 'txi_stringtie.rds' and associated CSV files.")

    writeLines(c(
        '"BIOC_TXIMPORT_STRINGTIE_IMPORT":',
        paste0('    tximport: ', as.character(packageVersion('tximport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stringtie_import.csv versions.yml
    """
}

workflow BIOC_TXIMPORT_STRINGTIE_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ t_data.ctab ] ]

    main:
    BIOC_TXIMPORT_STRINGTIE_IMPORT(ch_input)

    emit:
    tables   = BIOC_TXIMPORT_STRINGTIE_IMPORT.out.tables
    plots    = BIOC_TXIMPORT_STRINGTIE_IMPORT.out.plots
    objects  = BIOC_TXIMPORT_STRINGTIE_IMPORT.out.objects
    versions = BIOC_TXIMPORT_STRINGTIE_IMPORT.out.versions
}
