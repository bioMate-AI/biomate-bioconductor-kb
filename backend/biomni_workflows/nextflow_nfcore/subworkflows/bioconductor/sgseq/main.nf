#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SGSeq
// SGSeq is a software package for analyzing splice events from RNA-seq data. Input data are RNA-seq re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SGSeq/inst/doc/SGSeq.R
// Upstream  : knitr
// Downstream: EventPointer
//
// Install: BiocManager::install("SGSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SGSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sgseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sgseq:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sgseq:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sgseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sgseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sgseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SGSeq)
    library(jsonlite)

    # --- plot Features [] ---
    # Key functions: plotFeatures
    df <- plotFeatures(sgfc_ucsc, geneID = 1)
    # --- plot Variants [] ---
    # Key functions: plotVariants
    plotVariants(sgvc_pred, eventID = 1, color_novel = "red")
    # --- plot Splice Graph [] ---
    # Key functions: plotSpliceGraph, plotCoverage
    par(mfrow = c(5, 1), mar = c(1, 3, 1, 1))
    plotSpliceGraph(rowRanges(sgfc_pred), geneID = 1, toscale = "none", color_novel = "red")
    for (j in 1:4) {

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sgseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sgseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sgseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SGSEQ:", paste0("    sgseq: ", packageVersion("SGSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sgseq_results.csv
    touch ${prefix}_sgseq_output.rds
    echo "BIOC_SGSEQ:" > versions.yml
    echo "    sgseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SGSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SGSEQ(ch_input)

    emit:
    results  = BIOC_SGSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SGSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SGSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SGSEQ.out.versions  // channel: path(versions.yml)
}
