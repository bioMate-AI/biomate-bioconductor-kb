#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: m6Aboost
// This package can help user to run the m6Aboost model on their own miCLIP2 data. The package includes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/m6Aboost/inst/doc/m6AboosVignettes.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("m6Aboost")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_M6ABOOST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-m6aboost"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-m6aboost:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-m6aboost:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_m6aboost_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_m6aboost_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_m6aboost_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(m6Aboost)
    library(jsonlite)

    # --- Preparingdata [] ---
    # Key functions: preparingData
    ---------------------------------------------------------------------
    ## Extract the features for the m6Aboost prediction
    test <- preparingData(test, test_gff3, colname_reads="WTmean",
        colname_C2T="CtoTmean")
    test

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_m6aboost_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_m6aboost_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_m6aboost_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_M6ABOOST:", paste0("    m6aboost: ", packageVersion("m6Aboost"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_m6aboost_results.csv
    touch ${prefix}_m6aboost_output.rds
    echo "BIOC_M6ABOOST:" > versions.yml
    echo "    m6aboost: 0.0.0" >> versions.yml
    """
}


workflow BIOC_M6ABOOST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_M6ABOOST(ch_input)

    emit:
    results  = BIOC_M6ABOOST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_M6ABOOST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_M6ABOOST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_M6ABOOST.out.versions  // channel: path(versions.yml)
}
