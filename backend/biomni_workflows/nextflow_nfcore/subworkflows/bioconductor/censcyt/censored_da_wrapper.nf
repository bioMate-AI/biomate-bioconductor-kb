#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: censcyt — censored_da_wrapper
// Perform the complete differential abundance analysis workflow (clustering and testing) from raw expression data using the censcyt wrapper.
// Input: d_input, experiment_info, marker_info
// Container: quay.io/biocontainers/bioconductor-censcyt:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SummarizedExperiment, censcyt, ggplot2, tidyr
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Set up metadata and design formula using createFormula with an event indicator
//  * 2. [Input & Preparation] Define the contrast matrix
//  * 3. [Core Analysis] Run the all-in-one wrapper function censcyt to cluster cells and perform differential testing
//  * 4. [Visualization & Output] Extract top results using topTable and plot results using plotHeatmap

nextflow.enable.dsl = 2

process BIOC_CENSCYT_CENSORED_DA_WRAPPER {
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
          library(ggplot2)
          library(tidyr)
          library(BiocParallel)
        })
        
        # 1. Read User Inputs from the working directory
        if (!file.exists("experiment_info.csv")) {
          stop("Error: 'experiment_info.csv' not found in the working directory.")
        }
        if (!file.exists("marker_info.csv")) {
          stop("Error: 'marker_info.csv' not found in the working directory.")
        }
        if (!file.exists("d_input.rds")) {
          stop("Error: 'd_input.rds' not found in the working directory.")
        }
        
        experiment_info <- read.csv("experiment_info.csv", stringsAsFactors = FALSE)
        marker_info <- read.csv("marker_info.csv", stringsAsFactors = FALSE)
        
        # Ensure marker_class is a factor with correct levels as required by censcyt/diffcyt
        if ("marker_class" %in% colnames(marker_info)) {
          marker_info\$marker_class <- factor(marker_info\$marker_class, levels = c("type", "state", "none"))
        }
        
        d_input <- readRDS("d_input.rds")
        
        # Define X_true for the plotHeatmap sample_order argument.
        # If X_true is not present in experiment_info, fallback to X_obs.
        X_true <- if ("X_true" %in% colnames(experiment_info)) {
          experiment_info\$X_true
        } else {
          experiment_info\$X_obs
        }
        
        # 2. Set up formula and contrast
        da_formula <- createFormula(experiment_info = experiment_info,
                                    cols_fixed = "X_obs",
                                    cols_random = "sample_id",
                                    event_indicator = "Event_ind")
        
        # also create contrast matrix for testing
        contrast <- matrix(c(0,1))
        
        # 3. Run wrapper function
        out_DA <- censcyt(d_input, 
                          experiment_info, 
                          marker_info,
                          formula = da_formula, 
                          contrast = contrast,
                          meta_clustering = TRUE, 
                          meta_k = 10,
                          seed_clustering = 123, 
                          verbose = FALSE, 
                          mi_reps = 10,
                          imputation_method = "km",
                          BPPARAM=BiocParallel::MulticoreParam(workers = 1))
        
        # 4. Extract and save results
        # Display and save results for top DA clusters
        da_results <- topTable(out_DA, format_vals = TRUE)
        write.csv(as.data.frame(da_results), "top_DA_clusters.csv", row.names = FALSE)
        
        # Save the full output object
        saveRDS(out_DA, "out_DA.rds")
        
        # Plot heatmap for DA tests and save to PDF
        pdf("DA_heatmap.pdf", width = 10, height = 8)
        print(plotHeatmap(out_DA, 
                    analysis_type = "DA", 
                    sample_order = order(X_true)))
        dev.off()

    writeLines(c(
        '"BIOC_CENSCYT_CENSORED_DA_WRAPPER":',
        paste0('    censcyt: ', as.character(packageVersion('censcyt')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_censored_da_wrapper.csv versions.yml
    """
}

workflow BIOC_CENSCYT_CENSORED_DA_WRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ d_input, experiment_info, marker_info ] ]

    main:
    BIOC_CENSCYT_CENSORED_DA_WRAPPER(ch_input)

    emit:
    tables   = BIOC_CENSCYT_CENSORED_DA_WRAPPER.out.tables
    plots    = BIOC_CENSCYT_CENSORED_DA_WRAPPER.out.plots
    objects  = BIOC_CENSCYT_CENSORED_DA_WRAPPER.out.objects
    versions = BIOC_CENSCYT_CENSORED_DA_WRAPPER.out.versions
}
