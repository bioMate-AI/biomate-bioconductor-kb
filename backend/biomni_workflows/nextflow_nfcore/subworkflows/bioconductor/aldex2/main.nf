#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ALDEx2
// A differential abundance analysis for the comparison of two or more conditions. Useful for analyzing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ALDEx2/inst/doc/ALDEx2_vignette.R
// Upstream  : cowplot, ggpattern, ggplot2, tidyverse
// Downstream: omicplotR
//
// Install: BiocManager::install("ALDEx2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALDEX2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aldex2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aldex2:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aldex2:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_aldex2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aldex2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aldex2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ALDEx2)
    library(jsonlite)

    # --- load_all [] ---
    # Key functions: load_all
    devtools::load_all('~/Documents/0_git/ALDEx_bioc')
    library(ALDEx2)
    set.seed(11)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aldex2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aldex2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aldex2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALDEX2:", paste0("    aldex2: ", packageVersion("ALDEx2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aldex2_results.csv
    touch ${prefix}_aldex2_output.rds
    echo "BIOC_ALDEX2:" > versions.yml
    echo "    aldex2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALDEX2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALDEX2(ch_input)

    emit:
    results  = BIOC_ALDEX2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALDEX2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALDEX2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALDEX2.out.versions  // channel: path(versions.yml)
}
