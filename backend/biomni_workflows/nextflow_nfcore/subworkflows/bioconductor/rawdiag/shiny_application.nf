#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rawDiag — shiny_application
// Build and launch an interactive Shiny application for exploring raw MS data.
// Input: directory_path
// Container: quay.io/biocontainers/bioconductor-rawdiag:1.6.0--r45hdfd78af_0
// R packages: rawDiag, shiny
// Bioconductor: 3.20 | R: 4.4
// Requires: rawDiag, shiny
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the Shiny application from the raw file directory
//  * 2. [Core Analysis] Launch the application in the browser

nextflow.enable.dsl = 2

process BIOC_RAWDIAG_SHINY_APPLICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("rawDiag", "shiny")
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
    library(rawDiag)
    library(shiny)
    
    # Define user input directory path
    directory_path <- "directory_path"
    
    # Ensure the directory exists
    if (!dir.exists(directory_path)) {
      stop(paste("Input directory '", directory_path, "' does not exist. Please create it and populate it with .raw files.", sep = ""))
    }
    
    # Locate .raw files in the directory
    raw_files <- list.files(directory_path, pattern = "\\\\.raw\$", full.names = TRUE)
    
    if (length(raw_files) == 0) {
      stop(paste("No .raw files found in '", directory_path, "'. Please add at least one .raw file.", sep = ""))
    }
    
    # Select the first raw file to determine the directory path via dirname() as in the documented workflow
    rawfile <- raw_files[1]
    
    # 1. Build the Shiny application from the raw file directory
    rawfile |>
      dirname() |>
      rawDiag::buildRawDiagShinyApp() -> app
    
    # Save the built Shiny app object as a meaningful output
    saveRDS(app, file = "rawDiag_shiny_app.rds")
    
    # 2. Launch the application in the browser
    shiny::runApp(app)

    writeLines(c(
        '"BIOC_RAWDIAG_SHINY_APPLICATION":',
        paste0('    rawDiag: ', as.character(packageVersion('rawDiag')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shiny_application.csv versions.yml
    """
}

workflow BIOC_RAWDIAG_SHINY_APPLICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory_path ] ]

    main:
    BIOC_RAWDIAG_SHINY_APPLICATION(ch_input)

    emit:
    tables   = BIOC_RAWDIAG_SHINY_APPLICATION.out.tables
    plots    = BIOC_RAWDIAG_SHINY_APPLICATION.out.plots
    objects  = BIOC_RAWDIAG_SHINY_APPLICATION.out.objects
    versions = BIOC_RAWDIAG_SHINY_APPLICATION.out.versions
}
