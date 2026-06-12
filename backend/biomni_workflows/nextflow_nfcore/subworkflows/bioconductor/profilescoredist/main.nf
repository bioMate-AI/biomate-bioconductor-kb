#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: profileScoreDist — tfbs_score_cutoff_estimation
// Regularize a position count matrix, compute score distributions across GC contents, and estimate statistically rigorous score cutoffs for TFBS detection.
// Input: INR
// Container: quay.io/biocontainers/bioconductor-profilescoredist:1.38.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: profileScoreDist
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Regularize the position count matrix using regularizeMatrix()
//  * 2. [Input & Preparation] Define GC fractions and granularity parameters
//  * 3. [Core Analysis] Compute probability distributions for log-odds scores using computeScoreDist()
//  * 4. [Visualization & Output] Plot the distribution using plotDist()
//  * 5. [Core Analysis] Estimate score cutoffs for specified FDR/FNR thresholds using scoreDistCutoffs()

nextflow.enable.dsl = 2

process BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("profileScoreDist")
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
    library(profileScoreDist)
    
    # 1. Read the user input file 'INR' from the working directory
    # The file is expected to be a space- or tab-delimited position count matrix
    # with row names (A, C, G, T) and numeric columns.
    if (!file.exists("INR")) {
      stop("Error: Required input file 'INR' not found in the working directory.")
    }
    
    INR <- as.matrix(read.table("INR", header = TRUE, row.names = 1, check.names = FALSE))
    storage.mode(INR) <- "numeric"
    
    # 2. Regularize the position count matrix
    inr.reg <- regularizeMatrix(INR)
    
    # Save the regularized matrix to a CSV file
    write.csv(inr.reg, file = "inr_regularized.csv", row.names = TRUE)
    
    # 3. Define GC fractions and granularity parameters
    granularity <- 0.05
    gcgran <- 0.01
    gcmin <- 0.01
    gcmax <- 0.99
    gcs <- seq(gcgran*round(gcmin/gcgran), gcgran*round(gcmax/gcgran), gcgran)
    
    # 4. Compute probability distributions for log-odds scores
    distlist <- lapply(gcs, function(x) computeScoreDist(inr.reg, x, granularity))
    
    # Save the computed distributions list as an RDS object
    saveRDS(distlist, file = "score_distributions.rds")
    
    # 5. Plot the distribution for GC content 50% (index 50 in gcs)
    pdf("distribution_plot_gc50.pdf", width = 7, height = 5)
    plotDist(distlist[[50]])
    dev.off()
    
    # 6. Estimate score cutoffs for specified FDR/FNR thresholds
    ab5 <- scoreDistCutoffs(distlist[[50]], 500, 1, c=1, 0.05)
    
    # Extract and save the cutoffs
    cutoff_results <- data.frame(
      Metric = c("5% FDR Cutoff (cutoffa)", "5% FNR Cutoff (cutoffb)", "Balanced FDR=FNR Cutoff (cutoffopt)"),
      Value = c(ab5\$cutoffa, ab5\$cutoffb, ab5\$cutoffopt)
    )
    write.csv(cutoff_results, file = "estimated_cutoffs.csv", row.names = FALSE)
    
    # Print the results to standard output
    cat("Score Cutoff Estimation Complete.\n")
    cat("5% FDR Cutoff (cutoffa):", ab5\$cutoffa, "\n")
    cat("5% FNR Cutoff (cutoffb):", ab5\$cutoffb, "\n")
    cat("Balanced Cutoff (cutoffopt):", ab5\$cutoffopt, "\n")

    writeLines(c(
        '"BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION":',
        paste0('    profileScoreDist: ', as.character(packageVersion('profileScoreDist')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfbs_score_cutoff_estimation.csv versions.yml
    """
}

workflow BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ INR ] ]

    main:
    BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION.out.tables
    plots    = BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION.out.plots
    objects  = BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION.out.objects
    versions = BIOC_PROFILESCOREDIST_TFBS_SCORE_CUTOFF_ESTIMATION.out.versions
}
