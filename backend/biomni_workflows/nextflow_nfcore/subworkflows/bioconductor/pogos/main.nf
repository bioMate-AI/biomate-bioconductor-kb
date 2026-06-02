#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pogos
// Provide simple utilities for querying bhklab PharmacoDB, modeling API outputs, and integrating to ce
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pogos/inst/doc/pogos.R
// Upstream  : ggplot2, httr, ontoProc, ontologyPlot, rjson
// Downstream: none
//
// Install: BiocManager::install("pogos")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_POGOS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pogos"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pogos:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pogos:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pogos_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pogos_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pogos_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pogos)
    library(DRProfSet)
    library(DRTraceSet)
    library(GET)
    library(jsonlite)

    # --- Retrieve Dose-Response Profiles [] ---
    # Key functions: DRProfSet
    drp <- DRProfSet()
    drp_class <- class(drp)
    drp_len <- length(drp)
    plot(drp)


    # --- Dose-Response Trace Visualization [] ---
    # Key functions: DRTraceSet
    trace_set <- DRTraceSet(dataset = "CCLE")
    trace_class <- class(trace_set)
    plot(trace_set)


    # --- Metadata Exploration [] ---
    # Key functions: cell_lines_v1, compounds_v1, datasets_v1
    data("cell_lines_v1", package = "pogos")
    data("compounds_v1", package = "pogos")
    data("datasets_v1", package = "pogos")
    cl_df <- as.data.frame(cell_lines_v1)
    comp_df <- as.data.frame(compounds_v1)
    ds_df <- as.data.frame(datasets_v1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pogos_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pogos_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pogos_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_POGOS:", paste0("    pogos: ", packageVersion("pogos"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pogos_results.csv
    touch ${prefix}_pogos_output.rds
    echo "BIOC_POGOS:" > versions.yml
    echo "    pogos: 0.0.0" >> versions.yml
    """
}


workflow BIOC_POGOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_POGOS(ch_input)

    emit:
    results  = BIOC_POGOS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_POGOS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_POGOS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_POGOS.out.versions  // channel: path(versions.yml)
}
