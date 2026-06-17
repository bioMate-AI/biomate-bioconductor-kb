#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bcSeq — barcode_alignment_edit
// Align short reads to a reference barcode library using edit distance (allowing insertions and deletions) with customizable penalty parameters.
// Input: readFile.fastq, libFile.fasta
// Container: quay.io/biocontainers/bioconductor-bcseq:1.32.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, bcSeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define paths for the input read file, reference barcode
//  * 2. [Visualization & Output] Run bcSeq_edit with specified mismatch tolerance,
//  * 3. [Visualization & Output] Read the resulting CSV file containing barcode sequences

nextflow.enable.dsl = 2

process BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT {
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
    .bm_deps <- c("Matrix", "bcSeq")
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
    library(Matrix)
    library(bcSeq)
    
    # --- Define paths for the input read file, reference barcode ---
    ReadFile <- "readFile.fastq"
    BarFile  <- "libFile.fasta"
    outFile  <- "count.csv"
    
    # --- Run bcSeq_edit with specified mismatch tolerance, ---
    res <- bcSeq_edit(ReadFile, BarFile, outFile, misMatch = 2,
        tMat = NULL, numThread = 4, count_only = TRUE,
        gap_left = 2, ext_left = 1, gap_right = 2, ext_right = 1,
        pen_max = 7)
    
    # --- Read the resulting CSV file containing barcode sequences ---
    res <- read.csv(outFile, header=FALSE)
    
    # Display the first few rows of the results
    print(res[1:3,])
    
    # Save the final results as an RDS object for downstream analysis
    saveRDS(res, file = "alignment_counts.rds")

    writeLines(c(
        '"BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT":',
        paste0('    bcSeq: ', as.character(packageVersion('bcSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_barcode_alignment_edit.csv versions.yml
    """
}

workflow BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ readFile.fastq, libFile.fasta ] ]

    main:
    BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT(ch_input)

    emit:
    tables   = BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT.out.tables
    plots    = BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT.out.plots
    objects  = BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT.out.objects
    versions = BIOC_BCSEQ_BARCODE_ALIGNMENT_EDIT.out.versions
}
