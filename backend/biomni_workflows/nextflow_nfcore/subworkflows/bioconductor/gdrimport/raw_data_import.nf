#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gDRimport — raw_data_import
// Load and merge raw drug response files (manifest, templates, and results) into a unified gDR-compatible list structure.
// Input: manifest.xlsx, template.xlsx, results.csv
// Container: quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0
// R packages: gDRimport
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDRIMPORT_RAW_DATA_IMPORT {
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
    
    # Define helper functions to map the documented code arguments to the exact user input files
    manifest_path <- function(x) "manifest.xlsx"
    template_path <- function(x) "template.xlsx"
    result_path <- function(x) "results.csv"
    td1 <- "working_directory"
    
    # 1. Load the manifest file using load_manifest
    ml <- load_manifest(manifest_path(td1))
    
    # 2. Load the template files using load_templates
    t_df <- load_templates(template_path(td1))
    
    # 3. Load the raw results using load_results
    r_df <- suppressMessages(load_results(result_path(td1)))
    
    # 4. Load and merge all three components together using load_data
    l_tbl <- suppressMessages(load_data(manifest_path(td1), template_path(td1), result_path(td1)))
    
    # Save the meaningful results to output files
    saveRDS(ml, "manifest_loaded.rds")
    saveRDS(t_df, "templates_loaded.rds")
    saveRDS(r_df, "results_loaded.rds")
    saveRDS(l_tbl, "merged_data.rds")
    
    # Also export the merged data as a CSV for easy inspection
    if (inherits(l_tbl, "data.frame") || inherits(l_tbl, "data.table")) {
      write.csv(l_tbl, "merged_data.csv", row.names = FALSE)
    } else if (is.list(l_tbl)) {
      # If l_tbl is a list of data.tables/data.frames, save each or the main one
      for (name in names(l_tbl)) {
        tryCatch({
          write.csv(l_tbl[[name]], paste0("merged_data_", name, ".csv"), row.names = FALSE)
        }, error = function(e) {
          # Ignore if not exportable to CSV directly
        })
      }
    }

    writeLines(c(
        '"BIOC_GDRIMPORT_RAW_DATA_IMPORT":',
        paste0('        gDRimport: ', as.character(packageVersion("gDRimport")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raw_data_import.csv versions.yml
    """
}

workflow BIOC_GDRIMPORT_RAW_DATA_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ manifest.xlsx, template.xlsx, results.csv ] ]

    main:
    BIOC_GDRIMPORT_RAW_DATA_IMPORT(ch_input)

    emit:
    tables   = BIOC_GDRIMPORT_RAW_DATA_IMPORT.out.tables
    plots    = BIOC_GDRIMPORT_RAW_DATA_IMPORT.out.plots
    objects  = BIOC_GDRIMPORT_RAW_DATA_IMPORT.out.objects
    versions = BIOC_GDRIMPORT_RAW_DATA_IMPORT.out.versions
}
