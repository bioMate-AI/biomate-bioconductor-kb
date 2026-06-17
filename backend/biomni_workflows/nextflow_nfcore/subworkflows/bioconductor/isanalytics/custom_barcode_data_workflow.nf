#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ISAnalytics — custom_barcode_data_workflow
// Configure the dynamic variables system to import, pre-process, and analyze non-standard integration or barcode matrices.
// Input: barcodes_metadata.tsv, barcodes_matrix.tsv.xz
// Container: quay.io/biocontainers/bioconductor-isanalytics:1.20.1--r45hdfd78af_0
// R packages: ISAnalytics, dplyr, fs, readr, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: ISAnalytics, dplyr, fs, readr, tibble
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define custom metadata specifications and apply them using set_af_columns_def()
//  * 2. [Input & Preparation] Define custom mandatory integration variables and apply them using set_mandatory_IS_vars()
//  * 3. [Input & Preparation] Import the custom association file using import_association_file()
//  * 4. [Input & Preparation] Import the custom matrix using import_single_Vispa2Matrix()
//  * 5. [Core Analysis] Compute descriptive statistics using sample_statistics()
//  * 6. [Core Analysis] Aggregate values by key using aggregate_values_by_key()
//  * 7. [Core Analysis] Aggregate metadata using aggregate_metadata()
//  * 8. [Core Analysis] Compute relative and percentage abundance using compute_abundance()
//  * 9. [Core Analysis] Reset the dynamic variables configuration to defaults using reset_dyn_vars_config()

nextflow.enable.dsl = 2

process BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW {
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
    .bm_deps <- c("ISAnalytics", "dplyr", "fs", "readr", "tibble")
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
    library(ISAnalytics)
    library(tibble)
    library(dplyr)
    library(fs)
    library(readr)
    
    # Define input files from the working directory
    data_folder <- "."
    meta_file <- "barcodes_metadata.tsv"
    matrix_file <- "barcodes_matrix.tsv.xz"
    
    # 1. Define custom metadata specifications and apply them
    metadata_specs <- tibble::tribble(
        ~names, ~types, ~transform, ~flag, ~tag,
        "ProjectID", "char", NULL, "required", "project_id",
        "SubjectID", "char", NULL, "required", "subject",
        "Tissue", "char", NULL, "required", "tissue",
        "TimePoint", "int", NULL, "required", "tp_days",
        "CellMarker", "char", NULL, "required", "cell_marker",
        "ID", "char", NULL, "required", "pcr_repl_id",
        "SourceFileName", "char", NULL, "optional", NA_character_,
        "Link", "char", NULL, "optional", NA_character_
    )
    set_af_columns_def(metadata_specs)
    
    # 2. Define custom mandatory integration variables and apply them
    mandatory_specs <- tibble::tribble(
        ~names, ~types, ~transform, ~flag, ~tag,
        "BarcodeSeq", "char", NULL, "required", NA_character_
    )
    set_mandatory_IS_vars(mandatory_specs)
    
    # 3. Import the custom association file
    af <- import_association_file(fs::path(data_folder, meta_file),
        report_path = NULL
    )
    
    # 4. Import the custom matrix
    matrix <- import_single_Vispa2Matrix(fs::path(data_folder, matrix_file),
        sample_names_to = "ID"
    )
    
    # 5. Compute descriptive statistics
    desc_stats <- sample_statistics(matrix, af,
        sample_key = pcr_id_column(),
        value_columns = "Value"
    )\$metadata |>
        dplyr::rename(distinct_barcodes = "nIS")
    
    # 6. Aggregate values by key
    agg_key <- c("SubjectID")
    agg <- aggregate_values_by_key(matrix, af,
        key = agg_key,
        group = "BarcodeSeq",
        join_af_by = pcr_id_column()
    )
    
    # 7. Aggregate metadata
    agg_meta_functions <- tibble::tribble(
        ~Column, ~Function, ~Args, ~Output_colname,
        "TimePoint", ~ mean(.x, na.rm = TRUE), NA, "{.col}_avg",
        "CellMarker", ~ length(unique(.x)), NA, "distinct_cell_marker_count",
        "ID", ~ length(unique(.x)), NA, "distinct_id_count"
    )
    agg_meta <- aggregate_metadata(
        af,
        aggregating_functions = agg_meta_functions,
        grouping_keys = agg_key
    )
    
    # 8. Compute relative and percentage abundance
    abundance <- compute_abundance(agg, columns = "Value_sum", key = agg_key)
    
    # 9. Reset the dynamic variables configuration to defaults
    reset_dyn_vars_config()
    
    # Write meaningful results to output files
    readr::write_csv(desc_stats, "descriptive_statistics.csv")
    readr::write_csv(agg, "aggregated_values.csv")
    readr::write_csv(agg_meta, "aggregated_metadata.csv")
    readr::write_csv(abundance, "abundance_results.csv")
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW":',
        paste0('    ISAnalytics: ', as.character(packageVersion('ISAnalytics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_barcode_data_workflow.csv versions.yml
    """
}

workflow BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ barcodes_metadata.tsv, barcodes_matrix.tsv.xz ] ]

    main:
    BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW.out.tables
    plots    = BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW.out.plots
    objects  = BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW.out.objects
    versions = BIOC_ISANALYTICS_CUSTOM_BARCODE_DATA_WORKFLOW.out.versions
}
