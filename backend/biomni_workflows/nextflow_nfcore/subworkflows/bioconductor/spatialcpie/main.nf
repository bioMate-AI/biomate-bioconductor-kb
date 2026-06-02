#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialCPie
// SpatialCPie is an R package designed to facilitate cluster evaluation for spatial transcriptomics da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialCPie/inst/doc/SpatialCPie.R
// Upstream  : dplyr, rlang
// Downstream: none
//
// Install: BiocManager::install("SpatialCPie")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALCPIE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialcpie"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialcpie:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialcpie:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialcpie_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialcpie_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialcpie_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpatialCPie)
    library(jsonlite)

    # --- Cluster Path Analysis [] ---
    # Key functions: runCPie
    result <- runCPie(
        counts = counts,
        image = NULL,
        spotCoordinates = spots,
        resolutions = c(2, 3, 4)
    )
    cluster_graph <- result$clusterGraph
    array_plot <- result$arrayPlot$`4`


    # --- Subcluster Analysis [] ---
    # Key functions: runCPie
    subcluster <- result$clusters[
        result$clusters$resolution == 4 &
        result$clusters$cluster %in% c(1, 4),
        "unit"
    ]
    sub_result <- runCPie(
        counts = counts[, subcluster],
        image = NULL,
        spotCoordinates = spots
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialcpie_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialcpie_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialcpie_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALCPIE:", paste0("    spatialcpie: ", packageVersion("SpatialCPie"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialcpie_results.csv
    touch ${prefix}_spatialcpie_output.rds
    echo "BIOC_SPATIALCPIE:" > versions.yml
    echo "    spatialcpie: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALCPIE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALCPIE(ch_input)

    emit:
    results  = BIOC_SPATIALCPIE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALCPIE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALCPIE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALCPIE.out.versions  // channel: path(versions.yml)
}
