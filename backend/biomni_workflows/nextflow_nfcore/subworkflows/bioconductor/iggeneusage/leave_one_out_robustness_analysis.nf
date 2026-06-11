#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IgGeneUsage — leave_one_out_robustness_analysis
// Assert the robustness of the probability of DGU (pi) and the effect size (gamma) by performing a fully Bayesian leave-one-out (LOO) analysis.
// Input: data.frame
// Container: quay.io/biocontainers/bioconductor-iggeneusage:1.24.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IgGeneUsage, ggplot2, rstan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the leave-one-out analysis using LOO()
//  * 2. [Core Analysis] Extract and combine the gene usage (gu) and differential gene usage (dgu) results from each LOO iteration
//  * 3. [Visualization & Output] Visualize the variability of effect size (gamma), probability of DGU (pi), and gene usage across iterations

nextflow.enable.dsl = 2

process BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS {
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
    library(IgGeneUsage)
    library(rstan)
    library(ggplot2)
    
    # Define input file path
    input_file <- "gene_usage_data.csv"
    
    # Assert existence of the user input file
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file '", input_file, "' not found in the working directory.", sep = ""))
    }
    
    # Read the user input data
    ud_data <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Validate required columns
    required_cols <- c("individual_id", "condition", "gene_name", "gene_usage_count")
    missing_cols <- setdiff(required_cols, colnames(ud_data))
    if (length(missing_cols) > 0) {
      stop(paste("Error: Input data is missing required columns: ", paste(missing_cols, collapse = ", "), sep = ""))
    }
    
    # Run the leave-one-out (LOO) analysis using the documented function call
    L <- LOO(ud = ud_data, # input data
             mcmc_warmup = 500, # how many MCMC warm-ups per chain (default: 500)
             mcmc_steps = 1000, # how many MCMC steps per chain (default: 1,500)
             mcmc_chains = 1, # how many MCMC chain to run (default: 4)
             mcmc_cores = 1, # how many PC cores to use? (e.g. parallel chains)
             hdi_lvl = 0.95, # highest density interval level (de fault: 0.95)
             adapt_delta = 0.8, # MCMC target acceptance rate (default: 0.95)
             max_treedepth = 10) # tree depth evaluated at each step (default: 12)
    
    # Extract and combine the gene usage (gu) and differential gene usage (dgu) results
    L_gu <- do.call(rbind, lapply(X = L, FUN = function(x){return(x\$gu)}))
    L_dgu <- do.call(rbind, lapply(X = L, FUN = function(x){return(x\$dgu)}))
    
    # Save the extracted tables and the raw LOO object
    write.csv(L_gu, "loo_gene_usage.csv", row.names = FALSE)
    write.csv(L_dgu, "loo_differential_gene_usage.csv", row.names = FALSE)
    saveRDS(L, "loo_results.rds")
    
    # Visualize the variability of effect size (gamma), probability of DGU (pi), and gene usage
    pdf("loo_analysis_plots.pdf", width = 8, height = 6)
    
    # Plot 1: LOO-DGU: variability of effect size (gamma)
    p1 <- ggplot(data = L_dgu)+
      facet_wrap(facets = ~contrast, ncol = 1)+
      geom_hline(yintercept = 0, linetype = "dashed", col = "gray")+
      geom_errorbar(aes(x = gene_name, y = es_mean, ymin = es_L,
                        ymax = es_H, col = contrast, group = loo_id),
                    width = 0.1, position = position_dodge(width = 0.75))+
      geom_point(aes(x = gene_name, y = es_mean, col = contrast,
                     group = loo_id), size = 1,
                 position = position_dodge(width = 0.75))+
      theme_bw(base_size = 11)+
      theme(legend.position = "none")+
      ylab(expression(gamma))
    print(p1)
    
    # Plot 2: LOO-DGU: variability of pi
    p2 <- ggplot(data = L_dgu)+
      facet_wrap(facets = ~contrast, ncol = 1)+
      geom_point(aes(x = gene_name, y = pmax, col = contrast,
                     group = loo_id), size = 1,
                 position = position_dodge(width = 0.5))+
      theme_bw(base_size = 11)+
      theme(legend.position = "none")+
      ylab(expression(pi))
    print(p2)
    
    # Plot 3: LOO-GU: variability of the gene usage
    p3 <- ggplot(data = L_gu)+
      geom_hline(yintercept = 0, linetype = "dashed", col = "gray")+
      geom_errorbar(aes(x = gene_name, y = prob_mean, ymin = prob_L,
                        ymax = prob_H, col = condition, 
                        group = interaction(loo_id, condition)),
                    width = 0.1, position = position_dodge(width = 1))+
      geom_point(aes(x = gene_name, y = prob_mean, col = condition,
                     group = interaction(loo_id, condition)), size = 1,
                 position = position_dodge(width = 1))+
      theme_bw(base_size = 11)+
      theme(legend.position = "top")+
      ylab("GU [probability]")+
      theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.4))
    print(p3)
    
    dev.off()

    writeLines(c(
        '"BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS":',
        paste0('    IgGeneUsage: ', as.character(packageVersion('IgGeneUsage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_leave_one_out_robustness_analysis.csv versions.yml
    """
}

workflow BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.frame ] ]

    main:
    BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS.out.tables
    plots    = BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS.out.plots
    objects  = BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS.out.objects
    versions = BIOC_IGGENEUSAGE_LEAVE_ONE_OUT_ROBUSTNESS_ANALYSIS.out.versions
}
