#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: isobar
// isobar provides methods for preprocessing, normalization, and report generation for the analysis of 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/isobar/inst/doc/isobar-devel.R
// Upstream  : distr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("isobar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOBAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isobar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isobar:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isobar:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isobar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isobar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isobar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(isobar)
    library(jsonlite)

    # --- Isobar Devel.Rnw:43 44 [] ---
    # Key functions: getClass
    getClass("IBSpectra")
    # --- Isobar Devel.Rnw:70 71 [] ---
    # Key functions: getClass
    getClass("ProteinGroup")
    # --- Isobar Devel.Rnw:84 85 [] ---
    # Key functions: getClass
    getClass("NoiseModel")
    # --- Isobar Devel.Rnw:95 96 [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isobar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isobar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isobar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOBAR:", paste0("    isobar: ", packageVersion("isobar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isobar_results.csv
    touch ${prefix}_isobar_output.rds
    echo "BIOC_ISOBAR:" > versions.yml
    echo "    isobar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOBAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOBAR(ch_input)

    emit:
    results  = BIOC_ISOBAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOBAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOBAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOBAR.out.versions  // channel: path(versions.yml)
}
