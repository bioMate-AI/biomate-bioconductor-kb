#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DepecheR
// The purpose of this package is to identify traits in a dataset that can separate groups. This is don
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DepecheR/inst/doc/DepecheR_test.R
// Upstream  : BiocStyle, Rtsne, knitr
// Downstream: none
//
// Install: BiocManager::install("DepecheR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEPECHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-depecher"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-depecher:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-depecher:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_depecher_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_depecher_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_depecher_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DepecheR)
    library(jsonlite)

    # --- d Violins [] ---
    # Key functions: dViolins
    dViolins(testDataDepeche$clusterVector, inDataFrame = testData,
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_depecher_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_depecher_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_depecher_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEPECHER:", paste0("    depecher: ", packageVersion("DepecheR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_depecher_results.csv
    touch ${prefix}_depecher_output.rds
    echo "BIOC_DEPECHER:" > versions.yml
    echo "    depecher: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEPECHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEPECHER(ch_input)

    emit:
    results  = BIOC_DEPECHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEPECHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEPECHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEPECHER.out.versions  // channel: path(versions.yml)
}
