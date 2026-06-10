#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDDboost — differential_distribution_analysis
// Identify differentially distributed genes between two conditions in single-cell RNA-seq data.
// Input: normalized_counts_matrix, condition_vector
// Container: quay.io/biocontainers/bioconductor-scddboost:1.12.0--r45ha27e39d_0
// R packages: BiocParallel, ggplot2, scDDboost
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, scDDboost
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the cell distance matrix using calD
//  * 2. [Core Analysis] (Optional) Determine the number of subtypes using detK
//  * 3. [Core Analysis] Calculate the posterior probabilities of genes being differentially distributed using pdd
//  * 4. [Core Analysis] Extract the estimated DD genes controlling for false discovery rate using getDD

nextflow.enable.dsl = 2

process BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("BiocParallel", "ggplot2", "scDDboost")
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
    library(scDDboost)
    library(BiocParallel)
    
    # 1. Read User Inputs from the working directory
    if (file.exists("normalized_counts_matrix.rds")) {
      data_counts <- readRDS("normalized_counts_matrix.rds")
    } else if (file.exists("normalized_counts_matrix.csv")) {
      data_counts <- as.matrix(read.csv("normalized_counts_matrix.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("normalized_counts_matrix.tsv")) {
      data_counts <- as.matrix(read.delim("normalized_counts_matrix.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: normalized_counts_matrix file not found (expected .rds, .csv, or .tsv).")
    }
    
    if (file.exists("condition_vector.rds")) {
      conditions <- readRDS("condition_vector.rds")
    } else if (file.exists("condition_vector.csv")) {
      conditions_df <- read.csv("condition_vector.csv", header = FALSE)
      conditions <- as.character(conditions_df[[1]])
    } else if (file.exists("condition_vector.txt")) {
      conditions <- readLines("condition_vector.txt")
    } else {
      stop("Error: condition_vector file not found (expected .rds, .csv, or .txt).")
    }
    
    # Ensure data_counts is a matrix
    data_counts <- as.matrix(data_counts)
    
    # Preserve original rownames if they exist, otherwise set sequential integers
    if (is.null(rownames(data_counts))) {
      rownames(data_counts) <- seq_len(nrow(data_counts))
    }
    
    # 2. Execute Documented Workflow
    bp <- BiocParallel::MulticoreParam(2)
    D_c <- calD(data_counts, bp)
    ProbDD <- pdd(data = data_counts, cd = conditions, bp = bp, D = D_c)
    K <- detK(D_c)
    EDD <- getDD(ProbDD, 0.05)
    
    # 3. Save Outputs
    # Save the posterior probabilities
    prob_df <- data.frame(Gene = rownames(data_counts), Prob_DD = ProbDD)
    write.csv(prob_df, "posterior_probabilities.csv", row.names = FALSE)
    
    # Save the estimated DD genes
    if (is.numeric(EDD)) {
      edd_df <- data.frame(DD_Gene = rownames(data_counts)[EDD])
    } else {
      edd_df <- data.frame(DD_Gene = EDD)
    }
    write.csv(edd_df, "estimated_dd_genes.csv", row.names = FALSE)
    
    # Save K (number of subtypes)
    writeLines(as.character(K), "estimated_subtypes_K.txt")
    
    # Save RDS objects for downstream analysis
    saveRDS(ProbDD, "ProbDD.rds")
    saveRDS(EDD, "EDD.rds")
    saveRDS(D_c, "distance_matrix.rds")
    
    # Generate a diagnostic plot of posterior probabilities
    pdf("prob_distribution.pdf", width = 6, height = 4)
    hist(ProbDD, breaks = 50, col = "skyblue", main = "Distribution of Posterior Probabilities (ProbDD)",
         xlab = "Posterior Probability of DD", ylab = "Frequency")
    abline(v = 0.95, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = "0.95 Threshold", col = "red", lty = 2, lwd = 2)
    dev.off()
    
    cat("Workflow completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS":',
        paste0('    scDDboost: ', as.character(packageVersion('scDDboost')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normalized_counts_matrix, condition_vector ] ]

    main:
    BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SCDDBOOST_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.versions
}
