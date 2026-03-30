#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scmeth
// Functions to analyze methylation data can be found here. Some functions are relevant for single cell
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scmeth/inst/doc/my-vignette.R
// Upstream  : annotatr
// Downstream: none
//
// Install: BiocManager::install("scmeth")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMETH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmeth"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmeth:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmeth:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmeth_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmeth_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmeth_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scmeth)
    library(jsonlite)

    # --- Coverage [] ---
    # Key functions: coverage
    ---------------------------------------------------------------------
    scmeth::coverage(bsObject)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmeth_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmeth_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmeth_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMETH:", paste0("    scmeth: ", packageVersion("scmeth"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmeth_results.csv
    touch ${prefix}_scmeth_output.rds
    echo "BIOC_SCMETH:" > versions.yml
    echo "    scmeth: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMETH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMETH(ch_input)

    emit:
    results  = BIOC_SCMETH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMETH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMETH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMETH.out.versions  // channel: path(versions.yml)
}
