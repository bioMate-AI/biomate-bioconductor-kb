#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: multiscan
// Estimates gene expressions from several laser scans of the same microarray
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/multiscan/inst/doc/multiscan.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("multiscan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTISCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multiscan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multiscan:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multiscan:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multiscan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multiscan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multiscan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(multiscan)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: multiscan
    data(murine)
    fit<-multiscan(murine)
    fit

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multiscan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multiscan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multiscan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTISCAN:", paste0("    multiscan: ", packageVersion("multiscan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiscan_results.csv
    touch ${prefix}_multiscan_output.rds
    echo "BIOC_MULTISCAN:" > versions.yml
    echo "    multiscan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTISCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTISCAN(ch_input)

    emit:
    results  = BIOC_MULTISCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTISCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTISCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTISCAN.out.versions  // channel: path(versions.yml)
}
