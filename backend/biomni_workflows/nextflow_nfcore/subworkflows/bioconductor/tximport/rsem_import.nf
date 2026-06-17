#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — rsem_import
// Import gene-level or isoform-level quantification results from RSEM.
// Input: sample.genes.results.gz
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// R packages: tximport
// Bioconductor: 3.20 | R: 4.4
// Requires: tximport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define paths to RSEM results files
//  * 2. [Input & Preparation] Import gene-level results with txIn=FALSE and txOut=FALSE, or import isoform-level results with txIn=TRUE and txOut=TRUE

nextflow.enable.dsl = 2

process BIOC_TXIMPORT_RSEM_IMPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    
    library(tximport)
    
    # 1. Define paths to RSEM results files
    gene_file <- "sample.genes.results.gz"
    isoform_file <- "sample.isoforms.results.gz"
    
    # Check if at least one input file exists
    if (!file.exists(gene_file) && !file.exists(isoform_file)) {
      stop("Error: Neither 'sample.genes.results.gz' nor 'sample.isoforms.results.gz' was found in the working directory.")
    }
    
    # 2. Import gene-level results with txIn=FALSE and txOut=FALSE
    if (file.exists(gene_file)) {
      files <- gene_file
      names(files) <- "sample1"
      
      txi.rsem <- tximport(files, type="rsem", txIn=FALSE, txOut=FALSE)
      
      # Save meaningful outputs
      saveRDS(txi.rsem, "txi_rsem_genes.rds")
      if (!is.null(txi.rsem\$counts)) {
        write.csv(txi.rsem\$counts, "rsem_gene_counts.csv", row.names=TRUE)
      }
      if (!is.null(txi.rsem\$abundance)) {
        write.csv(txi.rsem\$abundance, "rsem_gene_abundance.csv", row.names=TRUE)
      }
      if (!is.null(txi.rsem\$length)) {
        write.csv(txi.rsem\$length, "rsem_gene_length.csv", row.names=TRUE)
      }
      message("Gene-level RSEM results successfully imported and saved.")
    }
    
    # 3. Import isoform-level results with txIn=TRUE and txOut=TRUE
    if (file.exists(isoform_file)) {
      files <- isoform_file
      names(files) <- "sample1"
      
      txi.rsem <- tximport(files, type="rsem", txIn=TRUE, txOut=TRUE)
      
      # Save meaningful outputs
      saveRDS(txi.rsem, "txi_rsem_isoforms.rds")
      if (!is.null(txi.rsem\$counts)) {
        write.csv(txi.rsem\$counts, "rsem_isoform_counts.csv", row.names=TRUE)
      }
      if (!is.null(txi.rsem\$abundance)) {
        write.csv(txi.rsem\$abundance, "rsem_isoform_abundance.csv", row.names=TRUE)
      }
      if (!is.null(txi.rsem\$length)) {
        write.csv(txi.rsem\$length, "rsem_isoform_length.csv", row.names=TRUE)
      }
      message("Isoform-level RSEM results successfully imported and saved.")
    }

    writeLines(c(
        '"BIOC_TXIMPORT_RSEM_IMPORT":',
        paste0('    tximport: ', as.character(packageVersion('tximport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsem_import.csv versions.yml
    """
}

workflow BIOC_TXIMPORT_RSEM_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.genes.results.gz ] ]

    main:
    BIOC_TXIMPORT_RSEM_IMPORT(ch_input)

    emit:
    tables   = BIOC_TXIMPORT_RSEM_IMPORT.out.tables
    plots    = BIOC_TXIMPORT_RSEM_IMPORT.out.plots
    objects  = BIOC_TXIMPORT_RSEM_IMPORT.out.objects
    versions = BIOC_TXIMPORT_RSEM_IMPORT.out.versions
}
