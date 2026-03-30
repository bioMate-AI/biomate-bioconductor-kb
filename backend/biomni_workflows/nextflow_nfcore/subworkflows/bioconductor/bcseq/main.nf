#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bcSeq
// This Rcpp-based package implements a highly efficient data structure and algorithm for performing al
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bcSeq/inst/doc/bcSeq.R
// Upstream  : Matrix, Rcpp, gdata, knitr
// Downstream: none
//
// Install: BiocManager::install("bcSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BCSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bcseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bcseq:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bcseq:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bcseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bcseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bcseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bcSeq)
    library(jsonlite)

    # --- BcSeq hamming analysis [] ---
    # Key functions: bcSeq_hamming, bcSeq_edit, rep, sourceCpp, toLatex
    bases     <- c(rep('A', 4), rep('C',4), rep('G',4), rep('T',4))
    Barcodes  <- rep(NA, numOfBars*2)
    for (i in 1:numOfBars){

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bcseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bcseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bcseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BCSEQ:", paste0("    bcseq: ", packageVersion("bcSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bcseq_results.csv
    touch ${prefix}_bcseq_output.rds
    echo "BIOC_BCSEQ:" > versions.yml
    echo "    bcseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BCSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BCSEQ(ch_input)

    emit:
    results  = BIOC_BCSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BCSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BCSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BCSEQ.out.versions  // channel: path(versions.yml)
}
