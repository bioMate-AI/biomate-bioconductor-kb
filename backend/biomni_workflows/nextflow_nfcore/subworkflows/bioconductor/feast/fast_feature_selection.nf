#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FEAST — fast_feature_selection
// Directly obtain gene rankings using the FEAST or FEAST_fast wrapper functions for downstream analysis.
// Input: Y, k
// Container: quay.io/biocontainers/bioconductor-feast:1.18.0--r45h01b2380_0
// R packages: FEAST
// Bioconductor: 3.20 | R: 4.4
// Requires: FEAST
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess the count matrix using process_Y
//  * 2. [Core Analysis] Run the FEAST wrapper function to obtain ranked gene

nextflow.enable.dsl = 2

process BIOC_FEAST_FAST_FEATURE_SELECTION {
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
    .bm_deps <- c("FEAST")
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
    if (!requireNamespace("FEAST", quietly = TRUE)) {
      stop("The 'FEAST' package is required but not installed.")
    }
    library(FEAST)
    
    # --- Input Loading ---
    # Read Y (raw count expression matrix with genes as rows and cells as columns)
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y <- as.matrix(read.csv("Y.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Y.tsv")) {
      Y <- as.matrix(read.delim("Y.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Count matrix file (Y.rds, Y.csv, or Y.tsv) not found in the working directory.")
    }
    
    # Read k (integer, number of clusters)
    if (file.exists("k.rds")) {
      k <- readRDS("k.rds")
    } else if (file.exists("k.txt")) {
      k <- as.integer(readLines("k.txt", n = 1))
    } else {
      stop("Error: Number of clusters file (k.rds or k.txt) not found in the working directory.")
    }
    
    # Ensure k is a valid integer
    k <- as.integer(k)
    if (is.na(k) || k <= 0) {
      stop("Error: k must be a positive integer.")
    }
    
    # --- FEAST Workflow ---
    
    # --- Preprocess the count matrix using process_Y ---
    Y = process_Y(Y, thre = 2)
    
    # --- Run the FEAST wrapper function to obtain ranked gene ---
    ixs = FEAST(Y, k=k)
    
    # Alternative fast wrapper calls (reproduced from documented code comments)
    # ixs = FEAST_fast(Y, k=k)
    # ixs = FEAST_fast(Y, k=k, split=TRUE, batch_size = 1000)
    
    # --- Save Outputs ---
    # Map indices to gene names if available
    gene_names <- rownames(Y)[ixs]
    output_df <- data.frame(
      Rank = seq_along(ixs),
      GeneIndex = ixs,
      GeneName = if (is.null(gene_names)) NA else gene_names
    )
    
    write.csv(output_df, "feast_ranked_genes.csv", row.names = FALSE)
    saveRDS(ixs, "feast_ranked_indices.rds")
    
    cat("FEAST workflow completed successfully. Outputs saved to 'feast_ranked_genes.csv' and 'feast_ranked_indices.rds'.\n")

    writeLines(c(
        '"BIOC_FEAST_FAST_FEATURE_SELECTION":',
        paste0('    FEAST: ', as.character(packageVersion('FEAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_feature_selection.csv versions.yml
    """
}

workflow BIOC_FEAST_FAST_FEATURE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, k ] ]

    main:
    BIOC_FEAST_FAST_FEATURE_SELECTION(ch_input)

    emit:
    tables   = BIOC_FEAST_FAST_FEATURE_SELECTION.out.tables
    plots    = BIOC_FEAST_FAST_FEATURE_SELECTION.out.plots
    objects  = BIOC_FEAST_FAST_FEATURE_SELECTION.out.objects
    versions = BIOC_FEAST_FAST_FEATURE_SELECTION.out.versions
}
