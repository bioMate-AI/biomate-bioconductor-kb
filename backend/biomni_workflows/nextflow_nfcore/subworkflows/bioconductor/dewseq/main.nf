#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEWSeq
// DEWSeq is a sliding window approach for the analysis of differentially enriched binding regions eCLI
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEWSeq/inst/doc/DEWSeq.R
// Upstream  : IHW, tidyverse
// Downstream: none
//
// Install: BiocManager::install("DEWSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEWSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dewseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dewseq:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dewseq:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dewseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dewseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dewseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEWSeq)
    library(DESeqDataSetFromSlidingWindows)
    library(jsonlite)

    # --- Size Factor Estimation and Filtering [] ---
    # Key functions: estimateSizeFactors, filterCounts
    ddw <- DEWSeq::estimateSizeFactors(ddw)
    ddw <- DEWSeq::filterCounts(
        object = ddw,
        maxCountFile = maxCountFile,
        countThresh = 5,
        nsamples = 2
    )


    # --- Dispersion Estimation and Wald Test [] ---
    # Key functions: estimateDispersions, nbinomWaldTest
    ddw <- DEWSeq::estimateDispersions(
        ddw,
        fitType = "local",
        quiet = TRUE
    )
    ddw <- DEWSeq::nbinomWaldTest(ddw)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dewseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dewseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dewseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEWSEQ:", paste0("    dewseq: ", packageVersion("DEWSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dewseq_results.csv
    touch ${prefix}_dewseq_output.rds
    echo "BIOC_DEWSEQ:" > versions.yml
    echo "    dewseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEWSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEWSEQ(ch_input)

    emit:
    results  = BIOC_DEWSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEWSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEWSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEWSEQ.out.versions  // channel: path(versions.yml)
}
