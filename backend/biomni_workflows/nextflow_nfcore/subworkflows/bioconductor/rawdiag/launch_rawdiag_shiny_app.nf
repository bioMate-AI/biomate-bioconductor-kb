#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rawdiag — launch_rawdiag_shiny_app
// Build and launch the interactive Shiny application for exploring Thermo Orbitrap raw data.
// Input: directory_path
// Container: quay.io/biocontainers/bioconductor-rawdiag:1.6.0--r45hdfd78af_0
// R packages: rawDiag, shiny
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rawdiag:1.6.0--r45hdfd78af_0"

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
    
    # USER INPUT — Path to a directory containing Thermo Orbitrap .raw files
    directory_path <- "."
    
    # Identify Thermo Orbitrap .raw files (must be case-sensitive '.raw')
    rawfile <- list.files(path = directory_path, pattern = "\\\\.raw\$", full.names = TRUE)
    
    # Check if raw files exist
    if (length(rawfile) == 0) {
      stop("Error: No '.raw' files found in '", directory_path, "'. Please place Thermo Orbitrap .raw files in this directory.")
    }
    
    # Ensure rawrr assembly is installed and working
    tryCatch({
      if (requireNamespace("rawrr", quietly = TRUE)) {
        if (!file.exists(rawrr:::.rawrrAssembly())) {
          rawrr::installRawrrExe()
        }
      }
    }, error = function(e) {
      warning("Failed to initialize rawrr assembly: ", e\$message)
    })
    
    # --- Build the Shiny application from the raw files directory ---
    rawfile |>
      dirname() |>
      rawDiag::buildRawDiagShinyApp() -> app
    
    # Save the built Shiny app object as an RDS file
    saveRDS(app, file = "rawdiag_shiny_app.rds")
    
    # --- Launch the application ---
    shiny::runApp(app)

    writeLines(c(
        '"BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP":',
        paste0('        rawdiag: ', as.character(packageVersion("rawdiag")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_launch_rawdiag_shiny_app.csv versions.yml
    """
}

workflow BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory_path ] ]

    main:
    BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP(ch_input)

    emit:
    tables   = BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP.out.tables
    plots    = BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP.out.plots
    objects  = BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP.out.objects
    versions = BIOC_RAWDIAG_LAUNCH_RAWDIAG_SHINY_APP.out.versions
}
