#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sparsenetgls
// The package provides methods of combining the graph structure learning and generalized least squares
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sparsenetgls/inst/doc/vignettes_sparsenetgls.R
// Upstream  : MASS, Matrix
// Downstream: none
//
// Install: BiocManager::install("sparsenetgls")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPARSENETGLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sparsenetgls"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sparsenetgls:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sparsenetgls:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sparsenetgls_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sparsenetgls_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sparsenetgls_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sparsenetgls)
    library(jsonlite)

    # --- example 1: assess estimated result from a GGM [] ---
    # Key functions: solve, mvrnorm, sparsenetgls, array
    library(MASS)
    library(Matrix)
    library(sparsenetgls)
    # --- example 2: Use the sparsenetgls and convertbeta function [] ---
    # Key functions: sparsenetgls, diag

    # --- example 3 [] ---
    # Key functions: plotsngls
    plotsngls(fitgls,ith_lambda=5)
    # --- example 4 [] ---
    # Key functions: sparsenetgls


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sparsenetgls_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sparsenetgls_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sparsenetgls_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPARSENETGLS:", paste0("    sparsenetgls: ", packageVersion("sparsenetgls"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sparsenetgls_results.csv
    touch ${prefix}_sparsenetgls_output.rds
    echo "BIOC_SPARSENETGLS:" > versions.yml
    echo "    sparsenetgls: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPARSENETGLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPARSENETGLS(ch_input)

    emit:
    results  = BIOC_SPARSENETGLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPARSENETGLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPARSENETGLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPARSENETGLS.out.versions  // channel: path(versions.yml)
}
