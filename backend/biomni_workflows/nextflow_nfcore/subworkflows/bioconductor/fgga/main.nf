#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fgga
// Package that implements the FGGA algorithm. This package provides a hierarchical ensemble method bas
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fgga/inst/doc/fgga.R
// Upstream  : GOstats, knitr
// Downstream: none
//
// Install: BiocManager::install("fgga")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FGGA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fgga"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fgga:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fgga:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fgga_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fgga_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fgga_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fgga)
    library(jsonlite)

    # --- Settings [] ---
    # Key functions: set
    ----------------------------------------------------------------
    #library(knitr)
    #opts_chunk$set(warning=TRUE, message = FALSE, cache = FALSE, tidy = FALSE, tidy.opts = list(width.cutoff = 60))
    options(width = 100)
    knitr::opts_chunk$set(collapse = TRUE, comment = "#>",class.source = "whiteCode")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fgga_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fgga_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fgga_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FGGA:", paste0("    fgga: ", packageVersion("fgga"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fgga_results.csv
    touch ${prefix}_fgga_output.rds
    echo "BIOC_FGGA:" > versions.yml
    echo "    fgga: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FGGA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FGGA(ch_input)

    emit:
    results  = BIOC_FGGA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FGGA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FGGA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FGGA.out.versions  // channel: path(versions.yml)
}
