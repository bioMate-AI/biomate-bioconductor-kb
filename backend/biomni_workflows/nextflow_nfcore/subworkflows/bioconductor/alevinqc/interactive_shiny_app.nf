#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alevinqc — interactive_shiny_app
// Launch an interactive Shiny application for visual quality control and optionally export the underlying data.
// Input: baseDir
// Container: quay.io/biocontainers/bioconductor-alevinqc:1.26.0--r45ha27e39d_0
// R packages: alevinQC, shiny
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALEVINQC_INTERACTIVE_SHINY_APP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-alevinqc:1.26.0--r45ha27e39d_0"

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
    .bm_deps <- c("alevinQC", "shiny")
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
    library(alevinQC)
    library(shiny)
    
    # Define user input directory (must exist in the working directory)
    baseDir <- "baseDir"
    
    # Verify input directory exists
    if (!dir.exists(baseDir)) {
      stop(paste("Expected input directory 'baseDir' does not exist in the current working directory:", getwd()))
    }
    
    # Check that all required alevin files are available
    checkAlevinInputFiles(baseDir = baseDir)
    
    # --- Create the Shiny app object using alevinQCShiny() ---
    app <- alevinQCShiny(baseDir = baseDir, sampleId = "testSample")
    
    # Save the Shiny app object to disk as a meaningful pipeline output
    saveRDS(app, "alevin_shiny_app.rds")
    
    # --- Run the app using shiny::runApp() and capture the output ---
    if (interactive()) {
        out <- shiny::runApp(app)
        if (exists("out") && !is.null(out)) {
            saveRDS(out, "shiny_exported_data.rds")
        }
    }
    
    # Export the underlying data directly to ensure meaningful outputs are written
    # regardless of whether the session is interactive or non-interactive
    alevin_data <- readAlevinQC(baseDir = baseDir)
    saveRDS(alevin_data, "alevin_qc_data.rds")
    
    if (!is.null(alevin_data\$cbTable)) {
        write.csv(alevin_data\$cbTable, "cbTable.csv", row.names = FALSE)
    }
    
    if (!is.null(alevin_data\$summaryTables\$fullDataset)) {
        write.csv(alevin_data\$summaryTables\$fullDataset, "summaryTable_fullDataset.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_ALEVINQC_INTERACTIVE_SHINY_APP":',
        paste0('        alevinqc: ', as.character(packageVersion("alevinqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_shiny_app.csv versions.yml
    """
}

workflow BIOC_ALEVINQC_INTERACTIVE_SHINY_APP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baseDir ] ]

    main:
    BIOC_ALEVINQC_INTERACTIVE_SHINY_APP(ch_input)

    emit:
    tables   = BIOC_ALEVINQC_INTERACTIVE_SHINY_APP.out.tables
    plots    = BIOC_ALEVINQC_INTERACTIVE_SHINY_APP.out.plots
    objects  = BIOC_ALEVINQC_INTERACTIVE_SHINY_APP.out.objects
    versions = BIOC_ALEVINQC_INTERACTIVE_SHINY_APP.out.versions
}
