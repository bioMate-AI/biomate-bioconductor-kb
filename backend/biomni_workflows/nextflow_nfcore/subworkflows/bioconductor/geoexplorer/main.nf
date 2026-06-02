#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GEOexplorer
// GEOexplorer is a webserver and R/Bioconductor package and web application that enables users to perf
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GEOexplorer/inst/doc/GEOexplorer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GEOexplorer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOEXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geoexplorer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geoexplorer:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geoexplorer:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geoexplorer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geoexplorer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geoexplorer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GEOexplorer)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Load Library [] ---
    # Key functions: loadApp
    library(GEOexplorer)

    ## -----------------------------------------------------------------------------
    loadApp()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geoexplorer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geoexplorer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geoexplorer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOEXPLORER:", paste0("    geoexplorer: ", packageVersion("GEOexplorer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geoexplorer_results.csv
    touch ${prefix}_geoexplorer_output.rds
    echo "BIOC_GEOEXPLORER:" > versions.yml
    echo "    geoexplorer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOEXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEOEXPLORER(ch_input)

    emit:
    results  = BIOC_GEOEXPLORER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOEXPLORER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOEXPLORER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOEXPLORER.out.versions  // channel: path(versions.yml)
}
