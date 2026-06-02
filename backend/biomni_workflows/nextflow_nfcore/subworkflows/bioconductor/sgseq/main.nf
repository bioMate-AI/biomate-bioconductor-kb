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

    # --- Transcript Feature Conversion ---
    # Key functions: convertToTxFeatures, convertToSGFeatures, analyzeFeatures
    txf_ucsc <- convertToTxFeatures(txdb)
    txf_ucsc <- txf_ucsc[txf_ucsc %over% gr]
    sgf_ucsc <- convertToSGFeatures(txf_ucsc)
    sgfc_ucsc <- analyzeFeatures(si, features = txf_ucsc)

    # --- Splice Graph Feature Prediction and Quantification ---
    # Key functions: predictTxFeatures, convertToSGFeatures, annotate, getSGFeatureCounts
    txf <- predictTxFeatures(si, gr)
    sgf <- convertToSGFeatures(txf)
    sgf <- annotate(sgf, txf_ucsc)
    sgfc <- getSGFeatureCounts(si, sgf)

    # --- Splice Variant Identification and Quantification ---
    # Key functions: findSGVariants, getSGVariantCounts, variantFreq, counts
    sgv <- findSGVariants(sgf)
    sgvc <- getSGVariantCounts(sgv, sgfc)
    v_freq <- variantFreq(sgvc)
    v_counts <- counts(sgvc)

    # --- Splice Variant Effect Prediction ---
    # Key functions: predictVariantEffects
    sgv_pred <- rowRanges(sgvc)
    vep <- predictVariantEffects(sgv_pred, txdb, Hsapiens)

    # --- Visualisation of Splice Graphs and Coverage ---
    # Key functions: plotFeatures, plotVariants, plotSpliceGraph, plotCoverage
    df_feat <- plotFeatures(sgfc, geneID = 1, color_novel = "red")
    plotVariants(sgvc, eventID = 1, color_novel = "red")
    plotSpliceGraph(
        rowRanges(sgfc),
        geneID = 1,
        toscale = "none",
        color_novel = "red"
    )
    plotCoverage(sgfc[, 1], geneID = 1, toscale = "none")


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
