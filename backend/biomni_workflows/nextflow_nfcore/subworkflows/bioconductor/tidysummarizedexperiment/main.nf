#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidySummarizedExperiment
// The tidySummarizedExperiment package provides a set of tools for creating and manipulating tidy data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidySummarizedExperiment/inst/doc/introduction.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("tidySummarizedExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYSUMMARIZEDEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidysummarizedexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidysummarizedexperiment:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidysummarizedexperiment:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidysummarizedexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidysummarizedexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidysummarizedexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidySummarizedExperiment)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_density, scale_x_log10
    ggplot(aes(counts + 1, group=.sample, color=`type`)) +
    geom_density() +
    scale_x_log10() +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidysummarizedexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidysummarizedexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidysummarizedexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYSUMMARIZEDEXPERIMENT:", paste0("    tidysummarizedexperiment: ", packageVersion("tidySummarizedExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidysummarizedexperiment_results.csv
    touch ${prefix}_tidysummarizedexperiment_output.rds
    echo "BIOC_TIDYSUMMARIZEDEXPERIMENT:" > versions.yml
    echo "    tidysummarizedexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYSUMMARIZEDEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYSUMMARIZEDEXPERIMENT(ch_input)

    emit:
    results  = BIOC_TIDYSUMMARIZEDEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYSUMMARIZEDEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYSUMMARIZEDEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYSUMMARIZEDEXPERIMENT.out.versions  // channel: path(versions.yml)
}
