#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: erccdashboard
// Technical performance metrics for differential gene expression experiments using External RNA Contro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/erccdashboard/inst/doc/erccdashboard.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("erccdashboard")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ERCCDASHBOARD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-erccdashboard"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-erccdashboard:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-erccdashboard:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_erccdashboard_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_erccdashboard_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_erccdashboard_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(erccdashboard)
    library(jsonlite)

    # --- run Dashboard [] ---
    # Key functions: runDashboard
    exDat <- runDashboard(datType="count", isNorm = FALSE,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_erccdashboard_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_erccdashboard_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_erccdashboard_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ERCCDASHBOARD:", paste0("    erccdashboard: ", packageVersion("erccdashboard"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_erccdashboard_results.csv
    touch ${prefix}_erccdashboard_output.rds
    echo "BIOC_ERCCDASHBOARD:" > versions.yml
    echo "    erccdashboard: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ERCCDASHBOARD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ERCCDASHBOARD(ch_input)

    emit:
    results  = BIOC_ERCCDASHBOARD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ERCCDASHBOARD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ERCCDASHBOARD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ERCCDASHBOARD.out.versions  // channel: path(versions.yml)
}
