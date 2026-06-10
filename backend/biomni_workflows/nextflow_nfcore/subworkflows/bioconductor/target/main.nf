#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: target — direct_target_prediction
// Predict direct target genes by integrating DNA-binding peaks and differential expression data, and statistically/visually validate the predictions.
// Input: real_peaks.RData, real_transcripts.RData
// Container: quay.io/biocontainers/bioconductor-target:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, target
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the target and GenomicRanges libraries
//  * 2. [Input & Preparation] Load or prepare the peaks and transcripts GRanges objects
//  * 3. [Core Analysis] Identify associated peaks near the regions of interest using associated_peaks
//  * 4. [Core Analysis] Predict direct target genes using direct_targets by integrating regulatory potential and differential expression statistics
//  * 5. [Visualization & Output] Visualize the relationship between peak distance/score, gene statistics/score, and the empirical cumulative distribution function 
//  * 6. [Core Analysis] Statistically test if the predicted targets are non-randomly distributed using test_predictions
//  * 7. [Core Analysis] Identify the top-ranked direct target genes and their associated peaks

nextflow.enable.dsl = 2

process BIOC_TARGET_DIRECT_TARGET_PREDICTION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(target)
    library(GenomicRanges)
    
    # Load peaks and transcripts data from the working directory
    load("real_peaks.RData")
    load("real_transcripts.RData")
    
    # Get associated peaks
    ap <- associated_peaks(real_peaks, real_transcripts, 'ID')
    
    # Get direct targets
    dt <- direct_targets(real_peaks, real_transcripts, 'ID', 't')
    
    # Save the GRanges results as RDS objects
    saveRDS(ap, "associated_peaks.rds")
    saveRDS(dt, "direct_targets.rds")
    
    # Save the results as CSV tables for easy inspection
    write.csv(as.data.frame(ap), "associated_peaks.csv", row.names = FALSE)
    write.csv(as.data.frame(dt), "direct_targets.csv", row.names = FALSE)
    
    # Set up PDF device for visualization
    pdf("direct_target_plots.pdf", width = 12, height = 4)
    par(mfrow = c(1, 3))
    
    # Show peak distance vs score
    plot(ap\$distance, ap\$peak_score,
         pch = 19, cex = .5, 
         xlab = 'Peak Distance', ylab = 'Peak Score')
    abline(v = 0, lty = 2, col = 'gray')
    
    # Show gene stat vs score
    plot(dt\$stat, dt\$score,
         pch = 19, cex = .5, 
         xlim = c(-35, 35),
         xlab = 'Gene t-stats', ylab = 'Gene Score')
    abline(v = 0, lty = 2, col = 'gray')
    
    # Show gene regulatory potential ecdf
    groups <- c('Down', 'None', 'Up')
    colors <- c('darkgreen', 'gray', 'darkred')
    
    fold_change <- cut(dt\$logFC,
                       breaks = c(min(dt\$logFC), -.5, .5, max(dt\$logFC)),
                       labels = groups)
    
    plot_predictions(dt\$score_rank,
                     fold_change,
                     colors,
                     groups,
                     xlab = 'Gene Regulatory Potential Rank',
                     ylab = 'ECDF')
    
    dev.off()
    
    # Test up-regulated transcripts are not random
    test_up <- test_predictions(dt\$score_rank,
                                group = fold_change,
                                compare = c('Up', 'None'),
                                alternative = 'greater')
    
    # Test down-regulated transcripts are not random
    test_down <- test_predictions(dt\$score_rank,
                                  group = fold_change,
                                  compare = c('Down', 'None'),
                                  alternative = 'greater')
    
    # Save statistical test results to a text file
    sink("statistical_tests.txt")
    cat("=== Up-regulated transcripts vs None ===\n")
    print(test_up)
    cat("\n=== Down-regulated transcripts vs None ===\n")
    print(test_down)
    sink()
    
    # Identify the top regulated transcript, gene name and its associated peaks
    top_trans <- unique(dt\$ID[dt\$rank == min(dt\$rank)])
    top_gene_name <- unique(dt\$name2[dt\$ID == top_trans])
    top_associated_peaks <- unique(ap\$peak_name[ap\$assigned_region == top_trans])
    
    # Save top regulated target information to a text file
    sink("top_regulated_transcript.txt")
    cat("Top regulated transcript ID:\n")
    print(top_trans)
    cat("\nGene name:\n")
    print(top_gene_name)
    cat("\nAssociated peaks:\n")
    print(top_associated_peaks)
    sink()

    writeLines(c(
        '"BIOC_TARGET_DIRECT_TARGET_PREDICTION":',
        paste0('    target: ', as.character(packageVersion('target')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_target_prediction.csv versions.yml
    """
}

workflow BIOC_TARGET_DIRECT_TARGET_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ real_peaks.RData, real_transcripts.RData ] ]

    main:
    BIOC_TARGET_DIRECT_TARGET_PREDICTION(ch_input)

    emit:
    tables   = BIOC_TARGET_DIRECT_TARGET_PREDICTION.out.tables
    plots    = BIOC_TARGET_DIRECT_TARGET_PREDICTION.out.plots
    objects  = BIOC_TARGET_DIRECT_TARGET_PREDICTION.out.objects
    versions = BIOC_TARGET_DIRECT_TARGET_PREDICTION.out.versions
}
