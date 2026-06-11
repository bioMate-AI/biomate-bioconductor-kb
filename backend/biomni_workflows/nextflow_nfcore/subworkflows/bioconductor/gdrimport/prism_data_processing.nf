#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gDRimport — prism_data_processing
// Process LEVEL5 or LEVEL6 PRISM multiplexed cancer cell line screening data and convert it to gDR input.
// Input: prism_level5.csv, prism_level6_data.csv, cell_line_metadata.csv, treatment_metadata.csv
// Container: quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0
// R packages: gDRimport
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDRIMPORT_PRISM_DATA_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0"

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
    .bm_deps <- c("gDRimport")
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
    library(gDRimport)
    
    # Define input file paths as specified by the user
    prism_level5_path <- "prism_level5.csv"
    prism_level6_path <- "prism_level6_data.csv"
    cell_line_metadata_path <- "cell_line_metadata.csv"
    treatment_metadata_path <- "treatment_metadata.csv"
    
    # Verify that the required input files exist before processing
    if (!file.exists(prism_level5_path)) {
      stop(paste("Required input file missing:", prism_level5_path))
    }
    if (!file.exists(prism_level6_path)) {
      stop(paste("Required input file missing:", prism_level6_path))
    }
    if (!file.exists(cell_line_metadata_path)) {
      stop(paste("Required input file missing:", cell_line_metadata_path))
    }
    if (!file.exists(treatment_metadata_path)) {
      stop(paste("Required input file missing:", treatment_metadata_path))
    }
    
    # Stage 1: Process LEVEL5 PRISM data
    # Using convert_LEVEL5_prism_to_gDR_input with the single LEVEL5 PRISM data file
    message("Processing LEVEL5 PRISM data...")
    level5_gdr_input <- convert_LEVEL5_prism_to_gDR_input(prism_level5_path)
    
    # Save LEVEL5 processed output
    write.csv(level5_gdr_input, "gdr_input_level5.csv", row.names = FALSE)
    saveRDS(level5_gdr_input, "gdr_input_level5.rds")
    message("LEVEL5 PRISM data successfully converted and saved.")
    
    # Stage 2: Process LEVEL6 PRISM data
    # Using convert_LEVEL6_prism_to_gDR_input with collapsed log fold change viability data,
    # cell line metadata, and treatment metadata files
    message("Processing LEVEL6 PRISM data...")
    level6_gdr_input <- convert_LEVEL6_prism_to_gDR_input(
      prism_level6_path,
      cell_line_metadata_path,
      treatment_metadata_path
    )
    
    # Save LEVEL6 processed output
    write.csv(level6_gdr_input, "gdr_input_level6.csv", row.names = FALSE)
    saveRDS(level6_gdr_input, "gdr_input_level6.rds")
    message("LEVEL6 PRISM data successfully converted and saved.")

    writeLines(c(
        '"BIOC_GDRIMPORT_PRISM_DATA_PROCESSING":',
        paste0('        gDRimport: ', as.character(packageVersion("gDRimport")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prism_data_processing.csv versions.yml
    """
}

workflow BIOC_GDRIMPORT_PRISM_DATA_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ prism_level5.csv, prism_level6_data.csv, cell_line_metadata.csv, treatment_metadata.csv ] ]

    main:
    BIOC_GDRIMPORT_PRISM_DATA_PROCESSING(ch_input)

    emit:
    tables   = BIOC_GDRIMPORT_PRISM_DATA_PROCESSING.out.tables
    plots    = BIOC_GDRIMPORT_PRISM_DATA_PROCESSING.out.plots
    objects  = BIOC_GDRIMPORT_PRISM_DATA_PROCESSING.out.objects
    versions = BIOC_GDRIMPORT_PRISM_DATA_PROCESSING.out.versions
}
