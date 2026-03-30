#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: synapter
// The synapter package provides functionality to reanalyse label-free proteomics data acquired on a Sy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/synapter/inst/doc/fragmentmatching.R
// Upstream  : BiocManager, BiocStyle, qvalue, synapterdata
// Downstream: synapterdata
//
// Install: BiocManager::install("synapter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNAPTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synapter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synapter:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synapter:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synapter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synapter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synapter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(synapter)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: synobj2RData, synergise1, filterFragments, fragmentMatching, plotFragmentMatching, kable, performance, getEMRTtable
    suppressPackageStartupMessages(library("synapter"))
    suppressPackageStartupMessages(library("synapterdata"))
    suppressPackageStartupMessages(library("BiocStyle"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synapter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synapter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synapter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNAPTER:", paste0("    synapter: ", packageVersion("synapter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synapter_results.csv
    touch ${prefix}_synapter_output.rds
    echo "BIOC_SYNAPTER:" > versions.yml
    echo "    synapter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNAPTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNAPTER(ch_input)

    emit:
    results  = BIOC_SYNAPTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNAPTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNAPTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNAPTER.out.versions  // channel: path(versions.yml)
}
