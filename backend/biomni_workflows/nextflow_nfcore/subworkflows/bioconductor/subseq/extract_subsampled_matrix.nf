#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: subSeq — extract_subsampled_matrix
// Generate and extract the exact subsampled count matrix at a specific proportion from a previous run for detailed manual inspection.
// Input: hammer.counts, seed
// Container: quay.io/biocontainers/bioconductor-subseq:1.40.0--r45hdfd78af_0
// R packages: subSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: subSeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Execute Documented Workflow
//  * 3. [Core Analysis] Write Outputs

nextflow.enable.dsl = 2

process BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX {
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
    .bm_deps <- c("subSeq")
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
    library(subSeq)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -----------------------------------------------------------------------------
    
    # Read hammer.counts (matrix of raw RNA-seq counts)
    if (file.exists("hammer.counts")) {
      hammer.counts <- tryCatch({
        readRDS("hammer.counts")
      }, error = function(e) {
        as.matrix(read.table("hammer.counts", header = TRUE, row.names = 1, check.names = FALSE))
      })
    } else if (file.exists("hammer.counts.rds")) {
      hammer.counts <- readRDS("hammer.counts.rds")
    } else if (file.exists("hammer.counts.csv")) {
      hammer.counts <- as.matrix(read.csv("hammer.counts.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Required input file 'hammer.counts' not found in the working directory.")
    }
    
    # Read seed (random seed retrieved from a previous subsamples object)
    if (file.exists("seed")) {
      seed <- tryCatch({
        readRDS("seed")
      }, error = function(e) {
        as.integer(readLines("seed", n = 1))
      })
    } else if (file.exists("seed.rds")) {
      seed <- readRDS("seed.rds")
    } else if (file.exists("seed.txt")) {
      seed <- as.integer(readLines("seed.txt", n = 1))
    } else {
      stop("Error: Required input file 'seed' not found in the working directory.")
    }
    
    # Ensure hammer.counts is a matrix
    hammer.counts <- as.matrix(hammer.counts)
    
    # -----------------------------------------------------------------------------
    # --- Execute Documented Workflow ---
    # -----------------------------------------------------------------------------
    
    submatrix = generateSubsampledMatrix(hammer.counts, .1, seed=seed)
    dim(submatrix)
    sum(submatrix)
    
    # -----------------------------------------------------------------------------
    # --- Write Outputs ---
    # -----------------------------------------------------------------------------
    
    # Save the generated subsampled matrix
    write.csv(submatrix, "submatrix.csv", row.names = TRUE)
    saveRDS(submatrix, "submatrix.rds")
    
    # Save summary statistics to a text file
    summary_file <- file("submatrix_summary.txt", "w")
    writeLines(paste("Dimensions (rows x columns):", paste(dim(submatrix), collapse = " x ")), summary_file)
    writeLines(paste("Total sum of counts:", sum(submatrix)), summary_file)
    close(summary_file)

    writeLines(c(
        '"BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX":',
        paste0('    subSeq: ', as.character(packageVersion('subSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_extract_subsampled_matrix.csv versions.yml
    """
}

workflow BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hammer.counts, seed ] ]

    main:
    BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX(ch_input)

    emit:
    tables   = BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX.out.tables
    plots    = BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX.out.plots
    objects  = BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX.out.objects
    versions = BIOC_SUBSEQ_EXTRACT_SUBSAMPLED_MATRIX.out.versions
}
