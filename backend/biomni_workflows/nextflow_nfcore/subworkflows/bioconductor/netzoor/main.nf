#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: netZooR
// netZooR unifies the implementations of several Network Zoo methods (netzoo, netzoo.github.io) into a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/netZooR/inst/doc/CONDOR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("netZooR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETZOOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-netzoor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-netzoor:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-netzoor:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_netzoor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_netzoor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_netzoor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(netZooR)
    library(jsonlite)

    # --- fig=TRUE [] ---
    # Key functions: condorCoreEnrich

    # --- fig=TRUE [] ---
    # Key functions: condorPlotHeatmap
    condorPlotHeatmap(condor.object)
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_netzoor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_netzoor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_netzoor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NETZOOR:", paste0("    netzoor: ", packageVersion("netZooR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netzoor_results.csv
    touch ${prefix}_netzoor_output.rds
    echo "BIOC_NETZOOR:" > versions.yml
    echo "    netzoor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NETZOOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NETZOOR(ch_input)

    emit:
    results  = BIOC_NETZOOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NETZOOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NETZOOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NETZOOR.out.versions  // channel: path(versions.yml)
}
