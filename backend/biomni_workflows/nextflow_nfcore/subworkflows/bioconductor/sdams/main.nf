#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sdams — csv_to_sda
// Create a SummarizedExperiment object from feature and group CSV files and perform semi-parametric differential abundance analysis.
// Input: feature.csv, group.csv
// Container: quay.io/biocontainers/bioconductor-sdams:1.30.0--r45hdfd78af_0
// R packages: SDAMS
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SDAMS_CSV_TO_SDA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sdams:1.30.0--r45hdfd78af_0"

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
    .bm_deps <- c("SDAMS")
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
    
    # --- Define paths to the feature and group CSV files ---
    path1 <- "feature.csv"
    path2 <- "group.csv"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(path1)) {
      stop("Error: Required input file 'feature.csv' not found in the working directory.")
    }
    if (!file.exists(path2)) {
      stop("Error: Required input file 'group.csv' not found in the working directory.")
    }
    
    # --- Load the SDAMS library ---
    library("SDAMS")
    
    # --- Create a SummarizedExperiment object using createSEFromCSV ---
    exampleSE1 <- createSEFromCSV(path1, path2)
    
    # Save the constructed SummarizedExperiment object
    saveRDS(exampleSE1, file = "sda_se.rds")
    
    # --- Perform differential abundance analysis using SDA ---
    results <- SDA(exampleSE1)
    
    # Save the complete results list object
    saveRDS(results, file = "sda_results.rds")
    
    # --- Extract and display results for gamma, beta, and the ---
    cat("=== Head of Gamma ===\n")
    print(head(results\$gamma[, 1]))
    
    cat("\n=== Head of P-Value Gamma ===\n")
    print(head(results\$pv_gamma[, 1]))
    
    cat("\n=== Head of Q-Value Gamma ===\n")
    print(head(results\$qv_gamma[, 1]))
    
    cat("\n=== Head of Beta ===\n")
    print(head(results\$beta[, 1]))
    
    cat("\n=== Head of P-Value Beta ===\n")
    print(head(results\$pv_beta[, 1]))
    
    cat("\n=== Head of Q-Value Beta ===\n")
    print(head(results\$qv_beta[, 1]))
    
    cat("\n=== Head of P-Value 2-Part ===\n")
    print(head(results\$pv_2part[, 1]))
    
    cat("\n=== Head of Q-Value 2-Part ===\n")
    print(head(results\$qv_2part[, 1]))
    
    cat("\n=== Head of Feature Names ===\n")
    print(head(results\$feat.names))
    
    # Construct a comprehensive data frame of the results and export to CSV
    results_df <- data.frame(
      Feature = results\$feat.names,
      Gamma = results\$gamma[, 1],
      PValue_Gamma = results\$pv_gamma[, 1],
      QValue_Gamma = results\$qv_gamma[, 1],
      Beta = results\$beta[, 1],
      PValue_Beta = results\$pv_beta[, 1],
      QValue_Beta = results\$qv_beta[, 1],
      PValue_2part = results\$pv_2part[, 1],
      QValue_2part = results\$qv_2part[, 1],
      stringsAsFactors = FALSE
    )
    
    write.csv(results_df, file = "sda_results.csv", row.names = FALSE)
    
    cat("\nPipeline completed successfully.\n")
    cat("Outputs written:\n")
    cat("- 'sda_se.rds' (SummarizedExperiment object)\n")
    cat("- 'sda_results.rds' (Raw SDA results list)\n")
    cat("- 'sda_results.csv' (Structured results table)\n")

    writeLines(c(
        '"BIOC_SDAMS_CSV_TO_SDA":',
        paste0('        sdams: ', as.character(packageVersion("sdams")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_csv_to_sda.csv versions.yml
    """
}

workflow BIOC_SDAMS_CSV_TO_SDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ feature.csv, group.csv ] ]

    main:
    BIOC_SDAMS_CSV_TO_SDA(ch_input)

    emit:
    tables   = BIOC_SDAMS_CSV_TO_SDA.out.tables
    plots    = BIOC_SDAMS_CSV_TO_SDA.out.plots
    objects  = BIOC_SDAMS_CSV_TO_SDA.out.objects
    versions = BIOC_SDAMS_CSV_TO_SDA.out.versions
}
