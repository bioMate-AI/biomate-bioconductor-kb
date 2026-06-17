#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMET — single_population_hvf_analysis
// Fit the scMET model on a single cell population to estimate methylation parameters and identify highly variable features (HVFs).
// Input: single_cell_methylation.csv, covariates.csv
// Container: quay.io/biocontainers/bioconductor-scmet:1.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, cowplot, data.table, ggplot2, scMET
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert SingleCellExperiment to scMET format (optional)
//  * 2. [Core Analysis] Run Bayesian inference using scmet to estimate mean and overdispersion parameters
//  * 3. [Core Analysis] Identify highly variable features (HVFs) using scmet_hvf
//  * 4. [Visualization & Output] Plot diagnostic and results figures using scmet_plot_mean_var, scmet_plot_efdr_efnr_grid, and scmet_plot_vf_tail_prob

nextflow.enable.dsl = 2

process BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS {
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
    .bm_deps <- c("scMET", "data.table", "ggplot2", "cowplot")
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
    suppressPackageStartupMessages({
      library(scMET)
      library(data.table)
      library(ggplot2)
      library(cowplot)
    })
    
    # Set seed for reproducibility
    set.seed(12)
    
    # 1. Read User Input Files
    if (!file.exists("single_cell_methylation.csv")) {
      stop("Error: 'single_cell_methylation.csv' not found in the working directory.")
    }
    
    # Read single-cell methylation data
    Y_scmet <- data.table::fread("single_cell_methylation.csv")
    
    # Ensure correct column types and names
    Y_scmet[, total_reads := as.integer(total_reads)]
    Y_scmet[, met_reads := as.numeric(met_reads)]
    
    # Identify unique features
    unique_features <- unique(Y_scmet\$Feature)
    
    # Read covariates if available, otherwise construct intercept-only matrix
    if (file.exists("covariates.csv")) {
      cov_df <- read.csv("covariates.csv", row.names = 1, check.names = FALSE)
      
      # Align covariates with the features present in the methylation data
      common_features <- intersect(unique_features, rownames(cov_df))
      if (length(common_features) > 0) {
        # Reorder and subset to match unique_features
        cov_df <- cov_df[unique_features, , drop = FALSE]
        # Handle any missing values by replacing with column mean
        for (col in seq_len(ncol(cov_df))) {
          if (any(is.na(cov_df[, col]))) {
            cov_df[is.na(cov_df[, col]), col] <- mean(cov_df[, col], na.rm = TRUE)
          }
        }
      } else {
        cov_df <- data.frame(row.names = unique_features)
      }
      
      X <- as.matrix(cov_df)
      # Ensure the first column is the intercept (vector of 1s)
      if (ncol(X) == 0 || !all(X[, 1] == 1)) {
        X <- cbind(intercept = 1, X)
      }
    } else {
      # Fallback to intercept-only matrix
      X <- matrix(1, nrow = length(unique_features), ncol = 1,
                  dimnames = list(unique_features, "intercept"))
    }
    
    # 2. Execute Documented Workflow Steps
    
    # Convert to SingleCellExperiment and back to scMET format
    Y_sce <- scmet_to_sce(Y = Y_scmet, X = X)
    scmet_obj <- sce_to_scmet(sce = Y_sce)
    
    # Prepare the scmet_dt list to match the exact documented function call
    scmet_dt <- list(Y = scmet_obj\$Y, X = scmet_obj\$X)
    if (is.null(scmet_dt\$X)) {
      scmet_dt\$X <- X
    }
    
    # Run Bayesian inference using scmet
    fit_obj <- scmet(Y = scmet_dt\$Y, X = scmet_dt\$X, L = 4, iter = 1000, seed = 12)
    
    # Plot mean-overdispersion relationships
    pdf("mean_var_plots.pdf", width = 10, height = 5)
    gg1 <- scmet_plot_mean_var(obj = fit_obj, y = "gamma", task = NULL, show_fit = TRUE)
    gg2 <- scmet_plot_mean_var(obj = fit_obj, y = "epsilon", task = NULL, show_fit = TRUE)
    print(cowplot::plot_grid(gg1, gg2, ncol = 2))
    dev.off()
    
    # Identify highly variable features (HVFs)
    fit_obj <- scmet_hvf(scmet_obj = fit_obj, delta_e = 0.75, evidence_thresh = 0.8, efdr = 0.1)
    
    # Plot diagnostic and results figures
    pdf("hvf_plots.pdf", width = 10, height = 8)
    print(scmet_plot_efdr_efnr_grid(obj = fit_obj, task = "hvf"))
    gg1 <- scmet_plot_vf_tail_prob(obj = fit_obj, x = "mu", task = "hvf")
    gg2 <- scmet_plot_mean_var(obj = fit_obj, y = "gamma", task = "hvf")
    print(cowplot::plot_grid(gg1, gg2, ncol = 2))
    dev.off()
    
    # 3. Save Outputs
    # Save the final fit object
    saveRDS(fit_obj, "scmet_fit_obj.rds")
    
    # Save the HVF summary table
    if (!is.null(fit_obj\$hvf\$summary)) {
      write.csv(fit_obj\$hvf\$summary, "hvf_summary.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully. Outputs saved to 'scmet_fit_obj.rds', 'hvf_summary.csv', 'mean_var_plots.pdf', and 'hvf_plots.pdf'.")

    writeLines(c(
        '"BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS":',
        paste0('    scMET: ', as.character(packageVersion('scMET')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_population_hvf_analysis.csv versions.yml
    """
}

workflow BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_cell_methylation.csv, covariates.csv ] ]

    main:
    BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS.out.tables
    plots    = BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS.out.plots
    objects  = BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS.out.objects
    versions = BIOC_SCMET_SINGLE_POPULATION_HVF_ANALYSIS.out.versions
}
