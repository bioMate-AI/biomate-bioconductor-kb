#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MouseFM
// This package provides methods for genetic finemapping in inbred mice by taking advantage of their ve
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MouseFM/inst/doc/fetch.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MouseFM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOUSEFM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mousefm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mousefm:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mousefm:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mousefm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mousefm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mousefm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MouseFM)
    library(jsonlite)

    # --- Fetch [] ---
    # Key functions: fetch
    ---------------------------------------------------------------------
    df = fetch("chr1", start=5000000, end=6000000)
    df[1:10,]
    # --- Comment [] ---
    # Key functions: comment
    ---------------------------------------------------------------------
    comment(df)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mousefm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mousefm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mousefm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOUSEFM:", paste0("    mousefm: ", packageVersion("MouseFM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mousefm_results.csv
    touch ${prefix}_mousefm_output.rds
    echo "BIOC_MOUSEFM:" > versions.yml
    echo "    mousefm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOUSEFM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOUSEFM(ch_input)

    emit:
    results  = BIOC_MOUSEFM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOUSEFM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOUSEFM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOUSEFM.out.versions  // channel: path(versions.yml)
}
