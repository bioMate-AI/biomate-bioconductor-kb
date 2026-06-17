#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bacon — single_set_correction
// Correct bias and inflation for a single vector of association test statistics.
// Input: y
// Container: quay.io/biocontainers/bioconductor-bacon:1.38.0--r45h01b2380_0
// R packages: bacon, BiocParallel
// Bioconductor: 3.20 | R: 4.4
// Requires: bacon
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the Gibbs sampler to estimate the empirical null distribution using bacon
//  * 2. [Core Analysis] Extract estimated parameters, inflation, and bias using estimates, inflation, and bias
//  * 3. [Core Analysis] Diagnose the Gibbs sampler fit using traces, posteriors, and fit
//  * 4. [Visualization & Output] Plot diagnostic histogram and QQ-plots using plot

nextflow.enable.dsl = 2

process BIOC_BACON_SINGLE_SET_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("bacon", "BiocParallel")
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
    library(bacon)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a file named 'y' (or 'y.csv' / 'y.txt') in the working directory
    # containing a single vector of z-scores.
    if (file.exists("y")) {
      y <- scan("y", quiet = TRUE)
    } else if (file.exists("y.csv")) {
      y <- read.csv("y.csv", header = FALSE)[[1]]
    } else if (file.exists("y.txt")) {
      y <- scan("y.txt", quiet = TRUE)
    } else {
      stop("Error: Input file 'y' containing z-scores not found in the working directory.")
    }
    
    # Ensure y is a numeric vector
    y <- as.numeric(y)
    y <- y[!is.na(y)]
    
    if (length(y) == 0) {
      stop("Error: Input vector 'y' is empty or contains no valid numeric values.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run the Gibbs sampler to estimate the empirical null distribution
    # -----------------------------------------------------------------------------
    bc <- bacon(y)
    print(bc)
    
    # Save the Bacon object
    saveRDS(bc, "bacon_object.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 2: Extract estimated parameters, inflation, and bias
    # -----------------------------------------------------------------------------
    est <- estimates(bc)
    inf <- inflation(bc)
    bi <- bias(bc)
    
    # Save estimates to CSV
    write.csv(as.data.frame(est), "estimates.csv", row.names = FALSE)
    
    # Save inflation and bias to CSV
    inf_bias_df <- data.frame(inflation = inf, bias = bi)
    write.csv(inf_bias_df, "inflation_bias.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Diagnose the Gibbs sampler fit
    # -----------------------------------------------------------------------------
    pdf("traces.pdf")
    traces(bc, burnin=FALSE)
    dev.off()
    
    pdf("posteriors.pdf")
    posteriors(bc)
    dev.off()
    
    pdf("fit.pdf")
    fit(bc, n=100)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 4: Plot diagnostic histogram and QQ-plots
    # -----------------------------------------------------------------------------
    pdf("plot_hist.pdf")
    plot(bc, type="hist")
    dev.off()
    
    pdf("plot_qq.pdf")
    plot(bc, type="qq")
    dev.off()

    writeLines(c(
        '"BIOC_BACON_SINGLE_SET_CORRECTION":',
        paste0('    bacon: ', as.character(packageVersion('bacon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_set_correction.csv versions.yml
    """
}

workflow BIOC_BACON_SINGLE_SET_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y ] ]

    main:
    BIOC_BACON_SINGLE_SET_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BACON_SINGLE_SET_CORRECTION.out.tables
    plots    = BIOC_BACON_SINGLE_SET_CORRECTION.out.plots
    objects  = BIOC_BACON_SINGLE_SET_CORRECTION.out.objects
    versions = BIOC_BACON_SINGLE_SET_CORRECTION.out.versions
}
