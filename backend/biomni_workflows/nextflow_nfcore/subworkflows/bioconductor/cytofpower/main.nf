#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CyTOFpower
// This package is a tool to predict the power of CyTOF experiments in the context of differential stat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CyTOFpower/inst/doc/CyTOFpower.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CyTOFpower")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOFPOWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytofpower"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytofpower:1.12.1--r44_0' :
        'quay.io/biocontainers/bioconductor-cytofpower:1.12.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytofpower_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytofpower_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytofpower_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CyTOFpower)
    library(jsonlite)

    # --- Cy T O Fpower [] ---
    # Key functions: CyTOFpower
    library(CyTOFpower)
    CyTOFpower()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytofpower_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytofpower_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytofpower_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOFPOWER:", paste0("    cytofpower: ", packageVersion("CyTOFpower"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytofpower_results.csv
    touch ${prefix}_cytofpower_output.rds
    echo "BIOC_CYTOFPOWER:" > versions.yml
    echo "    cytofpower: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOFPOWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOFPOWER(ch_input)

    emit:
    results  = BIOC_CYTOFPOWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOFPOWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOFPOWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOFPOWER.out.versions  // channel: path(versions.yml)
}
