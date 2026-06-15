#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCASPAR — survival_prediction_with_cross_validation
// Perform k-fold cross-validation on a single dataset to train and predict survival times using high-dimensional covariates.
// Input: geData, survData
// Container: quay.io/biocontainers/bioconductor-rcaspar:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RCASPAR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform k-fold cross-validation to predict survival times
//  * 2. [Visualization & Output] Plot Kaplan-Meier survival curves for predicted long and short survivors
//  * 3. [Visualization & Output] Calculate and plot the Area Under the ROC Curve (AURC)
//  * 4. [Core Analysis] Perform a log-rank test to compare the predicted survivor groups

nextflow.enable.dsl = 2

process BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION {
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
    .bm_deps <- c("RCASPAR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Load required library
    library(RCASPAR)
    
    # Helper function to robustly read user input files
    read_input_file <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".csv"),
        paste0(base_name, ".rds"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            return(readRDS(f))
          } else if (grepl("\\\\.(csv|txt|tsv)\$", f, ignore.case = TRUE) || f == base_name) {
            df <- tryCatch({
              read.csv(f, row.names = 1, check.names = FALSE)
            }, error = function(e) {
              tryCatch({
                read.table(f, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
              }, error = function(e2) {
                NULL
              })
            })
            if (!is.null(df)) return(df)
          }
        }
      }
      stop(paste("Could not find or read input file for:", base_name))
    }
    
    # 1. Read user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    geData_raw <- read_input_file("geData")
    geData <- as.matrix(geData_raw)
    # Replace missing values with zeros as required by RCASPAR
    geData[is.na(geData)] <- 0
    
    survData <- read_input_file("survData")
    
    # Ensure survData is a data frame
    survData <- as.data.frame(survData)
    
    # Define parameters for cross-validation
    k <- 3
    cut.off <- median(survData\$True_STs, na.rm = TRUE)
    q <- 1
    s <- 1
    a <- 1.558
    b <- 0.179
    groups <- 3
    method <- "CG"
    noprior <- 1
    extras <- list(reltol = 1)
    
    # 2. Perform k-fold cross-validation to predict survival times
    result <- STpredictor_xvBLH(geData, survData, k, cut.off, q, s, a, b, groups, method, noprior, extras)
    
    # Save the main result object
    saveRDS(result, "xv_results.rds")
    
    # 3. Plot Kaplan-Meier survival curves for predicted long and short survivors
    pdf("km_plot.pdf")
    kmplt_svrl(long = result\$long_survivors, short = result\$short_survivors, title = "KM plot of long and short survivors")
    dev.off()
    
    # 4. Calculate and plot the Area Under the ROC Curve (AURC)
    time.max <- max(result\$predicted_STs\$True_STs, na.rm = TRUE)
    pdf("aurc_plot.pdf")
    aurc_res <- survivAURC(Stime = result\$predicted_STs\$True_STs, status = result\$predicted_STs\$censored, marker = result\$predicted_STs\$Predicted_STs, time.max = time.max)
    dev.off()
    
    # Save AURC numerical results
    saveRDS(aurc_res, "aurc_results.rds")
    
    # 5. Perform a log-rank test to compare the predicted survivor groups
    logrank_res <- logrnk(dataL = result\$long_survivors, dataS = result\$short_survivors)
    
    # Save log-rank test results to CSV
    logrank_df <- data.frame(
      Statistic = "Chi-squared",
      Value = logrank_res\$Xsq,
      pValue = logrank_res\$pValue
    )
    write.csv(logrank_df, "logrank_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION":',
        paste0('    RCASPAR: ', as.character(packageVersion('RCASPAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_prediction_with_cross_validation.csv versions.yml
    """
}

workflow BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geData, survData ] ]

    main:
    BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION.out.tables
    plots    = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION.out.plots
    objects  = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION.out.objects
    versions = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_CROSS_VALIDATION.out.versions
}
