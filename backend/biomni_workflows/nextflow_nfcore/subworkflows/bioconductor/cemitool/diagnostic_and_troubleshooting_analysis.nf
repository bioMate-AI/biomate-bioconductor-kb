#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CEMiTool — diagnostic_and_troubleshooting_analysis
// Generate a diagnostic report to troubleshoot data issues, assess sample heterogeneity, mean-variance relationships, and distribution properties.
// Input: expression_data.csv
// Container: quay.io/biocontainers/bioconductor-cemitool:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CEMiTool
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load expression data
//  * 2. [Visualization & Output] Run cemitool to create a CEMiTool object
//  * 3. [Visualization & Output] Generate a diagnostic report

nextflow.enable.dsl = 2

process BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS {
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
    .bm_deps <- c("CEMiTool")
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
    
    # Load required library
    library("CEMiTool")
    
    # --- Load expression data ---
    # The pipeline reads the user-provided 'expression_data.csv' file.
    # This file must contain gene symbols in rows (first column) and samples in columns.
    if (!file.exists("expression_data.csv")) {
      stop("Error: 'expression_data.csv' not found in the working directory.")
    }
    
    expr0 <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
    
    # Convert to matrix and then data.frame to ensure proper formatting
    expr0 <- as.data.frame(as.matrix(expr0))
    
    # --- Run cemitool to create a CEMiTool object ---
    cem <- cemitool(expr0)
    
    # --- Generate a diagnostic report ---
    # This generates an HTML report to visualize sample clustering, mean-variance relationship,
    # Q-Q plot, and beta selection.
    diagnostic_report(cem)
    
    # Save the CEMiTool object as an RDS file for downstream analysis or troubleshooting
    saveRDS(cem, file = "cemitool_diagnostic_results.rds")

    writeLines(c(
        '"BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS":',
        paste0('    CEMiTool: ', as.character(packageVersion('CEMiTool')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diagnostic_and_troubleshooting_analysis.csv versions.yml
    """
}

workflow BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv ] ]

    main:
    BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS.out.tables
    plots    = BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS.out.plots
    objects  = BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS.out.objects
    versions = BIOC_CEMITOOL_DIAGNOSTIC_AND_TROUBLESHOOTING_ANALYSIS.out.versions
}
