#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ExperimentHub
// This package provides a client for the Bioconductor ExperimentHub web resource. ExperimentHub provid
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ExperimentHub/inst/doc/ExperimentHub.R
// Upstream  : none
// Downstream: adductomicsR, CoSIA, iSEEhub, LRcell, octad
//
// Install: BiocManager::install("ExperimentHub")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXPERIMENTHUB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-experimenthub"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-experimenthub:2.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-experimenthub:2.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_experimenthub_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_experimenthub_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_experimenthub_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocHubsShiny)
    library(jsonlite)

    # --- Query and Retrieve Data [] ---
    # Key functions: query
    apData <- query(eh, "alpineData")
    # --- Interactive Retrieval [] ---
    # Key functions: BiocHubsShiny
    BiocHubsShiny::BiocHubsShiny()
    # --- Check Possible Dates [] ---
    # Key functions: possibleDates
    pd <- possibleDates(eh)
    # --- Set Snapshot Date [] ---
    # Key functions: snapshotDate
    snapshotDate(ah) <- pd[1]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_experimenthub_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_experimenthub_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_experimenthub_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EXPERIMENTHUB:", paste0("    experimenthub: ", packageVersion("ExperimentHub"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_experimenthub_results.csv
    touch ${prefix}_experimenthub_output.rds
    echo "BIOC_EXPERIMENTHUB:" > versions.yml
    echo "    experimenthub: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EXPERIMENTHUB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EXPERIMENTHUB(ch_input)

    emit:
    results  = BIOC_EXPERIMENTHUB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EXPERIMENTHUB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EXPERIMENTHUB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EXPERIMENTHUB.out.versions  // channel: path(versions.yml)
}
