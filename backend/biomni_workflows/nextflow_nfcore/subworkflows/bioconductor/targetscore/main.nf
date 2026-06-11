#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TargetScore — target_score_direct_analysis
// Calculate target scores directly from user-provided log fold-changes and sequence-based scores.
// Input: logFC vector, seqScores matrix
// Container: quay.io/biocontainers/bioconductor-targetscore:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TargetScore
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load TargetScore library
//  * 2. [Input & Preparation] Prepare logFC and sequence scores matrix
//  * 3. [Core Analysis] Run targetScore function to compute posterior probabilities

nextflow.enable.dsl = 2

process BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS {
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
    
    # 1. Load TargetScore library
    library(TargetScore)
    
    # 2. Prepare logFC and sequence scores matrix from user-provided files
    if (!file.exists("logFC.csv") || !file.exists("seqScores.csv")) {
      stop("Error: Required input files 'logFC.csv' and 'seqScores.csv' must be present in the working directory.")
    }
    
    # Read logFC vector
    logFC_data <- read.csv("logFC.csv", header = TRUE)
    if ("logFC" %in% colnames(logFC_data)) {
      logFC <- as.numeric(logFC_data\$logFC)
    } else {
      logFC <- as.numeric(logFC_data[[1]])
    }
    
    # Read seqScores matrix
    seqScores_data <- read.csv("seqScores.csv", header = TRUE)
    seqScores <- as.matrix(seqScores_data)
    
    # Validate dimensions
    if (length(logFC) != nrow(seqScores)) {
      stop(sprintf("Dimension mismatch: logFC has length %d, but seqScores has %d rows.", length(logFC), nrow(seqScores)))
    }
    
    # 3. Run targetScore function to compute posterior probabilities
    p.targetScore <- targetScore(logFC, seqScores, tol=1e-3)
    
    # 4. Write meaningful results to output files
    # Save numerical results as CSV
    results_df <- data.frame(
      logFC = logFC,
      seqScores,
      targetScore = p.targetScore
    )
    write.csv(results_df, "targetScore_results.csv", row.names = FALSE)
    
    # Save RDS object for downstream R analysis
    saveRDS(p.targetScore, "targetScore_results.rds")
    
    # Save pairs plot as PDF
    pdf("targetScore_pairs_plot.pdf", width = 8, height = 8)
    pairs(cbind(p.targetScore, logFC, seqScores))
    dev.off()

    writeLines(c(
        '"BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS":',
        paste0('    TargetScore: ', as.character(packageVersion('TargetScore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_target_score_direct_analysis.csv versions.yml
    """
}

workflow BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ logFC vector, seqScores matrix ] ]

    main:
    BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS.out.tables
    plots    = BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS.out.plots
    objects  = BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS.out.objects
    versions = BIOC_TARGETSCORE_TARGET_SCORE_DIRECT_ANALYSIS.out.versions
}
