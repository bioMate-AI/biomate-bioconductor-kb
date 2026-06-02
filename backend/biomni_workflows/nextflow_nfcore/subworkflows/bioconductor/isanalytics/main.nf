#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ISAnalytics
// In gene therapy, stem cells are modified using viral vectors to deliver the therapeutic transgene an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ISAnalytics/inst/doc/ISAnalytics.R
// Upstream  : BiocStyle, DT, RefManageR, devtools, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("ISAnalytics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISANALYTICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isanalytics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isanalytics:1.16.1--r44_0' :
        'quay.io/biocontainers/bioconductor-isanalytics:1.16.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isanalytics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isanalytics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isanalytics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ISAnalytics)
    library(PrintBibliography)
    library(jsonlite)

    # --- Data Import [] ---
    # Key functions: import_association_file, import_single_Vispa2Matrix
    data_folder <- tempdir()
    utils::unzip(
        zipfile = system.file("testdata", "testdata.zip",
                              package = "ISAnalytics"),
        exdir = data_folder, overwrite = TRUE
    )
    af <- import_association_file(
        fs::path(data_folder, "barcodes_example_af.tsv.xz"),
        report_path = NULL
    )
    matrix <- import_single_Vispa2Matrix(
        fs::path(data_folder, "GSE144340_Matrix_542.tsv.xz"),
        sample_names_to = "ID"
    )


    # --- Descriptive Statistics [] ---
    # Key functions: sample_statistics, pcr_id_column
    desc_stats <- sample_statistics(
        matrix,
        af,
        sample_key = pcr_id_column(),
        value_columns = "Value"
    )$metadata


    # --- Clonal Aggregation [] ---
    # Key functions: aggregate_values_by_key, aggregate_metadata, pcr_id_column
    agg_key <- c("SubjectID")
    agg <- aggregate_values_by_key(
        matrix, af,
        key = agg_key,
        group = "BarcodeSeq",
        join_af_by = pcr_id_column()
    )
    agg_meta_functions <- tibble::tribble(
        ~Column, ~Function, ~Args, ~Output_colname,
        "ID", ~ length(unique(.x)), NA, "distinct_id_count"
    )
    agg_meta <- aggregate_metadata(
        af,
        aggregating_functions = agg_meta_functions,
        grouping_keys = agg_key
    )


    # --- Abundance Calculation [] ---
    # Key functions: compute_abundance, reset_dyn_vars_config
    agg_key <- c("SubjectID")
    abundance <- compute_abundance(
        agg,
        columns = "Value_sum",
        key = agg_key
    )
    reset_dyn_vars_config()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isanalytics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isanalytics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isanalytics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISANALYTICS:", paste0("    isanalytics: ", packageVersion("ISAnalytics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isanalytics_results.csv
    touch ${prefix}_isanalytics_output.rds
    echo "BIOC_ISANALYTICS:" > versions.yml
    echo "    isanalytics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISANALYTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISANALYTICS(ch_input)

    emit:
    results  = BIOC_ISANALYTICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISANALYTICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISANALYTICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISANALYTICS.out.versions  // channel: path(versions.yml)
}
