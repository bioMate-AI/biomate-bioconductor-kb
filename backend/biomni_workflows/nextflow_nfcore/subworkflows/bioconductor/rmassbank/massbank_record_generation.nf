#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmassbank — massbank_record_generation
// Retrieve compound annotations, compile spectral data, and export standardized MassBank records.
// Input: processed_workspace.RData, infolists_incomplete, Narcotics_infolist.csv
// Container: quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0
// R packages: RMassBank
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("RMassBank")
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
    library(RMassBank)
    
    # Initialize default settings to ensure RMassBank is configured
    RmbDefaultSettings()
    
    # Load the user-provided processed MS/MS workspace object
    # This RData file must contain the workspace object 'w'
    load("processed_workspace.RData")
    
    # --- Initialize a MassBank workspace from the processed MS/MS ---
    mb <- newMbWorkspace(w)
    
    # --- Load existing incomplete infolists from the user-provided ---
    mb <- resetInfolists(mb)
    mb <- loadInfolists(mb, "infolists_incomplete")
    
    # --- Run mbWorkflow to fetch missing annotations from online ---
    # and write them to the specified CSV file.
    # Wrapped in a tryCatch to handle potential network/CTS service downtime gracefully.
    tryCatch({
      mb <- mbWorkflow(mb, infolist_path="./Narcotics_infolist.csv")
    }, error = function(e) {
      warning("First mbWorkflow call encountered an issue (e.g., CTS offline): ", e\$message)
    })
    
    # --- Handle the completed CSV infolist ---
    # To reload the completed 'Narcotics_infolist.csv' using loadInfolists,
    # we place it into a dedicated directory.
    completed_dir <- "./infolists_completed"
    if (!dir.exists(completed_dir)) {
      dir.create(completed_dir, recursive = TRUE)
    }
    
    if (file.exists("./Narcotics_infolist.csv")) {
      file.copy("./Narcotics_infolist.csv", file.path(completed_dir, "Narcotics_infolist.csv"), overwrite = TRUE)
    } else {
      stop("Expected './Narcotics_infolist.csv' to exist but it was not found.")
    }
    
    # --- Reload the completed infolists and re-run mbWorkflow to ---
    # generate molfiles, and export MassBank record text files.
    mb <- resetInfolists(mb)
    mb <- loadInfolists(mb, completed_dir)
    mb <- mbWorkflow(mb)
    
    # Save the final compiled MassBank workspace object
    saveRDS(mb, "final_mb_workspace.rds")

    writeLines(c(
        '"BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION":',
        paste0('        rmassbank: ', as.character(packageVersion("rmassbank")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_massbank_record_generation.csv versions.yml
    """
}

workflow BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ processed_workspace.RData, infolists_incomplete, Narcotics_infolist.csv ] ]

    main:
    BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION(ch_input)

    emit:
    tables   = BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION.out.tables
    plots    = BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION.out.plots
    objects  = BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION.out.objects
    versions = BIOC_RMASSBANK_MASSBANK_RECORD_GENERATION.out.versions
}
