#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methyLImp2 — methylation_imputation
// Impute missing values in DNA methylation data using parallelized linear regression and optional mini-batching.
// Input: beta_SE
// Container: quay.io/biocontainers/bioconductor-methylimp2:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SummarizedExperiment, methyLImp2
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the DNA methylation data and metadata
//  * 2. [Input & Preparation] Run the methyLImp2 imputation algorithm
//  * 3. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_METHYLIMP2_METHYLATION_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("methyLImp2", "BiocParallel", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(methyLImp2)
    library(BiocParallel)
    
    # --- Load the DNA methylation data and metadata ---
    # The pipeline reads the user-provided SummarizedExperiment object from the working directory.
    if (file.exists("beta_SE.rds")) {
      beta_SE <- readRDS("beta_SE.rds")
    } else if (file.exists("beta_SE")) {
      beta_SE <- readRDS("beta_SE")
    } else {
      stop("Error: Input file 'beta_SE.rds' or 'beta_SE' not found in the working directory.")
    }
    
    # --- Run the methyLImp2 imputation algorithm ---
    # Specifying the array type, parallelization settings, and mini-batch fraction exactly as documented.
    time <- system.time(beta_SE_imputed <- methyLImp2(input = beta_SE, 
                                                   type = "EPIC", 
                                                   BPPARAM = SnowParam(exportglobals = FALSE),
                                                   minibatch_frac = 0.5))
    
    # --- Write named output files for the meaningful results ---
    # Save the complete imputed SummarizedExperiment object
    saveRDS(beta_SE_imputed, "beta_SE_imputed.rds")
    
    # Extract and save the imputed beta values matrix as a CSV file
    imputed_matrix <- assay(beta_SE_imputed)
    write.csv(imputed_matrix, "imputed_beta_values.csv", row.names = TRUE)
    
    # Save runtime performance metrics
    runtime_message <- paste0("Runtime was ", round(time[3], digits = 2), " seconds.")
    writeLines(runtime_message, "runtime.txt")
    cat(runtime_message, "\n")

    writeLines(c(
        '"BIOC_METHYLIMP2_METHYLATION_IMPUTATION":',
        paste0('    methyLImp2: ', as.character(packageVersion('methyLImp2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_imputation.csv versions.yml
    """
}

workflow BIOC_METHYLIMP2_METHYLATION_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta_SE ] ]

    main:
    BIOC_METHYLIMP2_METHYLATION_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_METHYLIMP2_METHYLATION_IMPUTATION.out.tables
    plots    = BIOC_METHYLIMP2_METHYLATION_IMPUTATION.out.plots
    objects  = BIOC_METHYLIMP2_METHYLATION_IMPUTATION.out.objects
    versions = BIOC_METHYLIMP2_METHYLATION_IMPUTATION.out.versions
}
