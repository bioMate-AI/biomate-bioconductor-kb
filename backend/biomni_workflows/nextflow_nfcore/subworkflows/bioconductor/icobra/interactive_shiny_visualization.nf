#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCOBRA — interactive_shiny_visualization
// Launch the interactive Shiny application to explore performance metrics.
// Input: A COBRAData object or text files containing truth and results.
// Container: quay.io/biocontainers/bioconductor-icobra:1.38.0--r45hdfd78af_0
// R packages: iCOBRA
// Bioconductor: 3.20 | R: 4.4
// Requires: iCOBRA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read user input files from the working directory
//  * 2. [Core Analysis] Launch the interactive Shiny application to explore

nextflow.enable.dsl = 2

process BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("iCOBRA")
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
        
        # Load required libraries
        library(iCOBRA)
        
        # --- Read user input files from the working directory ---
        # The pipeline expects either a serialized COBRAData object ('cobradata.rds')
        # or text files ('cobradata_truth.txt' and 'cobradata_results.txt').
        
        if (file.exists("cobradata.rds")) {
          cobradata_example <- readRDS("cobradata.rds")
        } else if (file.exists("cobradata_truth.txt") && file.exists("cobradata_results.txt")) {
          cobradata_example <- COBRAData_from_text(
            truth_file = "cobradata_truth.txt",
            result_files = "cobradata_results.txt",
            feature_id = "feature"
          )
        } else {
          stop("Error: Input files not found. Please provide 'cobradata.rds' or both 'cobradata_truth.txt' and 'cobradata_results.txt' in the working directory.")
        }
        
        # Save the loaded COBRAData object to verify successful loading and parsing
        saveRDS(cobradata_example, "processed_cobradata.rds")
        
        # --- Launch the interactive Shiny application to explore ---
        # (Documented calls reproduced exactly)
        COBRAapp(cobradata_example)

    writeLines(c(
        '"BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION":',
        paste0('    iCOBRA: ', as.character(packageVersion('iCOBRA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_shiny_visualization.csv versions.yml
    """
}

workflow BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A COBRAData object or text files containing truth and results. ] ]

    main:
    BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION.out.tables
    plots    = BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION.out.plots
    objects  = BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION.out.objects
    versions = BIOC_ICOBRA_INTERACTIVE_SHINY_VISUALIZATION.out.versions
}
