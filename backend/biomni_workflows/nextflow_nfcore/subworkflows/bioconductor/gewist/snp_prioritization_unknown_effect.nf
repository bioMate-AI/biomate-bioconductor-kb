#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GEWIST — snp_prioritization_unknown_effect
// Calculate the optimal variance prioritization threshold when the interaction effect size is unknown and modeled via a probability density function (e.g., Weibul
// Input: p, N, theta_c, M, K, nb_incr, range
// Container: quay.io/biocontainers/bioconductor-gewist:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GEWIST
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute the optimal variance prioritization threshold using effectPDF with a specified distribution (e.g., Weibull)

nextflow.enable.dsl = 2

process BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("GEWIST")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(GEWIST)
    
    # Read user inputs from the working directory
    p_val <- scan("p", quiet = TRUE)
    N_val <- scan("N", quiet = TRUE)
    theta_c_val <- scan("theta_c", quiet = TRUE)
    M_val <- scan("M", quiet = TRUE)
    K_val <- scan("K", quiet = TRUE)
    nb_incr_val <- scan("nb_incr", quiet = TRUE)
    range_val <- scan("range", quiet = TRUE)
    
    # Compute the optimal variance prioritization threshold (non-verbose)
    weibull_exp1 <- effectPDF(
      distribution = "weibull", 
      parameter1 = 0.8, 
      parameter2 = 0.3,
      parameter3 = NULL, 
      p = p_val, 
      N = N_val, 
      theta_c = theta_c_val, 
      M = M_val, 
      K = K_val, 
      nb_incr = nb_incr_val, 
      range = range_val, 
      verbose = FALSE
    )
    
    # Compute the optimal variance prioritization threshold (verbose for plotting)
    weibull_exp2 <- effectPDF(
      distribution = "weibull", 
      parameter1 = 0.8, 
      parameter2 = 0.3,
      parameter3 = NULL, 
      p = p_val, 
      N = N_val, 
      theta_c = theta_c_val, 
      M = M_val,
      K = K_val, 
      nb_incr = nb_incr_val, 
      range = range_val, 
      verbose = TRUE
    )
    
    # Save RDS object of the main result
    saveRDS(weibull_exp1, "weibull_exp1.rds")
    
    # Save CSV of the main results
    results_df <- data.frame(
      Conventional_power = weibull_exp1\$Conventional_power,
      Optimal_VP_power = weibull_exp1\$Optimal_VP_power,
      Optimal_pval_threshold = weibull_exp1\$Optimal_pval_threshold
    )
    write.csv(results_df, "optimal_threshold_results.csv", row.names = FALSE)
    
    # Save CSV of the verbose power curve
    write.csv(as.data.frame(weibull_exp2), "verbose_power_results.csv", row.names = FALSE)
    
    # Generate and save the diagnostic plot
    pdf("optimal_threshold_plot.pdf")
    plot(
      weibull_exp2, 
      xlab = "Levene's test p-value threshold",
      ylab = "Expected variance prioritization power", 
      pch = 20
    )
    abline(h = weibull_exp2[, 2][1000], col = "blue")	  
    mtext("Figure 2", cex = 2)      
    dev.off()

    writeLines(c(
        '"BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT":',
        paste0('    GEWIST: ', as.character(packageVersion('GEWIST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_prioritization_unknown_effect.csv versions.yml
    """
}

workflow BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ p, N, theta_c, M, K, nb_incr, range ] ]

    main:
    BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT(ch_input)

    emit:
    tables   = BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT.out.tables
    plots    = BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT.out.plots
    objects  = BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT.out.objects
    versions = BIOC_GEWIST_SNP_PRIORITIZATION_UNKNOWN_EFFECT.out.versions
}
