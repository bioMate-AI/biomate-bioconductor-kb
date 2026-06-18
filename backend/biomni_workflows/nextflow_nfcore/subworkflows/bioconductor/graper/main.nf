#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: graper — linear_regression
// Fit a group-penalized linear regression model on high-dimensional continuous data, evaluate convergence, extract coefficients, and make predictions.
// Input: Xtrain, ytrain, annot, Xtest
// Container: quay.io/biocontainers/bioconductor-graper:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, graper
// Visualizations: posterior plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the linear regression model using graper
//  * 2. [Visualization & Output] Plot the ELBO to monitor convergence using plotELBO
//  * 3. [Visualization & Output] Plot posterior distributions of parameters using plotPosterior
//  * 4. [Core Analysis] Extract coefficients and intercept using coef
//  * 5. [Core Analysis] Extract posterior inclusion probabilities using getPIPs
//  * 6. [Visualization & Output] Plot group-wise penalties using plotGroupPenalties
//  * 7. [Core Analysis] Predict response on new data using predict

nextflow.enable.dsl = 2

process BIOC_GRAPER_LINEAR_REGRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("graper", "ggplot2")
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
            library(graper)
            library(ggplot2)
            
            # Helper function to read inputs robustly from the working directory
            read_input <- function(name) {
              if (file.exists(paste0(name, ".rds"))) {
                return(readRDS(paste0(name, ".rds")))
              } else if (file.exists(paste0(name, ".csv"))) {
                df <- read.csv(paste0(name, ".csv"), row.names = 1, check.names = FALSE)
                if (ncol(df) == 1) {
                  return(df[[1]])
                }
                return(as.matrix(df))
              } else if (file.exists(name)) {
                return(readRDS(name))
              } else {
                stop(paste("Required input file not found:", name))
              }
            }
            
            # 1. Read the declared USER INPUT files
            Xtrain <- read_input("Xtrain")
            ytrain <- read_input("ytrain")
            annot <- read_input("annot")
            Xtest <- read_input("Xtest")
            
            # Ensure correct data types for graper
            Xtrain <- as.matrix(Xtrain)
            Xtest <- as.matrix(Xtest)
            ytrain <- as.numeric(ytrain)
            annot <- as.character(annot)
            
            # 2. Fit the linear regression model using graper
            fit <- graper(Xtrain, ytrain, annot, n_rep=3, verbose=FALSE, th=0.001)
            
            # Save the fitted model object
            saveRDS(fit, "fit.rds")
            
            # 3. Plot the ELBO to monitor convergence using plotELBO
            pdf("elbo_plot.pdf")
            print(plotELBO(fit))
            dev.off()
            
            # 4. Plot posterior distributions of parameters using plotPosterior
            pdf("posterior_gamma_plot.pdf")
            print(plotPosterior(fit, "gamma"))
            dev.off()
            
            pdf("posterior_pi_plot.pdf")
            print(plotPosterior(fit, "pi"))
            dev.off()
            
            # 5. Extract coefficients and intercept using coef
            beta <- coef(fit, include_intercept=FALSE)
            intercept <- fit\$intercept
            
            # Handle missing feature names
            feat_names <- names(beta)
            if (is.null(feat_names)) {
              feat_names <- paste0("Feature_", seq_along(beta))
            }
            
            # Save coefficients to CSV
            coef_df <- data.frame(
              Feature = feat_names,
              Beta = as.numeric(beta)
            )
            write.csv(coef_df, "coefficients.csv", row.names = FALSE)
            
            # Save intercept to a text file
            writeLines(as.character(intercept), "intercept.txt")
            
            # 6. Extract posterior inclusion probabilities using getPIPs
            pips <- getPIPs(fit)
            
            # Handle missing feature names
            pip_names <- names(pips)
            if (is.null(pip_names)) {
              pip_names <- paste0("Feature_", seq_along(pips))
            }
            
            # Save PIPs to CSV
            pips_df <- data.frame(
              Feature = pip_names,
              PIP = as.numeric(pips)
            )
            write.csv(pips_df, "pips.csv", row.names = FALSE)
            
            # 7. Plot group-wise penalties using plotGroupPenalties
            pdf("group_penalties_plot.pdf")
            print(plotGroupPenalties(fit))
            dev.off()
            
            # 8. Predict response on new data using predict
            preds <- predict(fit, Xtest)
            
            # Save predictions to CSV
            preds_df <- data.frame(
              Prediction = as.numeric(preds)
            )
            write.csv(preds_df, "predictions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GRAPER_LINEAR_REGRESSION":',
        paste0('    graper: ', as.character(packageVersion('graper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linear_regression.csv versions.yml
    """
}

workflow BIOC_GRAPER_LINEAR_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Xtrain, ytrain, annot, Xtest ] ]

    main:
    BIOC_GRAPER_LINEAR_REGRESSION(ch_input)

    emit:
    tables   = BIOC_GRAPER_LINEAR_REGRESSION.out.tables
    plots    = BIOC_GRAPER_LINEAR_REGRESSION.out.plots
    objects  = BIOC_GRAPER_LINEAR_REGRESSION.out.objects
    versions = BIOC_GRAPER_LINEAR_REGRESSION.out.versions
}
