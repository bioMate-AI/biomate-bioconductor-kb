#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rmspc
// The rmspc package runs MSPC (Multiple Sample Peak Calling) software using R. The analysis of ChIP-se
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rmspc/inst/doc/rmpsc.R
// Upstream  : BiocManager, GenomicRanges, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("rmspc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMSPC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rmspc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rmspc:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rmspc:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rmspc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rmspc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rmspc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rmspc)
    library(jsonlite)

    # --- mspc [] ---
    # Key functions: mspc
    library(rmspc)
    path <- system.file("extdata", package = "rmspc")
    list.files(path)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rmspc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rmspc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rmspc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RMSPC:", paste0("    rmspc: ", packageVersion("rmspc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rmspc_results.csv
    touch ${prefix}_rmspc_output.rds
    echo "BIOC_RMSPC:" > versions.yml
    echo "    rmspc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RMSPC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RMSPC(ch_input)

    emit:
    results  = BIOC_RMSPC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RMSPC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RMSPC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RMSPC.out.versions  // channel: path(versions.yml)
}
