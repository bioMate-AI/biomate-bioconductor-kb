#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CuratedAtlasQueryR
// Provides access to a copy of the Human Cell Atlas, but with harmonised metadata. This allows for uni
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CuratedAtlasQueryR/inst/doc/Introduction.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("CuratedAtlasQueryR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CURATEDATLASQUERYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-curatedatlasqueryr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-curatedatlasqueryr:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-curatedatlasqueryr:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_curatedatlasqueryr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_curatedatlasqueryr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_curatedatlasqueryr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CuratedAtlasQueryR)
    library(jsonlite)

    # --- Get Metadata [] ---
    # Key functions: get_metadata
    ---------------------------------------------------------------------
    # Note: in real applications you should use the default value of remote_url
    metadata <- get_metadata(remote_url = METADATA_URL)
    metadata
    # --- Distinct [] ---
    # Key functions: distinct
    ---------------------------------------------------------------------
    metadata |>
        dplyr::distinct(tissue, file_id)
    # --- Filter [] ---
    # Key functions: filter, str_like, get_single_cell_experiment
    ---------------------------------------------------------------------
    single_cell_counts =
        metadata |>
        dplyr::filter(
            ethnicity == "African" &
    # --- Filter [] ---
    # Key functions: filter, str_like, get_seurat
    ---------------------------------------------------------------------
    single_cell_counts_seurat =
        metadata |>
        dplyr::filter(
            ethnicity == "African" &
    # --- save H D F5 Summarized Experiment [] ---
    # Key functions: saveHDF5SummarizedExperiment
    ---------------------------------------------------------------------
    single_cell_counts |> HDF5Array::saveHDF5SummarizedExperiment("single_cell_counts", replace = TRUE)
    # --- Filter [] ---
    # Key functions: filter, get_single_cell_experiment, join_features, ggplot, aes, theme_bw, theme
    ---------------------------------------------------------------------
    metadata |>
      # Filter and subset
      dplyr::filter(cell_type_harmonised=="nk") |>
      # Get counts per million for HCA-A gene
    # --- Filter [] ---
    # Key functions: filter, get_unharmonised_metadata
    ---------------------------------------------------------------------
    harmonised <- metadata |> dplyr::filter(tissue == "kidney blood vessel")
    unharmonised <- get_unharmonised_metadata(harmonised)
    unharmonised
    # --- Pull [] ---
    # Key functions: pull
    ---------------------------------------------------------------------
    dplyr::pull(unharmonised) |> head(2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_curatedatlasqueryr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_curatedatlasqueryr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_curatedatlasqueryr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CURATEDATLASQUERYR:", paste0("    curatedatlasqueryr: ", packageVersion("CuratedAtlasQueryR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_curatedatlasqueryr_results.csv
    touch ${prefix}_curatedatlasqueryr_output.rds
    echo "BIOC_CURATEDATLASQUERYR:" > versions.yml
    echo "    curatedatlasqueryr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CURATEDATLASQUERYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CURATEDATLASQUERYR(ch_input)

    emit:
    results  = BIOC_CURATEDATLASQUERYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CURATEDATLASQUERYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CURATEDATLASQUERYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CURATEDATLASQUERYR.out.versions  // channel: path(versions.yml)
}
