#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ccImpute
// Dropout events make the lowly expressed genes indistinguishable from true zero expression and differ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ccImpute/inst/doc/ccImpute.R
// Upstream  : BiocParallel, RhpcBLASctl, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("ccImpute")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CCIMPUTE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ccimpute"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ccimpute:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ccimpute:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ccimpute_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ccimpute_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ccimpute_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ccImpute)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
        collapse = TRUE,
        comment = "#>"
    )

    # --- Reproduce3 [] ---
    # Key functions: session_info, sessioninfo
    ## Session info
    library("sessioninfo")
    options(width = 120)
    session_info()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ccimpute_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ccimpute_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ccimpute_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CCIMPUTE:", paste0("    ccimpute: ", packageVersion("ccImpute"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ccimpute_results.csv
    touch ${prefix}_ccimpute_output.rds
    echo "BIOC_CCIMPUTE:" > versions.yml
    echo "    ccimpute: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CCIMPUTE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CCIMPUTE(ch_input)

    emit:
    results  = BIOC_CCIMPUTE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CCIMPUTE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CCIMPUTE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CCIMPUTE.out.versions  // channel: path(versions.yml)
}
