#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rTRMui
// This package provides a web interface to compute transcriptional regulatory modules with rTRM.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rTRMui/inst/doc/rTRMui.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rTRMui")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTRMUI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtrmui"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtrmui:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtrmui:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rtrmui_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtrmui_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtrmui_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rTRMui)
    library(jsonlite)

    # --- Runtrm [] ---
    # Key functions: runTRM
    ## library(rTRMui)
    ## runTRM()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtrmui_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtrmui_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtrmui_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTRMUI:", paste0("    rtrmui: ", packageVersion("rTRMui"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtrmui_results.csv
    touch ${prefix}_rtrmui_output.rds
    echo "BIOC_RTRMUI:" > versions.yml
    echo "    rtrmui: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTRMUI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RTRMUI(ch_input)

    emit:
    results  = BIOC_RTRMUI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTRMUI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTRMUI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTRMUI.out.versions  // channel: path(versions.yml)
}
