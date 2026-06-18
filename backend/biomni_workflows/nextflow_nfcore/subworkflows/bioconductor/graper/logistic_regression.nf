#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: graper — logistic_regression
// Fit a group-penalized logistic regression model on high-dimensional binary data, extract coefficients, and make predictions.
// Input: Xtrain, ytrain, annot, Xtest
// Container: quay.io/biocontainers/bioconductor-graper:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, graper
// Visualizations: posterior plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the logistic regression model using graper with family="binomial" and calcELB=FALSE
//  * 2. [Visualization & Output] Plot posterior distributions of parameters using plotPosterior
//  * 3. [Core Analysis] Extract coefficients and intercept using coef
//  * 4. [Core Analysis] Extract posterior inclusion probabilities using getPIPs
//  * 5. [Core Analysis] Predict response on new data using predict

nextflow.enable.dsl = 2

process BIOC_GRAPER_LOGISTIC_REGRESSION {
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
        
        # Robust data loader function
        load_data <- function(name, is_matrix = FALSE) {
          extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
          for (ext in extensions) {
            file_path <- paste0(name, ext)
            if (file.exists(file_path)) {
              # Try RDS
              if (ext == ".rds" || ext == "") {
                obj <- try(readRDS(file_path), silent = TRUE)
                if (!inherits(obj, "try-error")) {
                  if (is_matrix) return(as.matrix(obj))
                  return(as.vector(obj))
                }
              }
              # Try CSV/TSV
              if (ext == ".csv" || ext == ".tsv" || ext == "") {
                sep <- if (ext == ".tsv") "\t" else ","
                obj <- try(read.table(file_path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE), silent = TRUE)
                if (!inherits(obj, "try-error")) {
                  if (is_matrix) return(as.matrix(obj))
                  if (ncol(obj) == 1) return(obj[[1]])
                  return(as.vector(as.matrix(obj)))
                }
                # Try without row.names
                obj <- try(read.table(file_path, header = FALSE, sep = sep), silent = TRUE)
                if (!inherits(obj, "try-error")) {
                  if (is_matrix) return(as.matrix(obj))
                  if (ncol(obj) == 1) return(obj[[1]])
                  return(as.vector(as.matrix(obj)))
                }
              }
              # Try plain text
              if (ext == ".txt" || ext == "") {
                obj <- try(readLines(file_path), silent = TRUE)
                if (!inherits(obj, "try-error")) {
                  num_obj <- as.numeric(obj)
                  if (!any(is.na(num_obj))) {
                    obj <- num_obj
                  }
                  if (is_matrix) return(as.matrix(obj))
                  return(as.vector(obj))
                }
              }
            }
          }
          stop(paste("Could not load file:", name))
        }
        
        # Load user inputs
        Xtrain <- load_data("Xtrain", is_matrix = TRUE)
        ytrain <- load_data("ytrain", is_matrix = FALSE)
        annot  <- load_data("annot", is_matrix = FALSE)
        Xtest  <- load_data("Xtest", is_matrix = TRUE)
        
        # Initialize data list for true parameters if available, otherwise NULL
        data <- list(gammas = NULL, pis = NULL)
        tryCatch({
          if (file.exists("gammas.rds") || file.exists("gammas.csv") || file.exists("gammas.txt")) {
            data\$gammas <- load_data("gammas")
          }
        }, error = function(e) NULL)
        
        tryCatch({
          if (file.exists("pis.rds") || file.exists("pis.csv") || file.exists("pis.txt")) {
            data\$pis <- load_data("pis")
          }
        }, error = function(e) NULL)
        
        # 1. Fit the logistic regression model
        fit <- graper(Xtrain, ytrain, annot, verbose=FALSE, family="binomial", calcELB=FALSE)
        
        # 2. Plot posterior distributions of parameters
        pdf("posterior_plots.pdf")
        print(plotPosterior(fit, "gamma", gamma0=data\$gammas))
        print(plotPosterior(fit, "pi", pi0=data\$pis))
        dev.off()
        
        # 3. Extract coefficients and intercept
        beta <- coef(fit, include_intercept=FALSE)
        intercept <- fit\$intercept
        
        # 4. Extract posterior inclusion probabilities
        pips <- getPIPs(fit)
        
        # 5. Predict response on new data
        preds <- predict(fit, Xtest)
        
        # Save outputs
        saveRDS(fit, "fit.rds")
        write.csv(as.data.frame(beta), "coefficients.csv")
        writeLines(as.character(intercept), "intercept.txt")
        write.csv(as.data.frame(pips), "pips.csv")
        write.csv(as.data.frame(preds), "predictions.csv")
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_GRAPER_LOGISTIC_REGRESSION":',
        paste0('    graper: ', as.character(packageVersion('graper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_logistic_regression.csv versions.yml
    """
}

workflow BIOC_GRAPER_LOGISTIC_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Xtrain, ytrain, annot, Xtest ] ]

    main:
    BIOC_GRAPER_LOGISTIC_REGRESSION(ch_input)

    emit:
    tables   = BIOC_GRAPER_LOGISTIC_REGRESSION.out.tables
    plots    = BIOC_GRAPER_LOGISTIC_REGRESSION.out.plots
    objects  = BIOC_GRAPER_LOGISTIC_REGRESSION.out.objects
    versions = BIOC_GRAPER_LOGISTIC_REGRESSION.out.versions
}
