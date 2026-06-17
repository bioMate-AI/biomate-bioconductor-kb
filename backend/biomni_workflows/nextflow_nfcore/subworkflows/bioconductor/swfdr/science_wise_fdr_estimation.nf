#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: swfdr — science_wise_fdr_estimation
// Estimate the science-wise false discovery rate from published literature p-values, accounting for rounding and truncation.
// Input: journals_pVals
// Container: quay.io/biocontainers/bioconductor-swfdr:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, swfdr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter the dataset to keep only p-values below 0.05
//  * 2. [Input & Preparation] Define vectors indicating truncation and rounding status
//  * 3. [Core Analysis] Run the EM algorithm using calculateSwfdr to estimate the overall false discovery rate (pi0)

nextflow.enable.dsl = 2

process BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION {
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
    .bm_deps <- c("swfdr", "dplyr")
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
    library(swfdr)
    library(dplyr)
    
    # Read user input file from the working directory
    if (file.exists("journals_pVals.rds")) {
      journals_pVals <- readRDS("journals_pVals.rds")
    } else if (file.exists("journals_pVals.csv")) {
      journals_pVals <- read.csv("journals_pVals.csv", stringsAsFactors = FALSE)
    } else if (file.exists("journals_pVals")) {
      journals_pVals <- read.csv("journals_pVals", stringsAsFactors = FALSE)
    } else {
      stop("Error: Input file 'journals_pVals' (CSV or RDS) not found in the working directory.")
    }
    
    # Ensure correct column ordering for index-based subsetting in the documented code
    expected_cols <- c("pvalue", "pvalueTruncated", "pubmedID", "year", "journal")
    if (all(expected_cols %in% colnames(journals_pVals))) {
      journals_pVals <- journals_pVals[, expected_cols]
    }
    journals_pVals <- as.data.frame(journals_pVals)
    
    # === DOCUMENTED CODE ===
    journals_pVals1 <- dplyr::filter(journals_pVals,
                                     pvalue < 0.05)
    tt <- journals_pVals1\$pvalueTruncated
    rr <- rep(0,length(tt))
    rr[tt == 0] <- (journals_pVals1\$pvalue[tt==0] == 
                      round(journals_pVals1\$pvalue[tt==0],2))
    pVals <- journals_pVals1\$pvalue
    resSwfdr <- calculateSwfdr(pValues = pVals, 
                               truncated = tt, 
                               rounded = rr, numEmIterations=100)
    # === END DOCUMENTED CODE ===
    
    # Save the complete results object as RDS
    saveRDS(resSwfdr, "resSwfdr.rds")
    
    # Save key parameter estimates (pi0, a) as a CSV
    estimates_df <- data.frame(
      Parameter = c("pi0", "a"),
      Value = c(resSwfdr\$pi0, resSwfdr\$a)
    )
    write.csv(estimates_df, "swfdr_estimates.csv", row.names = FALSE)
    
    # Save detailed z-values (expected values of the indicator of whether the p-value is null)
    z_df <- data.frame(
      pvalue = pVals,
      truncated = tt,
      rounded = rr,
      z = resSwfdr\$z
    )
    write.csv(z_df, "swfdr_z_values.csv", row.names = FALSE)
    
    # Save rounded p-value counts and expected nulls
    n_df <- data.frame(
      Interval = c("(0.005,0.015]", "(0.015,0.025]", "(0.025,0.035]", "(0.035,0.045]", "(0.045,0.05]"),
      Expected_Nulls = as.numeric(resSwfdr\$n0),
      Observed_Rounded = as.numeric(resSwfdr\$n)
    )
    write.csv(n_df, "swfdr_rounded_counts.csv", row.names = FALSE)
    
    # Generate diagnostic plot of the p-values and the estimated pi0 threshold
    pdf("swfdr_diagnostics.pdf", width = 8, height = 6)
    hist(pVals, breaks = 20, col = "lightgray", border = "white",
         main = "P-values < 0.05",
         xlab = "p-value", ylab = "Frequency")
    abline(h = length(pVals) * resSwfdr\$pi0 / 20, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = c(paste("Estimated pi0 =", round(resSwfdr\$pi0, 4))),
           col = "red", lty = 2, lwd = 2)
    dev.off()

    writeLines(c(
        '"BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION":',
        paste0('    swfdr: ', as.character(packageVersion('swfdr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_science_wise_fdr_estimation.csv versions.yml
    """
}

workflow BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ journals_pVals ] ]

    main:
    BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION.out.tables
    plots    = BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION.out.plots
    objects  = BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION.out.objects
    versions = BIOC_SWFDR_SCIENCE_WISE_FDR_ESTIMATION.out.versions
}
