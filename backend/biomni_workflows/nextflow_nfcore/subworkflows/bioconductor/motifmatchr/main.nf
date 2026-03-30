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
    library(Date)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Find Motif Matches [] ---
    # Key functions: matchMotifs, SummarizedExperiment, equal, motifMatches
    ---------------------------------------------------------------------
    # using peaks
    motif_ix_peaks <- matchMotifs(example_motifs, peaks, genome = "hg19")
    # using SummarizedExperiment
    example_SummarizedExperiment <-
    # --- Find Motif Matches [] ---
    # Key functions: matchMotifs
    ---------------------------------------------------------------------
    motif_ix <- matchMotifs(example_motifs, peaks, genome = "hg19", bg = "even")
    # --- Find Motif Matches [] ---
    # Key functions: matchMotifs, motifMatches, motifScores, motifCounts
    ---------------------------------------------------------------------
    motif_ix <- matchMotifs(example_motifs, peaks, genome = "hg19")
    print(motif_ix)
    head(motifMatches(motif_ix))
    motif_ix_scores <- matchMotifs(example_motifs, peaks,
    # --- Date [] ---
    # Key functions: Date
    ---------------------------------------------------------------------
    Sys.Date()

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
