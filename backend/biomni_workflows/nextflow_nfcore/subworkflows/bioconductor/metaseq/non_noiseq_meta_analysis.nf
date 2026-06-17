#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaSeq — non_noiseq_meta_analysis
// Perform meta-analysis using one-sided p-values generated from non-NOISeq methods (e.g., DESeq, edgeR, Cuffdiff).
// Input: upper, lower, weight
// Container: quay.io/biocontainers/bioconductor-metaseq:1.50.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metaSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the custom p-value matrices and weights using other.oneside.pvalues
//  * 2. [Core Analysis] Combine the p-values using Fisher.test and Stouffer.test

nextflow.enable.dsl = 2

process BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS {
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
    .bm_deps <- c("metaSeq")
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
    library(metaSeq)
    
    # Helper function to read matrix input robustly
    read_input_matrix <- function(filepath) {
      if (!file.exists(filepath)) {
        exts <- c(".csv", ".tsv", ".txt")
        found <- FALSE
        for (ext in exts) {
          if (file.exists(paste0(filepath, ext))) {
            filepath <- paste0(filepath, ext)
            found <- TRUE
            break
          }
        }
        if (!found) {
          stop(paste("Error: Input matrix file not found for prefix:", filepath))
        }
      }
      
      # Attempt reading as CSV first, then TSV
      mat <- tryCatch({
        as.matrix(read.csv(filepath, row.names = 1, check.names = FALSE))
      }, error = function(e) {
        tryCatch({
          as.matrix(read.table(filepath, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
        }, error = function(e2) {
          as.matrix(read.table(filepath, header = TRUE, row.names = 1, check.names = FALSE))
        })
      })
      return(mat)
    }
    
    # Helper function to read vector input robustly
    read_input_vector <- function(filepath) {
      if (!file.exists(filepath)) {
        exts <- c(".csv", ".tsv", ".txt")
        found <- FALSE
        for (ext in exts) {
          if (file.exists(paste0(filepath, ext))) {
            filepath <- paste0(filepath, ext)
            found <- TRUE
            break
          }
        }
        if (!found) {
          stop(paste("Error: Input vector file not found for prefix:", filepath))
        }
      }
      
      # Attempt reading as simple scan, then CSV row
      vec <- tryCatch({
        as.numeric(scan(filepath, quiet = TRUE))
      }, error = function(e) {
        tryCatch({
          as.numeric(read.csv(filepath, header = FALSE)[1, ])
        }, error = function(e2) {
          stop(paste("Error reading vector from file:", filepath))
        })
      })
      return(vec)
    }
    
    # 1. Read User Inputs
    upper <- read_input_matrix("upper")
    lower <- read_input_matrix("lower")
    weight <- read_input_vector("weight")
    
    # 2. Format the custom p-value matrices and weights
    result <- other.oneside.pvalues(upper, lower, weight)
    
    # 3. Combine the p-values using Fisher's method
    F <- Fisher.test(result)
    str(F)
    head(F\$Upper)
    head(F\$Lower)
    F\$Weight
    
    # 4. Combine the p-values using Stouffer's method
    S <- Stouffer.test(result)
    str(S)
    head(S\$Upper)
    head(S\$Lower)
    S\$Weight
    
    # 5. Write meaningful output files
    # Save Fisher's test results
    fisher_df <- data.frame(
      Gene = names(F\$Upper),
      Fisher_Upper = F\$Upper,
      Fisher_Lower = F\$Lower,
      stringsAsFactors = FALSE
    )
    write.csv(fisher_df, file = "fisher_test_results.csv", row.names = FALSE)
    
    # Save Stouffer's test results
    stouffer_df <- data.frame(
      Gene = names(S\$Upper),
      Stouffer_Upper = S\$Upper,
      Stouffer_Lower = S\$Lower,
      stringsAsFactors = FALSE
    )
    write.csv(stouffer_df, file = "stouffer_test_results.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(F, file = "fisher_test_object.rds")
    saveRDS(S, file = "stouffer_test_object.rds")
    
    # Optional: Generate a comparison plot of Fisher vs Stouffer p-values
    tryCatch({
      pdf("pvalue_comparison_plots.pdf", width = 10, height = 5)
      par(mfrow = c(1, 2))
      plot(F\$Upper, S\$Upper, 
           xlab = "Fisher's Method (Upper)", 
           ylab = "Stouffer's Method (Upper)", 
           main = "Upper-regulated P-values",
           col = "blue", pch = 20)
      abline(0, 1, col = "red", lty = 2)
      
      plot(F\$Lower, S\$Lower, 
           xlab = "Fisher's Method (Lower)", 
           ylab = "Stouffer's Method (Lower)", 
           main = "Lower-regulated P-values",
           col = "darkgreen", pch = 20)
      abline(0, 1, col = "red", lty = 2)
      dev.off()
    }, error = function(e) {
      warning("Could not generate comparison plots: ", e\$message)
    })

    writeLines(c(
        '"BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS":',
        paste0('    metaSeq: ', as.character(packageVersion('metaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_noiseq_meta_analysis.csv versions.yml
    """
}

workflow BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ upper, lower, weight ] ]

    main:
    BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.tables
    plots    = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.plots
    objects  = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.objects
    versions = BIOC_METASEQ_NON_NOISEQ_META_ANALYSIS.out.versions
}
