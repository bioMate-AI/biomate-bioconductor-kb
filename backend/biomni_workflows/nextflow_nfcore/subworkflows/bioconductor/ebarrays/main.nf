#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBarrays — empirical_bayes_de_analysis
// Identify differentially expressed genes and patterns across multiple conditions using empirical Bayes models and perform diagnostic checks.
// Input: gould
// Container: quay.io/biocontainers/bioconductor-ebarrays:2.74.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBarrays
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the dataset and define expression patterns using ebPatterns. 2. Fit the Gamma-Gamma (GG), Lognormal-Normal (LNN), or Lognorma

nextflow.enable.dsl = 2

process BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS {
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
    library(EBarrays)
    
    # 1. Load the dataset from the working directory
    # The pipeline expects a file named 'gould' (or 'gould.rds' / 'gould.csv') in the working directory.
    if (file.exists("gould.rds")) {
      gould <- readRDS("gould.rds")
    } else if (file.exists("gould.csv")) {
      gould <- as.matrix(read.csv("gould.csv", row.names = 1))
    } else if (file.exists("gould")) {
      gould <- tryCatch({
        readRDS("gould")
      }, error = function(e) {
        tryCatch({
          as.matrix(read.table("gould", header = TRUE, row.names = 1))
        }, error = function(e2) {
          stop("Failed to read 'gould' as RDS or table. Please ensure it is a valid matrix or ExpressionSet.")
        })
      })
    } else {
      stop("Input file 'gould' (or gould.rds/gould.csv) not found in the working directory.")
    }
    
    # 2. Define expression patterns
    pattern <- ebPatterns(c("1,1,1,0,0,0,0,0,0,0", "1,2,2,0,0,0,0,0,0,0"))
    
    # 3. Fit Gamma-Gamma (GG) model and calculate posterior probabilities
    gg.em.out <- emfit(gould, family = "GG", hypotheses = pattern, 
                       num.iter = 10)
    gg.post.out <- postprob(gg.em.out, gould)\$pattern
    gg.threshold <- crit.fun(gg.post.out[, 1], 0.05)
    gg.de.count <- sum(gg.post.out[, 2] > gg.threshold)
    
    # 4. Fit Lognormal-Normal (LNN) model and calculate posterior probabilities
    lnn.em.out <- emfit(gould, family = "LNN", hypotheses = pattern, 
                        num.iter = 10)
    lnn.post.out <- postprob(lnn.em.out, gould)\$pattern
    lnn.threshold <- crit.fun(lnn.post.out[, 1], 0.05)
    lnn.de.count <- sum(lnn.post.out[, 2] > lnn.threshold)
    
    # 5. Fit Lognormal-Normal with Modified Variance (LNNMV) model and calculate posterior probabilities
    lnnmv.em.out <- emfit(gould, family = "LNNMV", hypotheses = pattern, 
                          groupid = c(1,2,2,0,0,0,0,0,0,0), num.iter = 10)
    lnnmv.post.out <- postprob(lnnmv.em.out, gould, 
                               groupid = c(1,2,2,0,0,0,0,0,0,0))\$pattern
    lnnmv.threshold <- crit.fun(lnnmv.post.out[, 1], 0.05)
    lnnmv.de.count <- sum(lnnmv.post.out[, 2] > lnnmv.threshold)
    
    # 6. Perform diagnostic checks and save plots to a PDF
    pdf("diagnostic_plots.pdf", width = 8, height = 8)
    
    # Constant CV check
    checkCCV(gould[, 1:3])
    
    # Model assumption checks (QQ plots)
    print(checkModel(gould, gg.em.out, model = "gamma", nb = 50))
    print(checkModel(gould, lnn.em.out, model = "lognormal", nb = 50))
    print(checkModel(gould, lnnmv.em.out, model = "lnnmv", nb = 50,
                     groupid = c(1,2,2,0,0,0,0,0,0,0)))
    
    # Marginal density plots
    print(plotMarginal(gg.em.out, gould))
    print(plotMarginal(lnn.em.out, gould))
    
    # Variance prior checks for LNNMV
    print(checkVarsQQ(gould, groupid = c(1,2,2,0,0,0,0,0,0,0)))
    print(checkVarsMar(gould, groupid = c(1,2,2,0,0,0,0,0,0,0), 
                       nint = 2000, xlim = c(-0.1, 0.5)))
    
    dev.off()
    
    # 7. Save outputs to files
    # Save posterior probabilities
    write.csv(gg.post.out, "gg_posterior_probabilities.csv", row.names = TRUE)
    write.csv(lnn.post.out, "lnn_posterior_probabilities.csv", row.names = TRUE)
    write.csv(lnnmv.post.out, "lnnmv_posterior_probabilities.csv", row.names = TRUE)
    
    # Save fitted model objects
    saveRDS(list(gg = gg.em.out, lnn = lnn.em.out, lnnmv = lnnmv.em.out), "ebarrays_models_fit.rds")
    
    # Save summary statistics
    summary_conn <- file("summary_stats.txt", "w")
    cat("GG Model Threshold (FDR 0.05):", gg.threshold, "\n", file = summary_conn)
    cat("GG Model DE Genes Count:", gg.de.count, "\n\n", file = summary_conn)
    cat("LNN Model Threshold (FDR 0.05):", lnn.threshold, "\n", file = summary_conn)
    cat("LNN Model DE Genes Count:", lnn.de.count, "\n\n", file = summary_conn)
    cat("LNNMV Model Threshold (FDR 0.05):", lnnmv.threshold, "\n", file = summary_conn)
    cat("LNNMV Model DE Genes Count:", lnnmv.de.count, "\n", file = summary_conn)
    close(summary_conn)

    writeLines(c(
        '"BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS":',
        paste0('    EBarrays: ', as.character(packageVersion('EBarrays')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_empirical_bayes_de_analysis.csv versions.yml
    """
}

workflow BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gould ] ]

    main:
    BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS.out.tables
    plots    = BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS.out.plots
    objects  = BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS.out.objects
    versions = BIOC_EBARRAYS_EMPIRICAL_BAYES_DE_ANALYSIS.out.versions
}
