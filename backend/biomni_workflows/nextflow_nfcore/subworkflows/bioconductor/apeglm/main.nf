#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: apeglm — beta_binomial_ratio_shrinkage
// Estimate and shrink log-odds ratios for count ratio data (such as allele-specific expression) using a beta-binomial model.
// Input: ase.cts, cts
// Container: quay.io/biocontainers/bioconductor-apeglm:1.32.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: apeglm, emdbook
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-count genes
//  * 2. [Core Analysis] Run DESeq2 to estimate size factors, dispersions, and initial MLE coefficients
//  * 3. [Core Analysis] Extract the design matrix, dispersions, and convert MLEs and offsets to the natural log scale
//  * 4. [Core Analysis] Run apeglm using a fast negative binomial method (e.g., "nbinomR", "nbinomCR", or "nbinomC")
//  * 5. [Core Analysis] Convert the shrunk coefficients back to the log2 scale and compute s-values from the threshold probabilities

nextflow.enable.dsl = 2

process BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE {
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
    .bm_deps <- c("apeglm", "emdbook")
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
    library(apeglm)
    library(emdbook)
    
    # Helper function to read input files robustly
    read_matrix <- function(path) {
      if (!file.exists(path)) {
        stop(paste("Required input file missing:", path))
      }
      # Try reading as RDS
      res <- tryCatch(readRDS(path), error = function(e) NULL)
      if (!is.null(res)) {
        return(as.matrix(res))
      }
      # Try reading as whitespace-delimited table
      res <- tryCatch({
        df <- read.table(path, header = TRUE, row.names = 1, sep = "", check.names = FALSE)
        as.matrix(df)
      }, error = function(e) NULL)
      if (!is.null(res)) {
        return(res)
      }
      # Try reading as CSV
      res <- tryCatch({
        df <- read.csv(path, header = TRUE, row.names = 1, check.names = FALSE)
        as.matrix(df)
      }, error = function(e) NULL)
      if (!is.null(res)) {
        return(res)
      }
      stop(paste("Failed to parse file:", path))
    }
    
    # 1. Read the declared user input files
    message("Reading input files...")
    ase.cts <- read_matrix("ase.cts")
    cts <- read_matrix("cts")
    
    # Validate dimensions
    if (!all(dim(ase.cts) == dim(cts))) {
      stop("Dimensions of 'ase.cts' and 'cts' must match.")
    }
    
    num_samples <- ncol(cts)
    if (num_samples < 2) {
      stop("At least 2 samples (columns) are required to define a design matrix.")
    }
    
    # Create design matrix based on sample groups
    f <- factor(rep(1:2, each = ceiling(num_samples / 2), length.out = num_samples))
    x <- model.matrix(~f)
    coef <- ncol(x)
    
    # 2. Initialize the dispersion estimate and iteratively estimate MLE coefficients
    message("Initializing dispersion and running iterative MLE estimation...")
    theta.hat <- 100 # rough initial estimate of dispersion
    niter <- 3
    
    for (i in 1:niter) {
      message(paste("Iteration", i, "of", niter))
      param <- cbind(theta.hat, cts)
      fit.mle <- apeglm(Y=ase.cts, x=x, log.lik=NULL, param=param,
                        no.shrink=TRUE, log.link=FALSE, method="betabinCR")
      theta.hat <- bbEstDisp(success=ase.cts, size=cts,
                             x=x, beta=fit.mle\$map,
                             minDisp=.01, maxDisp=5000)
    }
    
    # Prepare MLE and standard error matrix for shrinkage
    mle <- cbind(fit.mle\$map[, coef], fit.mle\$sd[, coef])
    param <- cbind(theta.hat, cts)
    
    # 3. Run apeglm with shrinkage using the estimated dispersion, MLEs, and a threshold
    message("Running apeglm with shrinkage...")
    fit2 <- apeglm(Y=ase.cts, x=x, log.lik=NULL, param=param,
                   coef=coef, mle=mle, threshold=0.5,
                   log.link=FALSE, method="betabinCR")
    
    # 4. Compute s-values from the threshold probabilities
    message("Computing s-values...")
    s.val <- svalue(fit2\$thresh)
    
    # Save results to files
    message("Writing output files...")
    
    # Save the complete fit object
    saveRDS(fit2, "apeglm_beta_binomial_fit.rds")
    
    # Save a summary table of results
    results_df <- data.frame(
      mle_est = mle[, 1],
      mle_se = mle[, 2],
      map_est = fit2\$map[, coef],
      posterior_sd = fit2\$sd[, coef],
      s_value = s.val,
      row.names = rownames(cts)
    )
    write.csv(results_df, "apeglm_beta_binomial_results.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    pdf("apeglm_beta_binomial_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot MLE vs Shrunk MAP estimates
    plot(mle[, 1], fit2\$map[, coef],
         xlab = "MLE log-odds ratio",
         ylab = "Shrunk MAP log-odds ratio",
         main = "Effect Size Shrinkage",
         col = ifelse(s.val < 0.01, "red", "black"),
         pch = 20)
    abline(0, 1, col = "blue", lty = 2)
    legend("topleft", legend = c("s-value < 0.01", "s-value >= 0.01"),
           col = c("red", "black"), pch = 20)
    
    # Plot distribution of s-values
    hist(s.val, breaks = 50, col = "grey",
         main = "Distribution of s-values",
         xlab = "s-value")
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE":',
        paste0('    apeglm: ', as.character(packageVersion('apeglm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_beta_binomial_ratio_shrinkage.csv versions.yml
    """
}

workflow BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ase.cts, cts ] ]

    main:
    BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE(ch_input)

    emit:
    tables   = BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE.out.tables
    plots    = BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE.out.plots
    objects  = BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE.out.objects
    versions = BIOC_APEGLM_BETA_BINOMIAL_RATIO_SHRINKAGE.out.versions
}
