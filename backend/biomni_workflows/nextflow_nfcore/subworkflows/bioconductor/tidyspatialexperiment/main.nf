#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidySpatialExperiment
// tidySpatialExperiment provides a bridge between the SpatialExperiment package and the tidyverse ecos
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidySpatialExperiment/inst/doc/overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tidySpatialExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYSPATIALEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidyspatialexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidyspatialexperiment:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidyspatialexperiment:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidyspatialexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidyspatialexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidyspatialexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidySpatialExperiment)
    library(jsonlite)

    # --- Coldata [] ---
    # Key functions: colData, spatialCoords, imgData
    ---------------------------------------------------------------------
    spe |>
        colData() |>
        head()
    spe |>
    # --- Filter [] ---
    # Key functions: filter
    ---------------------------------------------------------------------
    spe |>
       filter(array_col < 5)
    # --- Mutate [] ---
    # Key functions: mutate
    ---------------------------------------------------------------------
    spe |>
        mutate(in_region = c(in_tissue & array_row < 10))
    # --- Nest [] ---
    # Key functions: nest, unnest
    ---------------------------------------------------------------------
    # Nest the SpatialExperiment object by sample_id
    spe_nested <-
        spe |>
        nest(data = -sample_id)
    # --- Filter [] ---
    # Key functions: filter, mutate, map_int, counts, ggplot, aes, reorder
    ---------------------------------------------------------------------
    spe |>
        filter(sample_id == "section1" & in_tissue) |>
        # Add a column with the sum of feature counts per cell
        mutate(count_sum = purrr::map_int(.cell, ~
    # --- Join Features [] ---
    # Key functions: join_features
    ---------------------------------------------------------------------
    # Join feature data in wide format, preserving the SpatialExperiment object
    spe |>
        join_features(features = c("ENSMUSG00000025915", "ENSMUSG00000042501"), shape = "wide") |>
        head()
    # --- Aggregate Cells [] ---
    # Key functions: aggregate_cells
    ---------------------------------------------------------------------
    spe |>
        aggregate_cells(in_tissue, assays = "counts")
    # --- Filter [] ---
    # Key functions: filter, mutate, ellipse, ggplot, aes, geom_point
    ---------------------------------------------------------------------
    spe |>
        filter(sample_id == "section1") |>
        mutate(in_ellipse = ellipse(array_col, array_row, c(20, 40), c(20, 20))) |>
        ggplot(aes(x = array_col, y = array_row, colour = in_ellipse)) +
    # --- Filter [] ---
    # Key functions: filter, na, str_detect
    ---------------------------------------------------------------------
    # Select cells within any gate
    spe_gated |>
      filter(!is.na(.gated))
    # Select cells within gate 2
    # --- Select [] ---
    # Key functions: select
    ---------------------------------------------------------------------
    spe |>
        select(-.cell) |>
        head()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidyspatialexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidyspatialexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidyspatialexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYSPATIALEXPERIMENT:", paste0("    tidyspatialexperiment: ", packageVersion("tidySpatialExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidyspatialexperiment_results.csv
    touch ${prefix}_tidyspatialexperiment_output.rds
    echo "BIOC_TIDYSPATIALEXPERIMENT:" > versions.yml
    echo "    tidyspatialexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYSPATIALEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYSPATIALEXPERIMENT(ch_input)

    emit:
    results  = BIOC_TIDYSPATIALEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYSPATIALEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYSPATIALEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYSPATIALEXPERIMENT.out.versions  // channel: path(versions.yml)
}
