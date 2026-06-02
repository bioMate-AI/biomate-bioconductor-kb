#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GateFinder
// Given a vector of cluster memberships for a cell population, identifies a sequence of gates (polygon
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GateFinder/inst/doc/GateFinder.R
// Upstream  : flowCore
// Downstream: none
//
// Install: BiocManager::install("GateFinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GATEFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gatefinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gatefinder:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gatefinder:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gatefinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gatefinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gatefinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GateFinder)
    library(jsonlite)

    # --- Gating Optimization [] ---
    # Key functions: GateFinder
    results <- GateFinder(
        x = x,
        target = targetpop,
        outlier.percentile = 0.5,
        beta = 0.5
    )


    # --- Gating Visualization [] ---
    # Key functions: plot
    plot(
        x,
        results,
        c(2, 3),
        targetpop
    )
    plot(results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gatefinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gatefinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gatefinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GATEFINDER:", paste0("    gatefinder: ", packageVersion("GateFinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gatefinder_results.csv
    touch ${prefix}_gatefinder_output.rds
    echo "BIOC_GATEFINDER:" > versions.yml
    echo "    gatefinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GATEFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GATEFINDER(ch_input)

    emit:
    results  = BIOC_GATEFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GATEFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GATEFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GATEFINDER.out.versions  // channel: path(versions.yml)
}
