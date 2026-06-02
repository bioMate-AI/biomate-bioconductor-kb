#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: motifmatchr
// Quickly find motif matches for many motifs and many sequences. Wraps C++ code from the MOODS motif c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/motifmatchr/inst/doc/motifmatchr.R
// Upstream  : BSgenome, Biostrings, GenomicRanges, SummarizedExperiment, TFBSTools
// Downstream: none
//
// Install: BiocManager::install("motifmatchr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFMATCHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motifmatchr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motifmatchr:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-motifmatchr:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motifmatchr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motifmatchr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motifmatchr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(motifmatchr)
    library(Date)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Motif Matching with SummarizedExperiment [] ---
    # Key functions: matchMotifs, motifMatches
    data(example_motifs, package = "motifmatchr")
    peaks <- GenomicRanges::GRanges(
        seqnames = c("chr1", "chr2", "chr2"),
        ranges = IRanges::IRanges(
            start = c(76585873, 42772928, 100183786),
            width = 500
        )
    )
    se <- SummarizedExperiment::SummarizedExperiment(
        assays = list(counts = matrix(1, ncol = 4, nrow = 3)),
        rowRanges = peaks
    )
    motif_ix_se <- matchMotifs(example_motifs, se, genome = "hg19")
    matches_se <- motifMatches(motif_ix_se)


    # --- Motif Matching with Custom Background Frequencies [] ---
    # Key functions: matchMotifs
    data(example_motifs, package = "motifmatchr")
    peaks <- GenomicRanges::GRanges(
        seqnames = c("chr1", "chr2", "chr2"),
        ranges = IRanges::IRanges(
            start = c(76585873, 42772928, 100183786),
            width = 500
        )
    )
    bg_custom <- c("A" = 0.2, "C" = 0.3, "G" = 0.3, "T" = 0.2)
    motif_ix_bg <- matchMotifs(
        example_motifs,
        peaks,
        genome = "hg19",
        bg = bg_custom
    )


    # --- Extracting Motif Scores and Counts [] ---
    # Key functions: matchMotifs, motifMatches, motifScores, motifCounts
    data(example_motifs, package = "motifmatchr")
    peaks <- GenomicRanges::GRanges(
        seqnames = c("chr1", "chr2", "chr2"),
        ranges = IRanges::IRanges(
            start = c(76585873, 42772928, 100183786),
            width = 500
        )
    )
    motif_ix_scores <- matchMotifs(
        example_motifs,
        peaks,
        genome = "hg19",
        out = "scores"
    )
    m_matches <- motifMatches(motif_ix_scores)
    m_scores <- motifScores(motif_ix_scores)
    m_counts <- motifCounts(motif_ix_scores)


    # --- Extracting Genomic Positions of Motif Matches [] ---
    # Key functions: matchMotifs
    data(example_motifs, package = "motifmatchr")
    peaks <- GenomicRanges::GRanges(
        seqnames = c("chr1", "chr2", "chr2"),
        ranges = IRanges::IRanges(
            start = c(76585873, 42772928, 100183786),
            width = 500
        )
    )
    motif_pos <- matchMotifs(
        example_motifs,
        peaks,
        genome = "hg19",
        out = "positions"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motifmatchr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motifmatchr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motifmatchr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFMATCHR:", paste0("    motifmatchr: ", packageVersion("motifmatchr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motifmatchr_results.csv
    touch ${prefix}_motifmatchr_output.rds
    echo "BIOC_MOTIFMATCHR:" > versions.yml
    echo "    motifmatchr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFMATCHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFMATCHR(ch_input)

    emit:
    results  = BIOC_MOTIFMATCHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFMATCHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFMATCHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFMATCHR.out.versions  // channel: path(versions.yml)
}
