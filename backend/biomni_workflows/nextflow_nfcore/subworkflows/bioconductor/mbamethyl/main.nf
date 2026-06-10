#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBAmethyl — dna_methylation_smoothing
// Smooth raw DNA methylation beta values across neighboring probes and biological replicates using a group fused lasso model.
// Input: methylation_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mbamethyl:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MBAmethyl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the MBAmethyl package
//  * 2. [Core Analysis] Run the smoothing algorithm on the raw methylation matrix
//  * 3. [Core Analysis] Inspect and extract the smoothed methylation values using the BIC model selection criterion

nextflow.enable.dsl = 2

process BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    
    # Check for required input file
    if (!file.exists("methylation_matrix.csv")) {
      stop("Error: 'methylation_matrix.csv' is required but was not found in the working directory.")
    }
    
    # Load input data
    # The input is expected to be a p x n matrix of raw methylation beta values
    # where rows represent neighboring probes and columns represent biological samples.
    Y_df <- read.csv("methylation_matrix.csv", row.names = 1, check.names = FALSE)
    Y <- as.matrix(Y_df)
    
    # 1. Load the MBAmethyl package
    library(MBAmethyl)
    
    # 2. Run the smoothing algorithm on the raw methylation matrix
    fit <- MBAmethyl(Y, steps = 30)
    
    # 3. Inspect and extract the smoothed methylation values using the BIC model selection criterion
    str(fit\$ans.bic)
    theta <- fit\$ans.bic
    
    # Save outputs
    # Save the full fit object
    saveRDS(fit, file = "mbamethyl_fit.rds")
    
    # Extract the smoothed methylation values (theta\$theta) and probe effects (theta\$phi)
    smoothed_beta <- theta\$theta
    rownames(smoothed_beta) <- rownames(Y)
    colnames(smoothed_beta) <- colnames(Y)
    
    write.csv(smoothed_beta, file = "smoothed_methylation.csv", row.names = TRUE)
    
    # Save probe effects
    probe_effects <- data.frame(
      Probe = rownames(Y),
      Phi = theta\$phi
    )
    write.csv(probe_effects, file = "probe_effects.csv", row.names = FALSE)
    
    # Save summary statistics
    summary_stats <- data.frame(
      Metric = c("change.p", "rss", "df.bic"),
      Value = c(paste(theta\$change.p, collapse = ","), theta\$rss, theta\$df.bic)
    )
    write.csv(summary_stats, file = "bic_summary_statistics.csv", row.names = FALSE)
    
    # Generate a diagnostic plot comparing raw and smoothed values for the first sample
    pdf("methylation_smoothing_plot.pdf", width = 8, height = 6)
    plot(Y[, 1], type = "p", col = "grey", pch = 16, 
         main = "Raw vs Smoothed Methylation (Sample 1)",
         xlab = "Probe Index", ylab = "Beta Value", ylim = c(0, 1))
    lines(smoothed_beta[, 1], col = "red", lwd = 2)
    legend("topright", legend = c("Raw", "Smoothed (BIC)"), 
           col = c("grey", "red"), pch = c(16, NA), lty = c(NA, 1), lwd = c(NA, 2))
    dev.off()

    writeLines(c(
        '"BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING":',
        paste0('    MBAmethyl: ', as.character(packageVersion('MBAmethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_methylation_smoothing.csv versions.yml
    """
}

workflow BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methylation_matrix.csv ] ]

    main:
    BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING(ch_input)

    emit:
    tables   = BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING.out.tables
    plots    = BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING.out.plots
    objects  = BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING.out.objects
    versions = BIOC_MBAMETHYL_DNA_METHYLATION_SMOOTHING.out.versions
}
