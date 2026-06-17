#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximport — transcript_level_import_and_summarization
// Import transcript-level estimates without gene-level summarization, with the option to summarize to gene-level later or perform transcript-level differential ex
// Input: quant.sf.gz, tx2gene.gencode.v27.csv
// Container: quay.io/biocontainers/bioconductor-tximport:1.38.2--r45hdfd78af_0
// R packages: edgeR, readr, tximport
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, readr, tximport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import transcript-level estimates with txOut=TRUE
//  * 2. [Visualization & Output] Summarize transcript-level matrices to gene-level using summarizeToGene
//  * 3. [Input & Preparation] Alternatively, create a transcript-level DGEList with divided counts for edgeR

nextflow.enable.dsl = 2

process BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION {
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
    .bm_deps <- c("edgeR", "readr", "tximport")
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
    library(readr)
    library(edgeR)
    
    # Define input files from the working directory
    files <- "quant.sf.gz"
    names(files) <- "sample1"
    
    # 1. Import transcript-level estimates with txOut=TRUE
    txi.tx <- tximport(files, type="salmon", txOut=TRUE)
    
    # 2. Summarize transcript-level matrices to gene-level using summarizeToGene
    tx2gene <- read_csv("tx2gene.gencode.v27.csv")
    txi.sum <- summarizeToGene(txi.tx, tx2gene)
    
    # 3. Alternatively, create a transcript-level DGEList with divided counts for edgeR
    dge.tx <- DGEListFromTximport(txi.tx, divide=TRUE)
    
    # Save outputs to the working directory
    saveRDS(txi.tx, "txi_tx.rds")
    saveRDS(txi.sum, "txi_sum.rds")
    saveRDS(dge.tx, "dge_tx.rds")
    
    # Export counts as CSV tables
    write.csv(as.data.frame(txi.tx\$counts), "transcript_counts.csv", row.names=TRUE)
    write.csv(as.data.frame(txi.sum\$counts), "gene_counts.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION":',
        paste0('    tximport: ', as.character(packageVersion('tximport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_level_import_and_summarization.csv versions.yml
    """
}

workflow BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf.gz, tx2gene.gencode.v27.csv ] ]

    main:
    BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION(ch_input)

    emit:
    tables   = BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION.out.tables
    plots    = BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION.out.plots
    objects  = BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION.out.objects
    versions = BIOC_TXIMPORT_TRANSCRIPT_LEVEL_IMPORT_AND_SUMMARIZATION.out.versions
}
