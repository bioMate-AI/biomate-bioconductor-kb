#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RAIDS
// This package implements specialized algorithms that enable genetic ancestry inference from various c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RAIDS/inst/doc/Create_Reference_GDS_File.R
// Upstream  : SNPRelate, gdsfmt, knitr
// Downstream: none
//
// Install: BiocManager::install("RAIDS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAIDS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-raids"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-raids:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-raids:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_raids_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_raids_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_raids_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RAIDS)
    library(jsonlite)

    # --- snpgds Open [] ---
    # Key functions: snpgdsOpen
    library(RAIDS)
    library(SNPRelate)
    pathRef <- system.file("extdata/", package="RAIDS")
    # --- unlink [] ---
    # Key functions: unlink
    library(RAIDS)
    library(SNPRelate)
    library(gdsfmt)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_raids_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_raids_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_raids_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAIDS:", paste0("    raids: ", packageVersion("RAIDS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raids_results.csv
    touch ${prefix}_raids_output.rds
    echo "BIOC_RAIDS:" > versions.yml
    echo "    raids: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAIDS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAIDS(ch_input)

    emit:
    results  = BIOC_RAIDS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAIDS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAIDS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAIDS.out.versions  // channel: path(versions.yml)
}
