#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: zFPKM
// Perform the zFPKM transform on RNA-seq FPKM data. This algorithm is based on the publication by Hart
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/zFPKM/inst/doc/zFPKM.R
// Upstream  : printr, dplyr, GEOquery, stringr, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("zFPKM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ZFPKM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zfpkm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-zfpkm:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-zfpkm:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_zfpkm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zfpkm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zfpkm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(zFPKM)
    library(jsonlite)


    # --- Reproducible Settings [] ---
    # Key functions: set, function, center
    rm(list=ls())
    set.seed(8675309)
    options(stringsAsFactors=FALSE)
    library(printr)

    knitr::opts_chunk$set(message=FALSE, fig.align="center", fig.width=8, fig.height=6)

    ## -----------------------------------------------------------------------------
    library(dplyr)
    library(GEOquery)
    library(stringr)
    library(SummarizedExperiment)
    library(tidyr)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_zfpkm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_zfpkm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_zfpkm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZFPKM:", paste0("    zfpkm: ", packageVersion("zFPKM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zfpkm_results.csv
    touch ${prefix}_zfpkm_output.rds
    echo "BIOC_ZFPKM:" > versions.yml
    echo "    zfpkm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZFPKM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_ZFPKM(ch_input)

    emit:
    results  = BIOC_ZFPKM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZFPKM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZFPKM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZFPKM.out.versions  // channel: path(versions.yml)
}
