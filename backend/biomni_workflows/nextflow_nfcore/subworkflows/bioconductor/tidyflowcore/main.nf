#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidyFlowCore
// tidyFlowCore bridges the gap between flow cytometry analysis using the flowCore Bioconductor package
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidyFlowCore/inst/doc/tidyFlowCore.R
// Upstream  : RefManageR, flowCore, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("tidyFlowCore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYFLOWCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidyflowcore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidyflowcore:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidyflowcore:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidyflowcore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidyflowcore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidyflowcore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidyFlowCore)
    library(Bodenmiller_BCR_XL_flowSet)
    library(PrintBibliography)
    library(jsonlite)

    # --- Data Transformation [tidyFlowCore] ---
    # Key functions: mutate, across, ends_with
    bcr_flowset <- HDCytoData::Bodenmiller_BCR_XL_flowSet()
    transformed_flowset <- bcr_flowset |>
        dplyr::mutate(dplyr::across(
            -dplyr::ends_with("_id"),
            \(.x) asinh(.x / 5)
        ))

    # --- Cell Population Profiling [tidyFlowCore] ---
    # Key functions: count
    population_counts <- bcr_flowset |>
        dplyr::count(.tidyFlowCore_identifier, population_id)

    # --- Marker Expression Summarisation [tidyFlowCore] ---
    # Key functions: ungroup, group_by, summarize, select
    population_stats <- bcr_flowset |>
        dplyr::ungroup() |>
        dplyr::group_by(population_id) |>
        dplyr::summarize(
            mean_hladr = mean(`HLA-DR(Yb174)Dd`),
            mean_cd20 = mean(`CD20(Sm147)Dd`)
        ) |>
        dplyr::select(population_id, mean_hladr, mean_cd20)

    # --- Single-Cell Visualisation [tidyFlowCore] ---
    # Key functions: mutate, ungroup, across
    plot_data <- bcr_flowset |>
        dplyr::mutate(dplyr::across(
            -dplyr::ends_with("_id"),
            \(.x) asinh(.x / 5)
        )) |>
        dplyr::ungroup()

    p <- ggplot2::ggplot(
        plot_data,
        ggplot2::aes(x = `CD20(Sm147)Dd`, y = `CD4(Nd145)Dd`)
    ) +
        ggplot2::geom_point(size = 0.1, alpha = 0.1) +
        ggplot2::facet_wrap(ggplot2::vars(population_id)) +
        ggplot2::labs(x = "CD20 (arcsinh)", y = "CD4 (arcsinh)")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidyflowcore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidyflowcore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidyflowcore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYFLOWCORE:", paste0("    tidyflowcore: ", packageVersion("tidyFlowCore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidyflowcore_results.csv
    touch ${prefix}_tidyflowcore_output.rds
    echo "BIOC_TIDYFLOWCORE:" > versions.yml
    echo "    tidyflowcore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYFLOWCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYFLOWCORE(ch_input)

    emit:
    results  = BIOC_TIDYFLOWCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYFLOWCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYFLOWCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYFLOWCORE.out.versions  // channel: path(versions.yml)
}
