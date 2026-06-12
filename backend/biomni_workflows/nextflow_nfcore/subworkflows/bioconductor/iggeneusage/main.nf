#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IgGeneUsage — differential_gene_usage_analysis
// Detect differential gene usage (DGU) between biological conditions using a Bayesian zero-inflated beta-binomial model.
// Input: data.frame
// Container: quay.io/biocontainers/bioconductor-iggeneusage:1.24.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IgGeneUsage, ggplot2, ggrepel, patchwork, reshape2, rstan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the differential gene usage analysis using DGU()
//  * 2. [Visualization & Output] Inspect the model fit and check MCMC diagnostics using summary() and rstan::check_hmc_diagnostics()
//  * 3. [Visualization & Output] Extract and visualize results such as condition-specific gene usage (gu), differential gene usage (dgu), and posterior predictive 

nextflow.enable.dsl = 2

process BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("IgGeneUsage", "rstan", "ggplot2", "ggrepel", "patchwork", "reshape2")
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
    
    # Load required libraries
    library(IgGeneUsage)
    library(rstan)
    library(ggplot2)
    library(ggrepel)
    library(patchwork)
    library(reshape2)
    
    # ==========================================
    # 1. Read User Input Data
    # ==========================================
    # The pipeline expects a CSV file named 'gene_usage_data.csv' in the working directory.
    # This file must contain columns: individual_id, condition, gene_name, gene_usage_count,
    # and optionally replicate.
    input_file <- "gene_usage_data.csv"
    
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file '", input_file, "' not found in the working directory. Please provide this file to run the pipeline.", sep = ""))
    }
    
    # Read the user-provided data frame
    user_data <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Validate required columns
    required_cols <- c("individual_id", "condition", "gene_name", "gene_usage_count")
    missing_cols <- setdiff(required_cols, colnames(user_data))
    if (length(missing_cols) > 0) {
      stop(paste("Error: Input data is missing required columns:", paste(missing_cols, collapse = ", ")))
    }
    
    # Ensure correct data types
    user_data\$individual_id <- as.character(user_data\$individual_id)
    user_data\$condition <- as.character(user_data\$condition)
    user_data\$gene_name <- as.character(user_data\$gene_name)
    user_data\$gene_usage_count <- as.numeric(user_data\$gene_usage_count)
    if ("replicate" %in% colnames(user_data)) {
      user_data\$replicate <- as.character(user_data\$replicate)
    }
    
    # ==========================================
    # 2. Run Differential Gene Usage Analysis
    # ==========================================
    # Run the Bayesian zero-inflated beta-binomial model using DGU()
    # Faithful reproduction of documented function call and arguments:
    M <- DGU(ud = user_data, # input data
             mcmc_warmup = 300, # how many MCMC warm-ups per chain (default: 500)
             mcmc_steps = 1500, # how many MCMC steps per chain (default: 1,500)
             mcmc_chains = 3, # how many MCMC chain to run (default: 4)
             mcmc_cores = 1, # how many PC cores to use? (e.g. parallel chains)
             hdi_lvl = 0.95, # highest density interval level (de fault: 0.95)
             adapt_delta = 0.8, # MCMC target acceptance rate (default: 0.95)
             max_treedepth = 10) # tree depth evaluated at each step (default: 12)
    
    # Save the complete model object
    saveRDS(M, file = "dgu_model_fit.rds")
    
    # ==========================================
    # 3. Inspect Model Fit & MCMC Diagnostics
    # ==========================================
    # Redirect console diagnostic outputs to a text file
    sink("mcmc_diagnostics_summary.txt")
    
    cat("=== MODEL SUMMARY ===\n")
    print(summary(M))
    
    cat("\n=== HMC DIAGNOSTICS ===\n")
    rstan::check_hmc_diagnostics(M\$fit)
    
    sink()
    
    # Print to standard output as well
    summary(M)
    rstan::check_hmc_diagnostics(M\$fit)
    
    # ==========================================
    # 4. Extract and Export Results
    # ==========================================
    # Export tabular results to CSV files
    write.csv(M\$dgu, file = "dgu_results.csv", row.names = FALSE)
    write.csv(M\$dgu_prob, file = "dgu_prob_results.csv", row.names = FALSE)
    write.csv(M\$gu, file = "gu_results.csv", row.names = FALSE)
    write.csv(M\$theta, file = "theta_results.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Visualization
    # ==========================================
    pdf("gene_usage_analysis_plots.pdf", width = 8, height = 6)
    
    # Plot 1: Observed Gene Usage Counts
    p1 <- ggplot(data = user_data) +
      geom_point(aes(x = gene_name, y = gene_usage_count, col = condition),
                 position = position_dodge(width = .7), shape = 21) +
      theme_bw(base_size = 11) +
      ylab(label = "Gene usage [count]") +
      xlab(label = '') +
      theme(legend.position = "top") +
      theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.4)) +
      ggtitle("Observed Gene Usage Counts")
    print(p1)
    
    # Plot 2: Repertoire-specific Posterior Predictive Checks (PPC)
    p2 <- ggplot(data = M\$ppc\$ppc_rep) +
      facet_wrap(facets = ~individual_id, ncol = 5) +
      geom_abline(intercept = 0, slope = 1, linetype = "dashed", col = "darkgray") +
      geom_errorbar(aes(x = observed_count, y = ppc_mean_count, 
                        ymin = ppc_L_count, ymax = ppc_H_count), col = "darkgray") +
      geom_point(aes(x = observed_count, y = ppc_mean_count), size = 1) +
      theme_bw(base_size = 11) +
      theme(legend.position = "top") +
      xlab(label = "Observed usage [counts]") +
      ylab(label = "PPC usage [counts]") +
      ggtitle("Repertoire-specific PPC")
    print(p2)
    
    # Plot 3: Overall Condition-specific PPC
    p3 <- ggplot(data = M\$ppc\$ppc_condition) +
      geom_errorbar(aes(x = gene_name, ymin = ppc_L_prop*100, 
                        ymax = ppc_H_prop*100, col = condition), 
                    position = position_dodge(width = 0.65), width = 0.1) +
      geom_point(aes(x = gene_name, y = ppc_mean_prop*100, col = condition), 
                 position = position_dodge(width = 0.65)) +
      theme_bw(base_size = 11) +
      theme(legend.position = "top") +
      xlab(label = "Observed usage [%]") +
      ylab(label = "PPC usage [%]") +
      theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.4)) +
      ggtitle("Overall Condition-specific PPC")
    print(p3)
    
    # Plot 4: Differential Gene Usage (DGU) Effect Size vs Probability
    stats <- M\$dgu
    stats <- stats[order(abs(stats\$es_mean), decreasing = FALSE), ]
    stats\$gene_fac <- factor(x = stats\$gene_name, levels = unique(stats\$gene_name))
    
    p4 <- ggplot(data = stats) +
      geom_hline(yintercept = 0, linetype = "dashed", col = "gray") +
      geom_errorbar(aes(x = pmax, y = es_mean, ymin = es_L, ymax = es_H), 
                    col = "darkgray") +
      geom_point(aes(x = pmax, y = es_mean, col = contrast)) +
      theme_bw(base_size = 11) +
      theme(legend.position = "top") +
      xlab(label = expression(pi)) +
      xlim(c(0, 1)) +
      ylab(expression(gamma)) +
      ggtitle("DGU Effect Size vs Probability")
    
    # Add labels for promising hits if they exist
    if (any(stats\$pmax >= 0.95)) {
      p4 <- p4 + geom_text_repel(data = stats[stats\$pmax >= 0.95, ],
                                aes(x = pmax, y = es_mean, label = gene_fac),
                                min.segment.length = 0, size = 2.75)
    }
    print(p4)
    
    # Plot 5: Promising Hits (PPC Usage % for top genes)
    promising_genes <- stats\$gene_name[stats\$pmax >= 0.95]
    if (length(promising_genes) == 0) {
      # Fallback to top 3 genes by effect size if no genes meet the 0.95 threshold
      promising_genes <- head(stats\$gene_name, 3)
    }
    
    if (length(promising_genes) > 0) {
      ppc_gene <- M\$ppc\$ppc_condition
      ppc_gene <- ppc_gene[ppc_gene\$gene_name %in% promising_genes, ]
    
      ppc_rep <- M\$ppc\$ppc_rep
      ppc_rep <- ppc_rep[ppc_rep\$gene_name %in% promising_genes, ]
    
      p5 <- ggplot() +
        geom_point(data = ppc_rep,
                   aes(x = gene_name, y = observed_prop*100, col = condition),
                   size = 1, fill = "black",
                   position = position_jitterdodge(jitter.width = 0.1, 
                                                   jitter.height = 0, 
                                                   dodge.width = 0.35)) +
        geom_errorbar(data = ppc_gene, 
                      aes(x = gene_name, ymin = ppc_L_prop*100, 
                          ymax = ppc_H_prop*100, group = condition),
                      position = position_dodge(width = 0.35), width = 0.15) +
        theme_bw(base_size = 11) +
        theme(legend.position = "top") +
        theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.4)) +
        ylab(label = "PPC usage [%]") +
        xlab(label = '') +
        ggtitle("Promising Hits (PPC Usage %)")
      print(p5)
    }
    
    # Plot 6: Gene Usage (GU) Summary Probability
    p6 <- ggplot(data = M\$gu) +
      geom_errorbar(aes(x = gene_name, y = prob_mean, ymin = prob_L,
                        ymax = prob_H, col = condition),
                    width = 0.1, position = position_dodge(width = 0.4)) +
      geom_point(aes(x = gene_name, y = prob_mean, col = condition), size = 1,
                 position = position_dodge(width = 0.4)) +
      theme_bw(base_size = 11) +
      theme(legend.position = "top") +
      ylab(label = "GU [probability]") +
      theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.4)) +
      ggtitle("Inferred Gene Usage Probability")
    print(p6)
    
    dev.off()
    
    cat("\nPipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS":',
        paste0('    IgGeneUsage: ', as.character(packageVersion('IgGeneUsage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_gene_usage_analysis.csv versions.yml
    """
}

workflow BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.frame ] ]

    main:
    BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS.out.tables
    plots    = BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS.out.plots
    objects  = BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS.out.objects
    versions = BIOC_IGGENEUSAGE_DIFFERENTIAL_GENE_USAGE_ANALYSIS.out.versions
}
