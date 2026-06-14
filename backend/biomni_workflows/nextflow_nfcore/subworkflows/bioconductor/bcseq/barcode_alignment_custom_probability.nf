#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bcSeq — barcode_alignment_custom_probability
// Align short reads using edit distance with a user-defined R or Rcpp function to customize alignment probability calculations.
// Input: sampleFile.fastq, libFile.fasta
// Container: quay.io/biocontainers/bioconductor-bcseq:1.32.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, bcSeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a custom probability function in R
//  * 2. [Input & Preparation] Run bcSeq_edit passing the custom function to the

nextflow.enable.dsl = 2

process BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY {
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
    .bm_deps <- c("bcSeq", "Matrix")
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
    library(bcSeq)
    library(Matrix)
    
    # Define input and output file paths as specified by the user
    sampleFile <- "sampleFile.fastq"
    libFile    <- "libFile.fasta"
    outFile    <- "count_custom.csv"
    
    # Verify that the required user input files exist in the working directory
    if (!file.exists(sampleFile)) {
        stop(paste("Required input file missing:", sampleFile))
    }
    if (!file.exists(libFile)) {
        stop(paste("Required input file missing:", libFile))
    }
    
    # --- Define a custom probability function in R ---
    customizeP <- function(max_pen, prob, pen_val)
    {
        prob * (1 - log(2) + log(1 + max_pen / (max_pen + pen_val) ) )
    }
    
    # --- Run bcSeq_edit passing the custom function to the ---
    # All function and argument names are reproduced exactly from the documented workflow
    bcSeq_edit(sampleFile, libFile, outFile, misMatch = 2, tMat = NULL,
        numThread = 4, count_only = TRUE, userProb = customizeP,
        gap_left = 2, ext_left = 1, gap_right = 2,
        ext_right = 1, pen_max = 5)
    
    # Read the output, format it, and write meaningful output files
    if (file.exists(outFile)) {
        alignment_results <- read.csv(outFile, header = FALSE)
        colnames(alignment_results) <- c("Barcode", "Count")
        
        # Save formatted CSV and RDS objects
        write.csv(alignment_results, "alignment_results_formatted.csv", row.names = FALSE)
        saveRDS(alignment_results, "alignment_results.rds")
    } else {
        warning("Output file was not created. Check alignment settings or input file formats.")
    }

    writeLines(c(
        '"BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY":',
        paste0('    bcSeq: ', as.character(packageVersion('bcSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_barcode_alignment_custom_probability.csv versions.yml
    """
}

workflow BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleFile.fastq, libFile.fasta ] ]

    main:
    BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY(ch_input)

    emit:
    tables   = BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY.out.tables
    plots    = BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY.out.plots
    objects  = BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY.out.objects
    versions = BIOC_BCSEQ_BARCODE_ALIGNMENT_CUSTOM_PROBABILITY.out.versions
}
