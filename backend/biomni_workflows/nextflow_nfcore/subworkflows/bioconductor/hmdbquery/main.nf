#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hmdbQuery
// Define utilities for exploration of human metabolome database, including functions to retrieve speci
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hmdbQuery/inst/doc/hmdbQuery.R
// Upstream  : gwascat, annotate
// Downstream: none
//
// Install: BiocManager::install("hmdbQuery")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HMDBQUERY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hmdbquery"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hmdbquery:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hmdbquery:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hmdbquery_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hmdbquery_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hmdbquery_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hmdbQuery)
    library(jsonlite)

    # --- biospecimens [] ---
    # Key functions: biospecimens, tissues
    biospecimens(lk1)
    tissues(lk1)
    st = store(lk1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hmdbquery_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hmdbquery_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hmdbquery_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HMDBQUERY:", paste0("    hmdbquery: ", packageVersion("hmdbQuery"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hmdbquery_results.csv
    touch ${prefix}_hmdbquery_output.rds
    echo "BIOC_HMDBQUERY:" > versions.yml
    echo "    hmdbquery: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HMDBQUERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HMDBQUERY(ch_input)

    emit:
    results  = BIOC_HMDBQUERY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HMDBQUERY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HMDBQUERY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HMDBQUERY.out.versions  // channel: path(versions.yml)
}
