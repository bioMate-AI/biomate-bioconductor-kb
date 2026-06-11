#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: censcyt — censored_da_step_by_step
// Perform differential abundance analysis with a censored covariate step-by-step using pre-calculated cluster counts.
// Input: d_counts, experiment_info
// Container: quay.io/biocontainers/bioconductor-censcyt:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SummarizedExperiment, censcyt, ggplot2, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Set up metadata and design formula using createFormula with an event indicator
//  * 2. [Input & Preparation] Define the contrast matrix
//  * 3. [Core Analysis] Run differential testing using testDA_censoredGLMM with multiple imputation
//  * 4. [Core Analysis] Extract top results using topTable

nextflow.enable.dsl = 2

process BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    suppressPackageStartupMessages({
      library(censcyt)
      library(BiocParallel)
    })
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read experiment_info (data.frame containing sample IDs, observed covariate values, and event indicators)
    if (file.exists("experiment_info.csv")) {
      experiment_info <- read.csv("experiment_info.csv", stringsAsFactors = FALSE)
    } else if (file.exists("experiment_info.rds")) {
      experiment_info <- readRDS("experiment_info.rds")
    } else {
      stop("Required input file 'experiment_info.csv' or 'experiment_info.rds' not found in the working directory.")
    }
    
    # Read d_counts (SummarizedExperiment containing cluster cell counts per sample)
    if (file.exists("d_counts.rds")) {
      d_counts <- readRDS("d_counts.rds")
    } else {
      stop("Required input file 'd_counts.rds' not found in the working directory.")
    }
    
    # ==========================================
    # 2. DIFFERENTIAL ABUNDANCE ANALYSIS PIPELINE
    # ==========================================
    
    # Stage 1: Set up metadata and design formula using createFormula with an event indicator
    da_formula <- createFormula(experiment_info = experiment_info,
                                cols_fixed = "X_obs",
                                cols_random = "sample_id",
                                event_indicator = "Event_ind")
    
    # Stage 2: Define the contrast matrix
    contrast <- matrix(c(0,1))
    
    # Stage 3: Run differential testing using testDA_censoredGLMM with multiple imputation
    da_out <- testDA_censoredGLMM(d_counts = d_counts,
                                  formula = da_formula,
                                  contrast = contrast,
                                  mi_reps = 30,
                                  imputation_method = "km",
                                  verbose = TRUE,
                                  BPPARAM=BiocParallel::MulticoreParam(workers = 1))
    
    # Stage 4: Extract top results using topTable
    da_results <- topTable(da_out)
    
    # ==========================================
    # 3. WRITE OUTPUT FILES
    # ==========================================
    
    # Save the full differential testing output object
    saveRDS(da_out, file = "da_out.rds")
    
    # Save the top results table as a CSV file
    write.csv(as.data.frame(da_results), file = "da_results.csv", row.names = FALSE)
    
    # Optional: Generate and save diagnostic plot of relative cell population abundance
    tryCatch({
      library(ggplot2)
      library(tidyr)
      
      # Convert counts to proportions
      proportion <- as.data.frame(t(apply(assay(d_counts), 2, function(x) x / sum(x))))
      nr_clusters <- ncol(proportion)
      names(proportion) <- paste0("Cluster_", names(proportion))
      
      # Convert to long format for plotting
      counts_long <- pivot_longer(proportion, 
                                  cols = seq_len(nr_clusters), 
                                  names_to = "cluster_id", 
                                  values_to = "proportion")
      
      # Add observed covariate and event indicator
      counts_long\$X_obs <- rep(experiment_info\$X_obs, each = nr_clusters)
      counts_long\$Event_ind <- factor(rep(experiment_info\$Event_ind, each = nr_clusters),
                                      levels = c(0, 1),
                                      labels = c("censored", "observed"))
      
      p <- ggplot(counts_long) +
        geom_point(aes(x = X_obs, y = proportion, color = Event_ind)) +
        facet_wrap(~cluster_id) +
        theme_bw() +
        labs(title = "Relative Cell Population Abundance vs. Covariate",
             x = "Observed Covariate (X_obs)",
             y = "Proportion")
      
      ggsave("da_abundance_plot.pdf", plot = p, width = 8, height = 6)
    }, error = function(e) {
      message("Could not generate diagnostic plot: ", e\$message)
    })
    
    message("Pipeline completed successfully. Outputs saved to 'da_out.rds' and 'da_results.csv'.")

    writeLines(c(
        '"BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP":',
        paste0('    censcyt: ', as.character(packageVersion('censcyt')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_censored_da_step_by_step.csv versions.yml
    """
}

workflow BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ d_counts, experiment_info ] ]

    main:
    BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP(ch_input)

    emit:
    tables   = BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP.out.tables
    plots    = BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP.out.plots
    objects  = BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP.out.objects
    versions = BIOC_CENSCYT_CENSORED_DA_STEP_BY_STEP.out.versions
}
