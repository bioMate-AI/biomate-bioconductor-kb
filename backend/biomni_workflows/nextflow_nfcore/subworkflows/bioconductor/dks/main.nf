#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dks — double_ks_diagnostic
// Perform double Kolmogorov-Smirnov and Bayesian diagnostic tests on simulated null p-values across multiple studies.
// Input: P
// Container: quay.io/biocontainers/bioconductor-dks:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cubature, dks
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the simulated dataset from the working directory
//  * 2. [Visualization & Output] Run the dks function to compute the double KS p-value,
//  * 3. [Visualization & Output] Calculate the posterior distribution for the first study
//  * 4. [Visualization & Output] Calculate a 80% credible set

nextflow.enable.dsl = 2

process BIOC_DKS_DOUBLE_KS_DIAGNOSTIC {
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
    .bm_deps <- c("dks", "cubature")
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
    library(dks)
    library(cubature)
    
    # --- Load the simulated dataset from the working directory ---
    # We check for common formats: P.csv, P.tsv, P.rds, or a file named P
    if (file.exists("P.csv")) {
      P <- as.matrix(read.csv("P.csv", header = TRUE, check.names = FALSE))
    } else if (file.exists("P.tsv")) {
      P <- as.matrix(read.delim("P.tsv", header = TRUE, check.names = FALSE))
    } else if (file.exists("P.rds")) {
      P <- readRDS("P.rds")
    } else if (file.exists("P")) {
      P <- as.matrix(read.table("P", header = TRUE, check.names = FALSE))
    } else {
      stop("Error: Input file 'P' (or P.csv/P.tsv/P.rds) not found in the working directory.")
    }
    
    # Ensure P is a numeric matrix
    if (!is.matrix(P)) {
      P <- as.matrix(P)
    }
    if (!is.numeric(P)) {
      # If the first column is non-numeric (e.g., row names), remove it
      if (any(is.na(suppressWarnings(as.numeric(P[, 1]))))) {
        P <- P[, -1, drop = FALSE]
      }
      storage.mode(P) <- "numeric"
    }
    
    # Print dimensions of the input matrix
    print(dim(P))
    
    # --- Run the dks function to compute the double KS p-value, ---
    # and generate diagnostic plots.
    pdf("dks_diagnostic_plots.pdf", width = 12, height = 4)
    dks1 <- dks(P, plot = TRUE)
    dev.off()
    
    # Save the dks results
    saveRDS(dks1, "dks_results.rds")
    
    # --- Calculate the posterior distribution for the first study ---
    delta <- 0.1
    dist1 <- pprob.dist(P[, 1])
    
    # Save the posterior distribution matrix
    saveRDS(dist1, "posterior_dist.rds")
    
    # Plot the posterior distribution
    pdf("posterior_distribution.pdf", width = 6, height = 6)
    alpha <- seq(0.1, 10, by = delta)
    beta <- seq(0.1, 10, by = delta)
    pprobImage = image(log10(alpha), log10(beta), dist1, xaxt = "n", yaxt = "n", xlab = "Alpha", ylab = "Beta")
    axis(1, at = c(-2, -1, 0, 1, 2), labels = c("10^-2", "10^-1", "10^0", "10^1", "10^2"))
    axis(2, at = c(-2, -1, 0, 1, 2), labels = c("10^-2", "10^-1", "10^0", "10^1", "10^2"))
    points(0, 0, col = "blue", cex = 1, pch = 19)
    dev.off()
    
    # --- Calculate a 80% credible set ---
    cred1 <- cred.set(dist1, delta = 0.1, level = 0.80)
    
    # Save the credible set results
    saveRDS(cred1, "credible_set_results.rds")
    
    # Plot the posterior and the credible set
    pdf("credible_set.pdf", width = 6, height = 6)
    alpha <- seq(0.1, 10, by = delta)
    beta <- seq(0.1, 10, by = delta)
    credImage = image(log10(alpha), log10(beta), cred1\$cred, xaxt = "n", yaxt = "n", xlab = "Alpha", ylab = "Beta")
    axis(1, at = c(-2, -1, 0, 1, 2), labels = c("10^-2", "10^-1", "10^0", "10^1", "10^2"))
    axis(2, at = c(-2, -1, 0, 1, 2), labels = c("10^-2", "10^-1", "10^0", "10^1", "10^2"))
    points(0, 0, col = "blue", cex = 1, pch = 19)
    dev.off()

    writeLines(c(
        '"BIOC_DKS_DOUBLE_KS_DIAGNOSTIC":',
        paste0('    dks: ', as.character(packageVersion('dks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_double_ks_diagnostic.csv versions.yml
    """
}

workflow BIOC_DKS_DOUBLE_KS_DIAGNOSTIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ P ] ]

    main:
    BIOC_DKS_DOUBLE_KS_DIAGNOSTIC(ch_input)

    emit:
    tables   = BIOC_DKS_DOUBLE_KS_DIAGNOSTIC.out.tables
    plots    = BIOC_DKS_DOUBLE_KS_DIAGNOSTIC.out.plots
    objects  = BIOC_DKS_DOUBLE_KS_DIAGNOSTIC.out.objects
    versions = BIOC_DKS_DOUBLE_KS_DIAGNOSTIC.out.versions
}
