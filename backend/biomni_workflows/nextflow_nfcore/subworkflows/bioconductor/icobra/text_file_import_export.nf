#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCOBRA — text_file_import_export
// Convert between COBRAData objects and text files for external storage or app compatibility.
// Input: A COBRAData object or text files containing truth and results.
// Container: quay.io/biocontainers/bioconductor-icobra:1.38.0--r45hdfd78af_0
// R packages: iCOBRA
// Bioconductor: 3.20 | R: 4.4
// Requires: iCOBRA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Export COBRAData to text files using COBRAData_to_text
//  * 2. [Input & Preparation] Import text files back into a COBRAData object using COBRAData_from_text

nextflow.enable.dsl = 2

process BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT {
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
    .bm_deps <- c("iCOBRA")
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
    library(iCOBRA)
    
    # Read user input files from the working directory
    if (file.exists("input_cobradata.rds")) {
      cobradata_input <- readRDS("input_cobradata.rds")
    } else if (file.exists("input_truth.txt") && file.exists("input_results.txt")) {
      cobradata_input <- COBRAData_from_text(truth_file = "input_truth.txt",
                                             result_files = "input_results.txt",
                                             feature_id = "feature")
    } else {
      stop("Required input files ('input_cobradata.rds' or 'input_truth.txt' and 'input_results.txt') not found in the working directory.")
    }
    
    # Stage 1: Export COBRAData to text files using COBRAData_to_text
    COBRAData_to_text(cobradata = cobradata_input, 
                      truth_file = "cobradata_truth.txt",
                      result_files = "cobradata_results.txt", 
                      feature_id = "feature")
    
    # Stage 2: Import text files back into a COBRAData object using COBRAData_from_text
    cobra <- COBRAData_from_text(truth_file = "cobradata_truth.txt", 
                                 result_files = "cobradata_results.txt", 
                                 feature_id = "feature")
    
    # Save the final imported COBRAData object
    saveRDS(cobra, file = "output_cobra.rds")

    writeLines(c(
        '"BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT":',
        paste0('    iCOBRA: ', as.character(packageVersion('iCOBRA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_text_file_import_export.csv versions.yml
    """
}

workflow BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A COBRAData object or text files containing truth and results. ] ]

    main:
    BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT(ch_input)

    emit:
    tables   = BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT.out.tables
    plots    = BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT.out.plots
    objects  = BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT.out.objects
    versions = BIOC_ICOBRA_TEXT_FILE_IMPORT_EXPORT.out.versions
}
