#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fmrs — fmrs_mle_and_variable_selection
// Fit a finite mixture of regression/AFT model, select optimal tuning parameters, and perform sparse variable selection.
// Input: y, x, delta
// Container: quay.io/biocontainers/bioconductor-fmrs:1.20.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: fmrs
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the initial FMR/AFT model using Maximum Likelihood Estimation with fmrs.mle
//  * 2. [Core Analysis] Select component-wise tuning parameters using fmrs.tunsel with MLE estimates as initial values
//  * 3. [Core Analysis] Perform sparse variable selection using fmrs.varsel with the selected tuning parameters
//  * 4. [Core Analysis] Extract the selected active set of covariates using slot(..., "selectedset")

nextflow.enable.dsl = 2

process BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION {
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
    .bm_deps <- c("fmrs")
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
    
    # Load required library
    library(fmrs)
    
    # Helper function to read vector input robustly
    read_vector <- function(filepath) {
      if (file.exists(paste0(filepath, ".rds"))) {
        return(as.numeric(readRDS(paste0(filepath, ".rds"))))
      }
      actual_path <- if (file.exists(filepath)) filepath else paste0(filepath, ".csv")
      if (!file.exists(actual_path)) {
        stop(paste("Required input file not found:", filepath))
      }
      
      first_line <- readLines(actual_path, n = 1)
      has_header <- !all(grepl("^[0-9eE\\\\.\\\\-\\\\+\\\\s,;]+\$", first_line))
      
      df <- read.csv(actual_path, header = has_header)
      return(as.numeric(df[[1]]))
    }
    
    # Helper function to read matrix input robustly
    read_matrix <- function(filepath) {
      if (file.exists(paste0(filepath, ".rds"))) {
        return(as.matrix(readRDS(paste0(filepath, ".rds"))))
      }
      actual_path <- if (file.exists(filepath)) filepath else paste0(filepath, ".csv")
      if (!file.exists(actual_path)) {
        stop(paste("Required input file not found:", filepath))
      }
      
      first_line <- readLines(actual_path, n = 1)
      has_header <- !all(grepl("^[0-9eE\\\\.\\\\-\\\\+\\\\s,;]+\$", first_line))
      
      df <- read.csv(actual_path, header = has_header)
      return(as.matrix(df))
    }
    
    # Read user inputs from the working directory
    y <- read_vector("y")
    x <- read_matrix("x")
    delta <- read_vector("delta")
    
    # Determine dimensions and parameters
    nComp <- as.integer(Sys.getenv("FMRS_NCOMP", unset = "2"))
    nCov <- ncol(x)
    
    # Set seed for reproducibility of EM/NR initialization
    set.seed(1980)
    
    # 1. Fit the initial FMR/AFT model using Maximum Likelihood Estimation
    res.mle <- fmrs.mle(y = y, x = x, delta = delta,
                       nComp = nComp, disFamily = "lnorm",
                       initCoeff = rnorm(nComp*nCov+nComp),
                       initDispersion = rep(1, nComp),
                       initmixProp = rep(1/nComp, nComp))
    summary(res.mle)
    
    # 2. Select component-wise tuning parameters using fmrs.tunsel
    res.lam <- fmrs.tunsel(y = y, x = x, delta = delta,
                          nComp = nComp, disFamily = "lnorm",
                          initCoeff = c(coefficients(res.mle)),
                          initDispersion = dispersion(res.mle),
                          initmixProp = mixProp(res.mle),
                          penFamily = "adplasso")
    summary(res.lam)
    
    # 3. Perform sparse variable selection using fmrs.varsel
    res.var <- fmrs.varsel(y = y, x = x, delta = delta,
                          nComp = ncomp(res.mle), disFamily = "lnorm",
                          initCoeff=c(coefficients(res.mle)),
                          initDispersion = dispersion(res.mle),
                          initmixProp = mixProp(res.mle),
                          penFamily = "adplasso",
                          lambPen = slot(res.lam, "lambPen"))
    summary(res.var)
    
    # 4. Extract the selected active set of covariates
    selected_set <- slot(res.var, "selectedset")
    
    # Save RDS objects
    saveRDS(res.mle, "res_mle.rds")
    saveRDS(res.lam, "res_lam.rds")
    saveRDS(res.var, "res_var.rds")
    
    # Save text summaries
    writeLines(capture.output(summary(res.mle)), "mle_summary.txt")
    writeLines(capture.output(summary(res.lam)), "lam_summary.txt")
    writeLines(capture.output(summary(res.var)), "var_summary.txt")
    
    # Save tabular outputs
    write.csv(as.data.frame(selected_set), "selected_set.csv", row.names = TRUE)
    
    tryCatch({
      coef_var <- coefficients(res.var)
      write.csv(as.data.frame(coef_var), "coefficients_var.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not extract coefficients from res.var directly.")
    })
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION":',
        paste0('    fmrs: ', as.character(packageVersion('fmrs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fmrs_mle_and_variable_selection.csv versions.yml
    """
}

workflow BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y, x, delta ] ]

    main:
    BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION(ch_input)

    emit:
    tables   = BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION.out.tables
    plots    = BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION.out.plots
    objects  = BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION.out.objects
    versions = BIOC_FMRS_FMRS_MLE_AND_VARIABLE_SELECTION.out.versions
}
