#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scFeatures — association_study_report
// Generate an HTML report visualizing the association of generated features with conditions.
// Input: scfeatures_result.rds
// Container: quay.io/biocontainers/bioconductor-scfeatures:1.6.0--r44hdfd78af_0
// R packages: scFeatures
// Bioconductor: 3.20 | R: 4.4
// Requires: scFeatures
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the generated scFeatures list
//  * 2. [Visualization & Output] Define the output directory
//  * 3. [Visualization & Output] Generate the HTML association study report using run_association_study_report

nextflow.enable.dsl = 2

process BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("scFeatures")
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
    library(scFeatures)
    
    # 1. Load the generated scFeatures list from the user input file
    input_file <- "scfeatures_result.rds"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    scfeatures_result <- readRDS(input_file)
    
    # 2. Define the output directory
    output_folder <- tempdir()
    
    # 3. Generate the HTML association study report using run_association_study_report
    # This call is preserved exactly as documented
    run_association_study_report(scfeatures_result, output_folder )
    
    # 4. Copy the generated HTML report to the working directory as a named output file
    generated_report <- file.path(output_folder, "output_report.html")
    output_report_name <- "association_study_report.html"
    
    if (file.exists(generated_report)) {
      file.copy(generated_report, output_report_name, overwrite = TRUE)
      message(paste("Successfully generated and saved report to:", output_report_name))
    } else {
      warning("Expected HTML report was not found in the temporary output folder.")
    }

    writeLines(c(
        '"BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT":',
        paste0('    scFeatures: ', as.character(packageVersion('scFeatures')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_association_study_report.csv versions.yml
    """
}

workflow BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scfeatures_result.rds ] ]

    main:
    BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT(ch_input)

    emit:
    tables   = BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT.out.tables
    plots    = BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT.out.plots
    objects  = BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT.out.objects
    versions = BIOC_SCFEATURES_ASSOCIATION_STUDY_REPORT.out.versions
}
