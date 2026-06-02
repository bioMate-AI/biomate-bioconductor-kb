#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowGate
// flowGate adds an interactive Shiny app to allow manual GUI-based gating of flow cytometry data in R.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowGate/inst/doc/flowGate.R
// Upstream  : flowCore, flowWorkspace, ncdfFlow
// Downstream: none
//
// Install: BiocManager::install("flowGate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWGATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowgate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowgate:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowgate:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowgate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowgate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowgate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GatingSet)
    library(jsonlite)

    # --- make GatingSet [] ---
    # Key functions: GatingSet
    library(flowWorkspace)
    gs <- GatingSet(fs)
    # --- Compensate data [] ---
    # Key functions: compensation, compensate

    # --- Acquisition [] ---
    # Key functions: spillover, compensation, compensate
    spillover(some_new_fs[[3]])
    comp_matrix <- spillover(some_new_fs[[3]])[[1]]
    comp <- compensation(comp_matrix)
    # --- create import function [] ---
    # Key functions: GatingSet, compensation, compensate

    # --- functional import [] ---
    # Key functions: import_gs, markernames


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowgate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowgate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowgate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWGATE:", paste0("    flowgate: ", packageVersion("flowGate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowgate_results.csv
    touch ${prefix}_flowgate_output.rds
    echo "BIOC_FLOWGATE:" > versions.yml
    echo "    flowgate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWGATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWGATE(ch_input)

    emit:
    results  = BIOC_FLOWGATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWGATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWGATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWGATE.out.versions  // channel: path(versions.yml)
}
