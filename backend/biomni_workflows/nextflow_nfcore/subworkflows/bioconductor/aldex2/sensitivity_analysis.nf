#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ALDEx2 — sensitivity_analysis
// Assess how differential abundance results change across a range of scale uncertainty (gamma) values.
// Input: Y, conds
// Container: quay.io/biocontainers/bioconductor-aldex2:1.42.0--r45hdfd78af_0
// R packages: ALDEx2
// Bioconductor: 3.20 | R: 4.4
// Requires: ALDEx2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate base CLR instances using `aldex.clr`
//  * 2. [Core Analysis] Run sensitivity analysis using `aldex.senAnalysis`
//  * 3. [Visualization & Output] Plot sensitivity results using `plotGamma`

nextflow.enable.dsl = 2

process BIOC_ALDEX2_SENSITIVITY_ANALYSIS {
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
    .bm_deps <- c("ALDEx2")
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
    library(ALDEx2)
    
    # Helper to read Y (count matrix of features by samples)
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y <- read.csv("Y.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("Y.tsv")) {
      Y <- read.delim("Y.tsv", row.names = 1, check.names = FALSE)
    } else {
      stop("Error: Count matrix file 'Y' not found. Please provide Y.rds, Y.csv, or Y.tsv in the working directory.")
    }
    
    # Helper to read conds (vector of group conditions)
    if (file.exists("conds.rds")) {
      conds <- readRDS("conds.rds")
    } else if (file.exists("conds.csv")) {
      conds_df <- read.csv("conds.csv", header = FALSE)
      conds <- as.vector(t(conds_df))
    } else if (file.exists("conds.tsv")) {
      conds_df <- read.delim("conds.tsv", header = FALSE)
      conds <- as.vector(t(conds_df))
    } else if (file.exists("conds.txt")) {
      conds <- readLines("conds.txt")
    } else {
      stop("Error: Conditions file 'conds' not found. Please provide conds.rds, conds.csv, conds.tsv, or conds.txt in the working directory.")
    }
    
    # Ensure correct data types for ALDEx2
    Y <- as.matrix(Y)
    conds <- as.character(conds)
    
    # Define gamma values to test
    gamma_to_test <- c(1e-3, .1, .25, .5, .75, 1, 2, 3, 4, 5)
    
    ## Run the CLR function
    clr <- aldex.clr(Y, conds)
    
    ## Run sensitivity analysis function
    sen_res <- aldex.senAnalysis(clr, gamma = gamma_to_test)
    
    ## Plotting and saving the plot to a PDF file
    pdf("sensitivity_analysis_plot.pdf", width = 8, height = 6)
    plotGamma(sen_res, thresh = .1)
    dev.off()
    
    # Save the sensitivity analysis results
    saveRDS(sen_res, "sensitivity_analysis_results.rds")
    
    tryCatch({
      write.csv(as.data.frame(sen_res), "sensitivity_analysis_results.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not write sensitivity results to CSV, saved as RDS instead.")
    })
    
    cat("Pipeline completed successfully. Outputs saved to 'sensitivity_analysis_results.rds', 'sensitivity_analysis_results.csv', and 'sensitivity_analysis_plot.pdf'.\n")

    writeLines(c(
        '"BIOC_ALDEX2_SENSITIVITY_ANALYSIS":',
        paste0('    ALDEx2: ', as.character(packageVersion('ALDEx2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sensitivity_analysis.csv versions.yml
    """
}

workflow BIOC_ALDEX2_SENSITIVITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, conds ] ]

    main:
    BIOC_ALDEX2_SENSITIVITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ALDEX2_SENSITIVITY_ANALYSIS.out.tables
    plots    = BIOC_ALDEX2_SENSITIVITY_ANALYSIS.out.plots
    objects  = BIOC_ALDEX2_SENSITIVITY_ANALYSIS.out.objects
    versions = BIOC_ALDEX2_SENSITIVITY_ANALYSIS.out.versions
}
