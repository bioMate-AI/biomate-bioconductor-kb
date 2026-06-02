#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: monocle
// Monocle performs differential expression and time-series analysis for single-cell expression experim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/monocle/inst/doc/monocle-vignette.R
// Upstream  : Biobase, ggplot2, knitr, reshape2
// Downstream: cicero
//
// Install: BiocManager::install("monocle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MONOCLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-monocle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-monocle:2.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-monocle:2.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_monocle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_monocle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_monocle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(monocle)
    library(jsonlite)


    # --- Include=false [] ---
    # Key functions: set
    library(knitr)
    opts_chunk$set(
    #concordance=TRUE
    )

    # --- Gene Pairwise Kinetic Plot [] ---
    # Key functions: monocle
    plot(1:10)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_monocle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_monocle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_monocle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MONOCLE:", paste0("    monocle: ", packageVersion("monocle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_monocle_results.csv
    touch ${prefix}_monocle_output.rds
    echo "BIOC_MONOCLE:" > versions.yml
    echo "    monocle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MONOCLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MONOCLE(ch_input)

    emit:
    results  = BIOC_MONOCLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MONOCLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MONOCLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MONOCLE.out.versions  // channel: path(versions.yml)
}
