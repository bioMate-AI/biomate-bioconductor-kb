#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ngsReports
// This package provides methods and object classes for parsing FastQC reports and output summaries fro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ngsReports/inst/doc/ngsReportsIntroduction.R
// Upstream  : dplyr, pander
// Downstream: none
//
// Install: BiocManager::install("ngsReports")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NGSREPORTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ngsreports"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ngsreports:2.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ngsreports:2.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ngsreports_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ngsreports_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ngsreports_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ngsReports)
    library(jsonlite)

    # --- plot Summary [] ---
    # Key functions: plotSummary, plotReadTotals, theme
    plotSummary(fdl)
    plotReadTotals(fdl)
    plotReadTotals(fdl) +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ngsreports_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ngsreports_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ngsreports_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NGSREPORTS:", paste0("    ngsreports: ", packageVersion("ngsReports"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ngsreports_results.csv
    touch ${prefix}_ngsreports_output.rds
    echo "BIOC_NGSREPORTS:" > versions.yml
    echo "    ngsreports: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NGSREPORTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NGSREPORTS(ch_input)

    emit:
    results  = BIOC_NGSREPORTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NGSREPORTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NGSREPORTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NGSREPORTS.out.versions  // channel: path(versions.yml)
}
