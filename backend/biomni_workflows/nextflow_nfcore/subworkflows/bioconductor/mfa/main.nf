#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mfa — mfa_bifurcation_analysis
// Perform Bayesian trajectory inference to estimate pseudotime and branch assignments for single-cell expression data.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mfa:1.28.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mfa
// Visualizations: trajectory plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate hyperparameters using empirical Bayes with empirical_bayes
//  * 2. [Core Analysis] Fit the Bayesian mixture of factor analysers model using mfa
//  * 3. [Visualization & Output] Extract posterior summary statistics using summary
//  * 4. [Core Analysis] Convert the fit to a tidy format or diagnostic object using to_ggmcmc
//  * 5. [Visualization & Output] Plot the inferred bifurcation trajectory using plot_mfa

nextflow.enable.dsl = 2

process BIOC_MFA_MFA_BIFURCATION_ANALYSIS {
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
    .bm_deps <- c("mfa", "ggplot2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
        library(mfa)
        library(ggplot2)
        
        # 1. Read user input
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        
        y_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        y <- as.matrix(y_df)
        storage.mode(y) <- "numeric"
        
        # Filter out zero-variance genes to ensure numerical stability
        gene_vars <- apply(y, 2, var)
        y <- y[, gene_vars > 0, drop = FALSE]
        
        if (ncol(y) < 2) {
          stop("Error: Fewer than 2 genes with non-zero variance. Cannot run mfa.")
        }
        
        # Stage 1: Estimate hyperparameters using empirical Bayes
        eb <- empirical_bayes(y)
        saveRDS(eb, "empirical_bayes_estimates.rds")
        
        # Stage 2: Fit the Bayesian mixture of factor analysers model
        m <- mfa(y, iter = 2000, thin = 1, alpha_prior = eb[1], beta_prior = eb[2])
        saveRDS(m, "mfa_fit.rds")
        
        # Stage 3: Extract posterior summary statistics
        ms <- summary(m)
        write.csv(ms, "mfa_summary.csv", row.names = TRUE)
        
        # Stage 4: Convert the fit to a tidy format or diagnostic object
        g <- to_ggmcmc(m)
        saveRDS(g, "mfa_ggmcmc.rds")
        
        # Stage 5: Plot the inferred bifurcation trajectory
        p <- plot_mfa(m)
        ggsave("mfa_trajectory.pdf", plot = p, width = 8, height = 6)

    writeLines(c(
        '"BIOC_MFA_MFA_BIFURCATION_ANALYSIS":',
        paste0('    mfa: ', as.character(packageVersion('mfa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mfa_bifurcation_analysis.csv versions.yml
    """
}

workflow BIOC_MFA_MFA_BIFURCATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_MFA_MFA_BIFURCATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MFA_MFA_BIFURCATION_ANALYSIS.out.tables
    plots    = BIOC_MFA_MFA_BIFURCATION_ANALYSIS.out.plots
    objects  = BIOC_MFA_MFA_BIFURCATION_ANALYSIS.out.objects
    versions = BIOC_MFA_MFA_BIFURCATION_ANALYSIS.out.versions
}
