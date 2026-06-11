#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epistack — chipseq_peaks_quality
// Visualize ChIP-seq coverage signal centered around merged peak regions, sorted and binned by peak scores.
// Input: path_peaks, path_reads
// Container: quay.io/biocontainers/bioconductor-epistack:1.16.0--r45hdfd78af_0
// R packages: EnrichedHeatmap, epistack, GenomicRanges, rtracklayer, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: EnrichedHeatmap, GenomicRanges, SummarizedExperiment, epistack, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load peak files using rtracklayer::import
//  * 2. [Visualization & Output] Merge peaks across replicates using GenomicRanges::union
//  * 3. [Visualization & Output] Load aligned reads using rtracklayer::import
//  * 4. [Visualization & Output] Generate coverage matrices around peak centers using
//  * 5. [Visualization & Output] Construct a SummarizedExperiment object containing the
//  * 6. [Visualization & Output] Assign peak types as bins and plot the stacked profiles

nextflow.enable.dsl = 2

process BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("EnrichedHeatmap", "epistack", "GenomicRanges", "rtracklayer", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Define input file paths in the working directory
    path_peaks <- c(
        peak1 = "peak1.bed",
        peak2 = "peak2.bed"
    )
    
    path_reads <- c(
        rep1 = "rep1.bed",
        rep2 = "rep2.bed",
        input = "input.bed"
    )
    
    # Load required libraries
    library(rtracklayer)
    library(GenomicRanges)
    library(EnrichedHeatmap)
    library(epistack)
    
    # --- Load peak files using rtracklayer::import ---
    peaks <- lapply(path_peaks, import)
    
    # --- Merge peaks across replicates using GenomicRanges::union ---
    merged_peaks <- GenomicRanges::union(peaks[[1]], peaks[[2]])
    
    scores_rep1 <- double(length(merged_peaks))
    scores_rep1[findOverlaps(peaks[[1]], merged_peaks, select = "first")] <- peaks[[1]]\$score
    
    scores_rep2 <- double(length(merged_peaks))
    scores_rep2[findOverlaps(peaks[[2]], merged_peaks, select = "first")] <- peaks[[2]]\$score
    
    peak_type <- ifelse(
        scores_rep1 != 0 & scores_rep2 != 0, "Both", ifelse(
            scores_rep1 != 0, "Rep1 only", "Rep2 only"
        )
    )
    
    mcols(merged_peaks) <- DataFrame(scores_rep1, scores_rep2, peak_type)
    merged_peaks\$mean_scores <- apply((mcols(merged_peaks)[, c("scores_rep1", "scores_rep2")]), 1, mean)
    merged_peaks <- merged_peaks[order(merged_peaks\$mean_scores, decreasing = TRUE), ]
    rm(scores_rep1, scores_rep2, peak_type)
    
    # --- Load aligned reads using rtracklayer::import ---
    reads <- lapply(path_reads, import)
    
    # --- Generate coverage matrices around peak centers using ---
    coverage_matrices <- lapply(
        reads,
        function(x) {
            normalizeToMatrix(
                x,
                resize(merged_peaks, width = 1, fix = "center"),
                extend = 5000, w = 250, 
                mean_mode = "coverage"
            )
        }
    )
    
    xlabs <- c("-5kb", "peak center", "+5kb")
    
    # --- Construct a SummarizedExperiment object containing the ---
    merged_peaks <- SummarizedExperiment(
        rowRanges = merged_peaks,
        assays = coverage_matrices
    )
    
    # --- Assign peak types as bins and plot the stacked profiles ---
    rowRanges(merged_peaks)\$bin <- rowRanges(merged_peaks)\$peak_type
    
    # Save the visualization plot as a PDF
    pdf("epistack_peaks_quality_plot.pdf", width = 8, height = 10)
    plotEpistack(
        merged_peaks,
        assays = c("rep1", "rep2", "input"),
        tints = c("dodgerblue", "firebrick1", "grey"), 
        titles = c("Rep1", "Rep2" , "Input"),
        x_labels = xlabs,
        zlim = c(0, 4), ylim = c(0, 4), 
        metric_col = "mean_scores", metric_title = "Peak score", metric_label = "score",
        bin_palette = colorRampPalette(c("darkorchid1", "dodgerblue", "firebrick1")),
        npix_height = 300
    )
    dev.off()
    
    # Save the final SummarizedExperiment object
    saveRDS(merged_peaks, "merged_peaks_epistack.rds")
    
    # Save the metadata of the merged peaks as a CSV table
    write.csv(as.data.frame(rowRanges(merged_peaks)), "merged_peaks_metadata.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY":',
        paste0('    epistack: ', as.character(packageVersion('epistack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_peaks_quality.csv versions.yml
    """
}

workflow BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path_peaks, path_reads ] ]

    main:
    BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY(ch_input)

    emit:
    tables   = BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY.out.tables
    plots    = BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY.out.plots
    objects  = BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY.out.objects
    versions = BIOC_EPISTACK_CHIPSEQ_PEAKS_QUALITY.out.versions
}
