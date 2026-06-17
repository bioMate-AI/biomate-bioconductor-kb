#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mdqc — multivariate_qc_assessment
// Perform multivariate quality control assessment on microarray QC reports using Mahalanobis Distance to identify and diagnose outlying arrays.
// Input: allQC.csv
// Container: quay.io/biocontainers/bioconductor-mdqc:1.72.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mdqc
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and the QC report data
//  * 2. [Core Analysis] Run MDQC using the desired grouping or dimensionality reduction method (e.g., "nogroups", "apriori", "cluster", "loading", or "glo
//  * 3. [Visualization & Output] Plot the Mahalanobis distances against Chi-Squared distribution cutoffs to visually identify outliers
//  * 4. [Visualization & Output] Print and summarize the MDQC output to list flagged arrays exceeding the 90%, 95%, and 99% thresholds

nextflow.enable.dsl = 2

process BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT {
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
    .bm_deps <- c("mdqc")
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
            
        # 1. Load the required package
        library(mdqc)
        
        # 2. Read the user-provided input file
        if (!file.exists("allQC.csv")) {
          stop("Error: Input file 'allQC.csv' not found in the working directory.")
        }
        
        # Read the CSV file, preserving row names (arrays) and column names (QC metrics)
        allQC <- read.csv("allQC.csv", row.names = 1, check.names = FALSE)
        allQC <- as.data.frame(allQC)
        
        # Display dimensions and first few rows as in the vignette
        dim(allQC)
        allQC[1:2,]
        
        # Determine method based on user input or adapt to data
        args <- commandArgs(trailingOnly = TRUE)
        if (length(args) > 0) {
          method_choice <- args[1]
        } else {
          # Adapt to input data: MDQC requires the number of observations (rows) 
          # to be >= the number of quality measures (columns) for 'nogroups'.
          if (nrow(allQC) >= ncol(allQC)) {
            method_choice <- "nogroups"
          } else {
            # 'global' requires n > p, so default to 'apriori' when p > n
            method_choice <- "apriori"
          }
        }
        
        # Open a PDF device to capture all visual diagnostic plots
        pdf("mdqc_visualizations.pdf", width = 10, height = 8)
        
        if (method_choice == "nogroups") {
            # 3. Run MDQC using "nogroups" method
            mdout <- mdqc(allQC, method="nogroups") 
            plot(mdout) 
            print(mdout)
            summary(mdout)
            
            # Save outputs for "nogroups"
            saveRDS(mdout, "mdout_nogroups.rds")
            sink("mdout_nogroups_report.txt")
            cat("=== MDQC NOGROUPS REPORT ===\n")
            print(mdout)
            cat("\n=== SUMMARY ===\n")
            summary(mdout)
            sink()
        
        } else if (method_choice == "apriori") {
            # 4. Run MDQC using "apriori" grouping method
            # Dynamically create groups to avoid hardcoded indices and adapt to dataset dimensions
            k_apriori <- min(ncol(allQC), max(3, ceiling(ncol(allQC) / nrow(allQC))))
            groups_list <- unname(split(1:ncol(allQC), cut(1:ncol(allQC), breaks = k_apriori, labels = FALSE)))
            
            mdout <- mdqc(allQC, method="apriori", groups=groups_list)
            plot(mdout) 
            
            # Save outputs for "apriori"
            saveRDS(mdout, "mdout_apriori.rds")
            sink("mdout_apriori_report.txt")
            cat("=== MDQC APRIORI REPORT ===\n")
            print(mdout)
            cat("\n=== SUMMARY ===\n")
            summary(mdout)
            sink()
        
        } else if (method_choice == "cluster") {
            # 5. Run MDQC using "cluster" grouping method
            # Dynamically set k to avoid hardcoded values and ensure p <= n per cluster
            k_val <- min(ncol(allQC), max(3, ceiling(ncol(allQC) / nrow(allQC))))
            mdout <- NULL
            
            # Increment k until the clustering algorithm produces groups where p <= n
            while (k_val <= ncol(allQC)) {
                mdout <- try(mdqc(allQC, method="cluster", k=k_val), silent=TRUE)
                if (!inherits(mdout, "try-error")) {
                    break
                }
                k_val <- k_val + 1
            }
            
            if (inherits(mdout, "try-error")) {
                stop("Error: Could not find a valid k for cluster method where p <= n for all clusters.")
            }
            
            plot(mdout) 
            print(mdout)
            
            # Save outputs for "cluster"
            saveRDS(mdout, "mdout_cluster.rds")
            sink("mdout_cluster_report.txt")
            cat("=== MDQC CLUSTER REPORT ===\n")
            print(mdout)
            cat("\n=== SUMMARY ===\n")
            summary(mdout)
            sink()
        
        } else if (method_choice == "loading") {
            # 6. Run MDQC using "loading" grouping method
            # Dynamically set k and pc to avoid hardcoded values and adapt to dataset dimensions
            k_val <- min(ncol(allQC), max(3, ceiling(ncol(allQC) / nrow(allQC))))
            pc_val <- max(1, min(4, ncol(allQC), nrow(allQC) - 1))
            mdout <- NULL
            
            # Increment k until the clustering algorithm produces groups where p <= n
            while (k_val <= ncol(allQC)) {
                mdout <- try(mdqc(allQC, method="loading", k=k_val, pc=pc_val), silent=TRUE)
                if (!inherits(mdout, "try-error")) {
                    break
                }
                k_val <- k_val + 1
            }
            
            if (inherits(mdout, "try-error")) {
                stop("Error: Could not find a valid k for loading method where p <= n for all clusters.")
            }
            
            plot(mdout)
            print(mdout)
            
            # Save outputs for "loading"
            saveRDS(mdout, "mdout_loading.rds")
            sink("mdout_loading_report.txt")
            cat("=== MDQC LOADING REPORT ===\n")
            print(mdout)
            cat("\n=== SUMMARY ===\n")
            summary(mdout)
            sink()
        
        } else if (method_choice == "global") {
            # 7. Run MDQC using "global" PCA method
            # Dynamically set pc to avoid hardcoded values and adapt to dataset dimensions
            pc_val <- max(1, min(4, ncol(allQC), nrow(allQC) - 1))
            mdout <- mdqc(allQC, method="global", pc=pc_val)
            plot(mdout)
            
            # Save outputs for "global"
            saveRDS(mdout, "mdout_global.rds")
            sink("mdout_global_report.txt")
            cat("=== MDQC GLOBAL REPORT ===\n")
            print(mdout)
            cat("\n=== SUMMARY ===\n")
            summary(mdout)
            sink()
        
        } else {
            stop(paste("Error: Unknown method", method_choice))
        }
        
        # Close the PDF device
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT":',
        paste0('    mdqc: ', as.character(packageVersion('mdqc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multivariate_qc_assessment.csv versions.yml
    """
}

workflow BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ allQC.csv ] ]

    main:
    BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT.out.tables
    plots    = BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT.out.plots
    objects  = BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT.out.objects
    versions = BIOC_MDQC_MULTIVARIATE_QC_ASSESSMENT.out.versions
}
