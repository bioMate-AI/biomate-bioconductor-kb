#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: snifter
// Provides an R wrapper for the implementation of FI-tSNE from the python package openTNSE. See Poliča
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/snifter/inst/doc/snifter.R
// Upstream  : BiocStyle
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("snifter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNIFTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snifter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snifter:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snifter:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snifter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snifter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snifter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(snifter)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: fitsne, ggplot, aes, geom_point, scale_colour_discrete
    fit <- fitsne(counts, random_state = 42L)
    ggplot() +
    aes(fit[, 1], fit[, 2], colour = label) +
    # --- sample [] ---
    # Key functions: sample, setdiff, fitsne
    test_ind <- sample(nrow(counts), nrow(counts) / 2)
    train_ind <- setdiff(seq_len(nrow(counts)), test_ind)
    embedding <- fitsne(train_mat, random_state = 42L)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: project, ggplot, geom_point, aes, scale_colour_discrete
    new_coords <- project(embedding, new = test_mat, old = train_mat)
    ggplot() +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snifter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snifter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snifter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNIFTER:", paste0("    snifter: ", packageVersion("snifter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snifter_results.csv
    touch ${prefix}_snifter_output.rds
    echo "BIOC_SNIFTER:" > versions.yml
    echo "    snifter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNIFTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNIFTER(ch_input)

    emit:
    results  = BIOC_SNIFTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNIFTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNIFTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNIFTER.out.versions  // channel: path(versions.yml)
}
