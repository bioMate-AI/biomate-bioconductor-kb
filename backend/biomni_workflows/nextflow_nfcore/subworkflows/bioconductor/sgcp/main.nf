#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SGCP
// SGC is a semi-supervised pipeline for gene clustering in gene co-expression networks. SGC consists o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SGCP/inst/doc/SGCP.R
// Upstream  : SummarizedExperiment, knitr
// Downstream: none
//
// Install: BiocManager::install("SGCP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SGCP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sgcp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sgcp:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sgcp:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sgcp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sgcp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sgcp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SGCP)
    library(jsonlite)

    # --- Knitr Options [] ---
    # Key functions: set
    --------------
    library(knitr)
    opts_chunk$set(fig.align = 'center', fig.width = 6, fig.height = 6, dev = 'png')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sgcp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sgcp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sgcp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SGCP:", paste0("    sgcp: ", packageVersion("SGCP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sgcp_results.csv
    touch ${prefix}_sgcp_output.rds
    echo "BIOC_SGCP:" > versions.yml
    echo "    sgcp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SGCP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SGCP(ch_input)

    emit:
    results  = BIOC_SGCP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SGCP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SGCP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SGCP.out.versions  // channel: path(versions.yml)
}
