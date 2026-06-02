#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rhdf5client
// This package provides functionality for reading data from HDF Scalable Data Service from within R.  
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rhdf5client/inst/doc/delayed-array.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rhdf5client")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RHDF5CLIENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rhdf5client"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rhdf5client:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rhdf5client:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rhdf5client_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rhdf5client_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rhdf5client_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HSDSArray)
    library(jsonlite)

    # --- H S D S Array [] ---
    # Key functions: HSDSArray
    if (check_hsds()) {
    da <- HSDSArray(URL_hsds(), 'hsds',

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rhdf5client_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rhdf5client_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rhdf5client_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RHDF5CLIENT:", paste0("    rhdf5client: ", packageVersion("rhdf5client"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rhdf5client_results.csv
    touch ${prefix}_rhdf5client_output.rds
    echo "BIOC_RHDF5CLIENT:" > versions.yml
    echo "    rhdf5client: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RHDF5CLIENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RHDF5CLIENT(ch_input)

    emit:
    results  = BIOC_RHDF5CLIENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RHDF5CLIENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RHDF5CLIENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RHDF5CLIENT.out.versions  // channel: path(versions.yml)
}
