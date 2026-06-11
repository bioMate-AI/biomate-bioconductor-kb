#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mnem — continuous_log_odds_pipeline
// Perform simultaneous causal network inference and cell subpopulation clustering on continuous log odds single-cell perturbation data, including model selection 
// Input: data.csv
// Container: quay.io/biocontainers/bioconductor-mnem:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mnem
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform model selection across multiple component sizes (k) using mnemk
//  * 2. [Visualization & Output] Plot the mixture NEM result for the best model using plot
//  * 3. [Core Analysis] Evaluate model selection criteria (raw vs penalized log likelihood)
//  * 4. [Visualization & Output] Check EM convergence using plotConvergence
//  * 5. [Visualization & Output] Calculate and plot cell responsibilities (affinities) using getAffinity

nextflow.enable.dsl = 2

process BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE {
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
    
    # Load required library
    library(mnem)
    
    # Read input data
    if (!file.exists("data.csv")) {
      stop("Error: 'data.csv' not found in the working directory.")
    }
    
    data_df <- read.csv("data.csv", row.names = 1, check.names = FALSE)
    data <- as.matrix(data_df)
    
    # 1. Perform model selection across multiple component sizes (k) using mnemk
    starts <- 5
    bestk <- mnemk(data, ks = 1:5, search = "greedy", starts = starts,
                           parallel = NULL)
    
    # Save the best model object
    saveRDS(bestk, "bestk_model.rds")
    
    # 2. Plot the mixture NEM result for the best model using plot
    pdf("best_mixture_nem_plot.pdf", width = 10, height = 8)
    plot(bestk\$best)
    dev.off()
    
    # 3. Evaluate model selection criteria (raw vs penalized log likelihood)
    pdf("model_selection_plots.pdf", width = 10, height = 5)
    par(mfrow=c(1,2)) 
    plot(bestk\$lls, col = "blue", main = "raw log likelihood", type = "b",
         xlab = "number of components", ylab = "score")
    plot(bestk\$ics, col = "red", main = "penalized log likelihood", type = "b",
         xlab = "number of components", ylab = "score")
    dev.off()
    
    # 4. Check EM convergence using plotConvergence
    pdf("em_convergence_plots.pdf", width = 8, height = 8)
    par(mfrow=c(2,2))
    plotConvergence(bestk\$best, cex.main = 0.7, cex.lab = 0.7)
    dev.off()
    
    # 5. Calculate and plot cell responsibilities (affinities) using getAffinity
    postprobs <- getAffinity(bestk\$best\$probs, mw = bestk\$best\$mw)
    
    # Save responsibilities to CSV
    write.csv(postprobs, "cell_responsibilities.csv", row.names = TRUE)
    
    # Plot responsibilities histogram
    pdf("responsibilities_histogram.pdf", width = 6, height = 6)
    hist(postprobs, xlab = "responsibilities", main = "")
    dev.off()

    writeLines(c(
        '"BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE":',
        paste0('    mnem: ', as.character(packageVersion('mnem')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_continuous_log_odds_pipeline.csv versions.yml
    """
}

workflow BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.csv ] ]

    main:
    BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE.out.tables
    plots    = BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE.out.plots
    objects  = BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE.out.objects
    versions = BIOC_MNEM_CONTINUOUS_LOG_ODDS_PIPELINE.out.versions
}
