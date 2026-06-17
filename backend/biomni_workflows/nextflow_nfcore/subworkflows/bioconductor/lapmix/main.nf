#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lapmix — laplace_mixture_differential_expression
// Identify differentially expressed genes from microarray contrast estimates and standard errors using a Laplace mixture model.
// Input: estimates.csv, standard_errors.csv
// Container: quay.io/biocontainers/bioconductor-lapmix:1.72.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: lapmix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the empirical Bayes Laplace mixture model using lapmix.fit
//  * 2. [Core Analysis] Calculate the posterior odds of differential expression using lap.odds

nextflow.enable.dsl = 2

process BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("lapmix")
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
        if (!requireNamespace("lapmix", quietly = TRUE)) {
          stop("The 'lapmix' package is required but not installed.")
        }
        library(lapmix)
        
        # ----------------------------------------------------------------------
        # 1. Read User Input Files
        # ----------------------------------------------------------------------
        estimates_file <- "estimates.csv"
        se_file <- "standard_errors.csv"
        
        if (!file.exists(estimates_file)) {
          stop(paste("Required input file missing:", estimates_file))
        }
        if (!file.exists(se_file)) {
          stop(paste("Required input file missing:", se_file))
        }
        
        # Read CSV files
        estimates_df <- read.csv(estimates_file, header = TRUE, stringsAsFactors = FALSE)
        se_df <- read.csv(se_file, header = TRUE, stringsAsFactors = FALSE)
        
        # Determine if the first column contains identifiers (non-numeric)
        if (!is.numeric(estimates_df[[1]])) {
          rownames(estimates_df) <- estimates_df[[1]]
          estimates_df <- estimates_df[-1]
        }
        if (!is.numeric(se_df[[1]])) {
          rownames(se_df) <- se_df[[1]]
          se_df <- se_df[-1]
        }
        
        # Convert to matrix
        Y <- as.matrix(estimates_df)
        SE <- as.matrix(se_df)
        
        # Ensure dimensions match
        if (!all(dim(Y) == dim(SE))) {
          stop("Dimensions of estimates and standard errors do not match.")
        }
        
        # If single column, convert to vector as lapmix supports both vectors and matrices
        if (ncol(Y) == 1) {
          gene_names <- rownames(Y)
          Y <- as.vector(Y)
          SE <- as.vector(SE)
          if (!is.null(gene_names)) {
            names(Y) <- gene_names
            names(SE) <- gene_names
          }
        }
        
        # ----------------------------------------------------------------------
        # 2. Run Laplace Mixture Model (Documented Code)
        # ----------------------------------------------------------------------
        # Calculate variances from standard errors
        V <- SE^2
        
        # Fit the empirical Bayes Laplace mixture model
        fit <- lapmix.fit(Y, V)
        
        # Calculate the posterior odds of differential expression
        odds <- lap.odds(Y, V, fit)
        
        # Calculate posterior probabilities from odds
        post_prob <- odds / (1 + odds)
        
        # ----------------------------------------------------------------------
        # 3. Save Outputs
        # ----------------------------------------------------------------------
        # Save the raw R objects
        saveRDS(fit, "lapmix_fit.rds")
        saveRDS(odds, "lapmix_odds.rds")
        
        # Export results to CSV
        if (is.matrix(Y)) {
          # For matrix inputs, write separate tables for odds and posterior probabilities
          write.csv(as.data.frame(odds), "lapmix_posterior_odds.csv", row.names = TRUE)
          write.csv(as.data.frame(post_prob), "lapmix_posterior_probabilities.csv", row.names = TRUE)
        } else {
          # For vector inputs, combine into a single data frame
          results <- data.frame(
            Gene = if (!is.null(names(Y))) names(Y) else 1:length(Y),
            Estimate = Y,
            StandardError = SE,
            PosteriorOdds = odds,
            PosteriorProbability = post_prob,
            stringsAsFactors = FALSE
          )
          write.csv(results, "lapmix_results.csv", row.names = FALSE)
        }
        
        # Generate diagnostic and results plots
        pdf("lapmix_plots.pdf", width = 8, height = 6)
        if (is.matrix(Y)) {
          # Plot for the first column/contrast
          plot(Y[, 1], post_prob[, 1],
               main = "Posterior Probability vs Estimate (First Contrast)",
               xlab = "Contrast Estimate (LFC)",
               ylab = "Posterior Probability of DE",
               pch = 20, col = "blue")
          abline(h = 0.5, col = "red", lty = 2)
        } else {
          plot(Y, post_prob,
               main = "Posterior Probability vs Estimate",
               xlab = "Contrast Estimate (LFC)",
               ylab = "Posterior Probability of DE",
               pch = 20, col = "blue")
          abline(h = 0.5, col = "red", lty = 2)
        }
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to 'lapmix_fit.rds', 'lapmix_odds.rds', CSV results, and 'lapmix_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION":',
        paste0('    lapmix: ', as.character(packageVersion('lapmix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_laplace_mixture_differential_expression.csv versions.yml
    """
}

workflow BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ estimates.csv, standard_errors.csv ] ]

    main:
    BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_LAPMIX_LAPLACE_MIXTURE_DIFFERENTIAL_EXPRESSION.out.versions
}
