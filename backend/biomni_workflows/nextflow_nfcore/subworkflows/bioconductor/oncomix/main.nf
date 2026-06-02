#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: oncomix
// This package helps identify mRNAs that are overexpressed in subsets of tumors relative to normal tis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/oncomix/inst/doc/oncomix.R
// Upstream  : RColorBrewer, RMySQL, ggplot2
// Downstream: none
//
// Install: BiocManager::install("oncomix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONCOMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-oncomix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-oncomix:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-oncomix:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_oncomix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_oncomix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_oncomix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(oncomix)
    library(MySQL)
    library(jsonlite)

    # --- Oncogene Candidate Selection [] ---
    # Key functions: topGeneQuants
    data(exprNmlIsof, exprTumIsof, package = "oncomix")
    mmParams <- mixModelParams(exprNmlIsof[1:50, ], exprTumIsof[1:50, ])
    topGeneQuant <- topGeneQuants(mmParams, deltMu2Thr = 90,
                                  deltMu1Thr = 5, siThr = 0.9)


    # --- Expression Visualization [] ---
    # Key functions: plotGeneHist, scatterMixPlot
    data(exprNmlIsof, exprTumIsof, package = "oncomix")
    mmParams <- mixModelParams(exprNmlIsof[1:50, ], exprTumIsof[1:50, ])
    isof <- rownames(mmParams)[1]
    plotGeneHist(mmParams, exprNmlIsof, exprTumIsof, isof)
    scatterMixPlot(mmParams, selIndThresh = 0.9)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_oncomix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_oncomix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_oncomix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ONCOMIX:", paste0("    oncomix: ", packageVersion("oncomix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oncomix_results.csv
    touch ${prefix}_oncomix_output.rds
    echo "BIOC_ONCOMIX:" > versions.yml
    echo "    oncomix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ONCOMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ONCOMIX(ch_input)

    emit:
    results  = BIOC_ONCOMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ONCOMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ONCOMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ONCOMIX.out.versions  // channel: path(versions.yml)
}
