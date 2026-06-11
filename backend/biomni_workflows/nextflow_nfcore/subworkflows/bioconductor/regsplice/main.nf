#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regsplice — rna_seq_wrapper
// Run the complete regsplice analysis pipeline on RNA-seq count data in a single step using the wrapper function.
// Input: counts, gene_IDs, n_exons, condition
// Container: quay.io/biocontainers/bioconductor-regsplice:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: regsplice
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create RegspliceData object
//  * 2. [Core Analysis] Run the wrapper analysis pipeline
//  * 3. [Visualization & Output] Generate a summary table of results

nextflow.enable.dsl = 2

process BIOC_REGSPLICE_RNA_SEQ_WRAPPER {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(regsplice)
    
    # Read user inputs from the working directory
    # 1. counts (matrix or data frame of RNA-seq read counts)
    if (file.exists("counts.rds")) {
      counts <- readRDS("counts.rds")
    } else if (file.exists("counts.csv")) {
      counts <- read.csv("counts.csv", header = TRUE, check.names = FALSE)
      if (!is.numeric(counts[[1]])) {
        rownames(counts) <- counts[[1]]
        counts <- counts[, -1, drop = FALSE]
      }
    } else if (file.exists("counts.txt")) {
      counts <- read.table("counts.txt", header = TRUE, sep = "\t", check.names = FALSE)
      if (!is.numeric(counts[[1]])) {
        rownames(counts) <- counts[[1]]
        counts <- counts[, -1, drop = FALSE]
      }
    } else {
      stop("Error: counts file (counts.rds, counts.csv, or counts.txt) not found in the working directory.")
    }
    
    # Convert counts to matrix if it is a data frame
    if (is.data.frame(counts)) {
      counts <- as.matrix(counts)
    }
    
    # 2. gene_IDs (vector of gene IDs)
    if (file.exists("gene_IDs.rds")) {
      gene_IDs <- readRDS("gene_IDs.rds")
    } else if (file.exists("gene_IDs.txt")) {
      gene_IDs <- scan("gene_IDs.txt", what = character(), quiet = TRUE)
    } else {
      stop("Error: gene_IDs file (gene_IDs.rds or gene_IDs.txt) not found in the working directory.")
    }
    
    # 3. n_exons (vector of number of exon bins per gene)
    if (file.exists("n_exons.rds")) {
      n_exons <- readRDS("n_exons.rds")
    } else if (file.exists("n_exons.txt")) {
      n_exons <- scan("n_exons.txt", what = integer(), quiet = TRUE)
    } else {
      stop("Error: n_exons file (n_exons.rds or n_exons.txt) not found in the working directory.")
    }
    
    # 4. condition (vector of experimental conditions)
    if (file.exists("condition.rds")) {
      condition <- readRDS("condition.rds")
    } else if (file.exists("condition.txt")) {
      condition <- scan("condition.txt", what = character(), quiet = TRUE)
    } else {
      stop("Error: condition file (condition.rds or condition.txt) not found in the working directory.")
    }
    
    # Step 1: Create RegspliceData object
    rs_data <- RegspliceData(counts, gene_IDs, n_exons, condition)
    
    # Step 2: Run the wrapper analysis pipeline
    rs_results <- suppressWarnings(regsplice(rs_data, seed = 123))
    
    # Step 3: Generate a summary table of results
    results_table <- summaryTable(rs_results, n = Inf, threshold = 1)
    
    # Write outputs to the working directory
    write.csv(results_table, "regsplice_summary_table.csv", row.names = FALSE)
    saveRDS(rs_results, "regsplice_results.rds")

    writeLines(c(
        '"BIOC_REGSPLICE_RNA_SEQ_WRAPPER":',
        paste0('    regsplice: ', as.character(packageVersion('regsplice')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_wrapper.csv versions.yml
    """
}

workflow BIOC_REGSPLICE_RNA_SEQ_WRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, gene_IDs, n_exons, condition ] ]

    main:
    BIOC_REGSPLICE_RNA_SEQ_WRAPPER(ch_input)

    emit:
    tables   = BIOC_REGSPLICE_RNA_SEQ_WRAPPER.out.tables
    plots    = BIOC_REGSPLICE_RNA_SEQ_WRAPPER.out.plots
    objects  = BIOC_REGSPLICE_RNA_SEQ_WRAPPER.out.objects
    versions = BIOC_REGSPLICE_RNA_SEQ_WRAPPER.out.versions
}
