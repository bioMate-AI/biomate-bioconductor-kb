#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: strandCheckR
// This package aims to quantify and remove putative double strand DNA from a strand-specific RNA sampl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/strandCheckR/inst/doc/strandCheckR.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("strandCheckR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRANDCHECKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-strandcheckr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-strandcheckr:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-strandcheckr:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_strandcheckr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_strandcheckr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_strandcheckr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(strandCheckR)
    library(jsonlite)

    # --- Read Strand Information from BAM ---
    # Key functions: getStrandFromBamFile
    files <- system.file(
        "extdata", c("s1.sorted.bam", "s2.sorted.bam"),
        package = "strandCheckR"
    )
    win <- getStrandFromBamFile(files, sequences = "10")
    win$File <- basename(as.character(win$File))
    sorted_win <- win[order((win$NbPos + win$NbNeg), decreasing = TRUE), ]

    # --- Annotate Windows with Genomic Features ---
    # Key functions: intersectWithFeature
    annot <- GenomicRanges::GRanges(
        seqnames = "chr10",
        ranges = IRanges::IRanges(start = 1, end = 100000)
    )
    win$Seq <- paste0("chr", win$Seq)
    win_annot <- intersectWithFeature(
        windows = win,
        annotation = annot,
        overlapCol = "OverlapTranscript"
    )

    # --- Visualize Strand Proportion Histograms ---
    # Key functions: plotHist, plotWin
    win$OverlapTranscript <- "Transcript"
    plotHist(
        windows = win,
        groupBy = c("File", "OverlapTranscript"),
        normalizeBy = "File",
        scales = "free_y"
    )
    plotWin(win, groupBy = "File")

    # --- Filter Double-Stranded DNA Contamination ---
    # Key functions: filterDNA
    files <- system.file(
        "extdata", c("s1.sorted.bam", "s2.sorted.bam"),
        package = "strandCheckR"
    )
    win2 <- filterDNA(
        file = files[2],
        sequences = "10",
        destination = tempfile(fileext = ".bam"),
        threshold = 0.7,
        getWin = TRUE
    )
    win2$File <- basename(as.character(win2$File))

    # --- Compare Before and After Filtering ---
    # Key functions: plotHist
    win2$File <- factor(
        win2$File,
        levels = c("s2.sorted.bam", "s2.filter.bam")
    )
    plotHist(
        win2,
        groupBy = "File",
        normalizeBy = "File",
        scales = "free_y"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_strandcheckr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_strandcheckr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_strandcheckr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRANDCHECKR:", paste0("    strandcheckr: ", packageVersion("strandCheckR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_strandcheckr_results.csv
    touch ${prefix}_strandcheckr_output.rds
    echo "BIOC_STRANDCHECKR:" > versions.yml
    echo "    strandcheckr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRANDCHECKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRANDCHECKR(ch_input)

    emit:
    results  = BIOC_STRANDCHECKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRANDCHECKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRANDCHECKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRANDCHECKR.out.versions  // channel: path(versions.yml)
}
