#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidytof
// This package implements an interactive, scientific analysis pipeline for high-dimensional cytometry 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidytof/inst/doc/clustering.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tidytof")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYTOF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidytof"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidytof:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidytof:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidytof_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidytof_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidytof_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidytof)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: tof_preprocess, tof_cluster, starts_with, tof_metacluster, select
    ---------------------------------------------------------------------
    data(phenograph_data)
    set.seed(203L)
    phenograph_clusters <-
        phenograph_data |>
    # --- Count [] ---
    # Key functions: count
    ---------------------------------------------------------------------
    phenograph_clusters |>
        dplyr::count(phenograph_cluster, .kmeans_metacluster, sort = TRUE)
    # --- Column [] ---
    # Key functions: column, tof_preprocess, tof_cluster, contains
    ---------------------------------------------------------------------
    # will result in a tibble with only 1 column (the cluster labels)
    phenograph_data |>
        tof_preprocess() |>
        tof_cluster(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidytof_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidytof_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidytof_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYTOF:", paste0("    tidytof: ", packageVersion("tidytof"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidytof_results.csv
    touch ${prefix}_tidytof_output.rds
    echo "BIOC_TIDYTOF:" > versions.yml
    echo "    tidytof: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYTOF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYTOF(ch_input)

    emit:
    results  = BIOC_TIDYTOF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYTOF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYTOF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYTOF.out.versions  // channel: path(versions.yml)
}
