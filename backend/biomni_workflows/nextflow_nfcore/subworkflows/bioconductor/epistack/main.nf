#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epistack
// The epistack package main objective is the visualizations of stacks of genomic tracks (such as, but 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epistack/inst/doc/using_epistack.R
// Upstream  : EnrichedHeatmap, GenomicRanges, SummarizedExperiment, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("epistack")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPISTACK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epistack"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epistack:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epistack:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epistack_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epistack_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epistack_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- plot Epistack [] ---
    # Key functions: plotEpistack
    plotEpistack(
    ylim = c(0, 1), zlim = c(0, 1),
    x_labels = c("-2.5kb", "TSS", "+2.5kb"),
    # --- add Bins [] ---
    # Key functions: addBins, plotEpistack
    stackepi <- addBins(stackepi, nbins = 5)
    plotEpistack(
    ylim = c(0, 1), zlim = c(0, 1),
    # --- plot Epistack [] ---
    # Key functions: plotEpistack
    plotEpistack(
    ylim = c(0, 1), zlim = c(0, 1),
    x_labels = c("-2.5kb", "TSS", "+2.5kb"),
    # --- plot Average Profile [] ---
    # Key functions: plotAverageProfile
    plotAverageProfile(
    ylim = c(0, 1),
    x_labels = c("-2.5kb", "TSS", "+2.5kb"),
    # --- plot Stack Profile [] ---
    # Key functions: plotStackProfile
    plotStackProfile(
    x_labels = c("-2.5kb", "TSS", "+2.5kb"),
    zlim = c(0, 1)
    # --- plot Average Profile [] ---
    # Key functions: plotAverageProfile, plotStackProfile, plotStackProfileLegend
    layout(matrix(1:3, ncol = 1), heights = c(1.5, 3, 0.5))
    old_par <- par(mar = c(2.5, 4, 0.6, 0.6))
    plotAverageProfile(
    # --- union [] ---
    # Key functions: union, double, ifelse, mcols
    merged_peaks <- GenomicRanges::union(peaks[[1]], peaks[[2]])
    scores_rep1 <- double(length(merged_peaks))
    scores_rep1[findOverlaps(peaks[[1]], merged_peaks, select = "first")] <- peaks[[1]]$score
    # --- Resize genomic intervals [] ---
    # Key functions: normalizeToMatrix, resize
    library(EnrichedHeatmap)
    coverage_matrices <- lapply(
    function(x) {
    # --- ready to plot [] ---
    # Key functions: SummarizedExperiment
    merged_peaks <- SummarizedExperiment(
    # --- plot Epistack [] ---
    # Key functions: plotEpistack
    plotEpistack(
    assays = c("rep1", "rep2", "input"),
    tints = c("dodgerblue", "firebrick1", "grey"),
    # --- peak plot bin [] ---
    # Key functions: rowRanges, plotEpistack
    rowRanges(merged_peaks)$bin <- rowRanges(merged_peaks)$peak_type
    plotEpistack(
    assays = c("rep1", "rep2", "input"),
    # --- peak plot bin2 [] ---
    # Key functions: rowRanges, plotEpistack
    merged_peaks <- merged_peaks[order(
    rowRanges(merged_peaks)$bin, rowRanges(merged_peaks)$mean_scores,
    decreasing = c(FALSE, TRUE), method = "radix"
    # --- example2 tss [] ---
    # Key functions: promoters
    load(
    system.file("extdata", "chr21_test_data.RData",
    tss <- promoters(genes, upstream = 0, downstream = 1)
    # --- expression data [] ---
    # Key functions: addMetricAndArrangeGRanges
    expr <- data.frame(
    gene_id = names(rpkm),
    epidata <- addMetricAndArrangeGRanges(
    # --- add Bins [] ---
    # Key functions: addBins
    epidata <- addBins(epidata, nbins = 5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epistack_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epistack_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epistack_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPISTACK:", paste0("    epistack: ", packageVersion("epistack"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epistack_results.csv
    touch ${prefix}_epistack_output.rds
    echo "BIOC_EPISTACK:" > versions.yml
    echo "    epistack: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPISTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPISTACK(ch_input)

    emit:
    results  = BIOC_EPISTACK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPISTACK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPISTACK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPISTACK.out.versions  // channel: path(versions.yml)
}
