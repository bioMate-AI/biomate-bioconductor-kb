#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifmatchr — motif_matching_genomic_ranges
// Find motif matches, scores, and genomic positions within a set of genomic ranges (peaks).
// Input: peaks, example_motifs
// Container: quay.io/biocontainers/bioconductor-motifmatchr:1.32.0--r45ha27e39d_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, Biostrings, BSgenome, GenomicRanges, motifmatchr, SummarizedExperiment, TFBSTools
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, SummarizedExperiment, motifmatchr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the motifmatchr, GenomicRanges, SummarizedExperiment, and BSgenome libraries
//  * 2. [Input & Preparation] Load example motifs and define genomic ranges (peaks)
//  * 3. [Core Analysis] Find motif matches using matchMotifs with default settings
//  * 4. [Core Analysis] Extract the boolean matches matrix using motifMatches
//  * 5. [Core Analysis] Find motif matches and extract scores and counts using out = "scores"
//  * 6. [Core Analysis] Find exact genomic positions of motif matches using out = "positions"

nextflow.enable.dsl = 2

process BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "Biostrings", "BSgenome", "GenomicRanges", "motifmatchr", "SummarizedExperiment", "TFBSTools")
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
    
    # 1. Load the motifmatchr, GenomicRanges, SummarizedExperiment, and BSgenome libraries
    library(motifmatchr)
    library(GenomicRanges)
    library(BSgenome)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # 2. Load example motifs and define genomic ranges (peaks) from user input files
    # The pipeline reads exactly these files from the working directory
    peaks <- readRDS("peaks.rds")
    example_motifs <- readRDS("example_motifs.rds")
    
    # 3. Find motif matches using matchMotifs with default settings
    motif_ix <- matchMotifs(example_motifs, peaks, genome = "hg19") 
    
    # 4. Extract the boolean matches matrix using motifMatches
    matches_matrix <- motifMatches(motif_ix)
    print(matches_matrix)
    
    # Save default match results
    saveRDS(motif_ix, "motif_ix.rds")
    write.csv(as.matrix(matches_matrix), "motif_matches.csv", row.names = TRUE)
    
    # 5. Find motif matches and extract scores and counts using out = "scores"
    motif_ix_scores <- matchMotifs(example_motifs, peaks, 
                                    genome = "hg19", out = "scores")
    print(head(motifMatches(motif_ix_scores)))
    print(head(motifScores(motif_ix_scores)))
    print(head(motifCounts(motif_ix_scores)))
    
    # Save scores and counts results
    saveRDS(motif_ix_scores, "motif_ix_scores.rds")
    write.csv(as.matrix(motifMatches(motif_ix_scores)), "motif_matches_from_scores.csv", row.names = TRUE)
    write.csv(as.matrix(motifScores(motif_ix_scores)), "motif_scores.csv", row.names = TRUE)
    write.csv(as.matrix(motifCounts(motif_ix_scores)), "motif_counts.csv", row.names = TRUE)
    
    # 6. Find exact genomic positions of motif matches using out = "positions"
    motif_pos <- matchMotifs(example_motifs, peaks, genome = "hg19", 
                              out = "positions") 
    print(motif_pos)
    
    # Save positions results
    saveRDS(motif_pos, "motif_positions.rds")
    
    # Export positions as a flat table for downstream convenience
    motif_pos_df <- as.data.frame(motif_pos)
    write.csv(motif_pos_df, "motif_positions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES":',
        paste0('    motifmatchr: ', as.character(packageVersion('motifmatchr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_matching_genomic_ranges.csv versions.yml
    """
}

workflow BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks, example_motifs ] ]

    main:
    BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES(ch_input)

    emit:
    tables   = BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES.out.tables
    plots    = BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES.out.plots
    objects  = BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES.out.objects
    versions = BIOC_MOTIFMATCHR_MOTIF_MATCHING_GENOMIC_RANGES.out.versions
}
