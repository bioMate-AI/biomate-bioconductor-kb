#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: comapr
// comapr detects crossover intervals for single gametes from their haplotype states sequences and stor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/comapr/inst/doc/getStarted.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("comapr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMAPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-comapr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-comapr:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-comapr:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_comapr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_comapr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_comapr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(comapr)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_comapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_comapr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_comapr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMAPR:", paste0("    comapr: ", packageVersion("comapr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comapr_results.csv
    touch ${prefix}_comapr_output.rds
    echo "BIOC_COMAPR:" > versions.yml
    echo "    comapr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMAPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMAPR(ch_input)

    emit:
    results  = BIOC_COMAPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMAPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMAPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMAPR.out.versions  // channel: path(versions.yml)
}
