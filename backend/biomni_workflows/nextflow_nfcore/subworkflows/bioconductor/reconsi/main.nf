#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: reconsi — matrix_simultaneous_inference
// Perform simultaneous hypothesis testing on a data matrix while accounting for test correlation using a collapsed null distribution.
// Input: mat, x
// Container: quay.io/biocontainers/bioconductor-reconsi:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: reconsi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run simultaneous inference using reconsi
//  * 2. [Core Analysis] Extract estimated tail-area false discovery rates and proportion of true nulls
//  * 3. [Visualization & Output] Plot the estimated null distribution
//  * 4. [Visualization & Output] Plot the approximate covariance matrix of test statistics

nextflow.enable.dsl = 2

process BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("reconsi")
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
    library(reconsi)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read 'mat' (numeric matrix of features, samples in rows, features in columns)
    if (file.exists("mat.rds")) {
      mat <- readRDS("mat.rds")
    } else if (file.exists("mat.csv")) {
      mat <- as.matrix(read.csv("mat.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("mat.txt")) {
      mat <- as.matrix(read.table("mat.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Required input file 'mat' (mat.rds, mat.csv, or mat.txt) not found in the working directory.")
    }
    
    # Read 'x' (grouping factor vector)
    if (file.exists("x.rds")) {
      x <- readRDS("x.rds")
    } else if (file.exists("x.csv")) {
      x_df <- read.csv("x.csv", header = FALSE, stringsAsFactors = FALSE)
      # If it's a single row/column, extract it as a vector
      if (ncol(x_df) == 1) {
        x <- x_df[[1]]
      } else {
        x <- as.vector(t(x_df))
      }
    } else if (file.exists("x.txt")) {
      x <- readLines("x.txt")
    } else {
      stop("Error: Required input file 'x' (x.rds, x.csv, or x.txt) not found in the working directory.")
    }
    
    # Ensure x is treated as a factor or vector as appropriate
    if (is.list(x)) {
      x <- unlist(x)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run simultaneous inference using reconsi
    # -----------------------------------------------------------------------------
    fdrRes = reconsi(mat, x)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Extract estimated tail-area false discovery rates and proportion of true nulls
    # -----------------------------------------------------------------------------
    estFdr = fdrRes\$Fdr
    p0_val = fdrRes\$p0
    
    # Save the estimated FDR values to a CSV file
    fdr_df <- data.frame(
      Feature = colnames(mat),
      Fdr = estFdr,
      stringsAsFactors = FALSE
    )
    write.csv(fdr_df, "estimated_fdr.csv", row.names = FALSE)
    
    # Save the proportion of true nulls to a text file
    writeLines(as.character(p0_val), "p0_estimate.txt")
    
    # Save the full results object as an RDS file
    saveRDS(fdrRes, "fdrRes.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Plot the estimated null distribution
    # -----------------------------------------------------------------------------
    pdf("null_distribution_plot.pdf", width = 7, height = 5)
    tryCatch({
      print(plotNull(fdrRes))
    }, error = function(e) {
      warning("Failed to plot null distribution: ", e\$message)
    })
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 4: Plot the approximate covariance matrix of test statistics
    # -----------------------------------------------------------------------------
    pdf("approx_covar_plot.pdf", width = 7, height = 6)
    tryCatch({
      print(plotApproxCovar(fdrRes))
    }, error = function(e) {
      warning("Failed to plot approximate covariance: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE":',
        paste0('    reconsi: ', as.character(packageVersion('reconsi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_simultaneous_inference.csv versions.yml
    """
}

workflow BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mat, x ] ]

    main:
    BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE(ch_input)

    emit:
    tables   = BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE.out.tables
    plots    = BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE.out.plots
    objects  = BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE.out.objects
    versions = BIOC_RECONSI_MATRIX_SIMULTANEOUS_INFERENCE.out.versions
}
