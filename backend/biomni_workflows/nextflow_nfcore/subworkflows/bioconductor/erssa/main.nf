#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ERSSA — erssa_sample_size_analysis
// Perform empirical RNA-seq sample size analysis by subsampling and running differential expression to determine replicate sufficiency.
// Input: count_table, condition_table
// Container: quay.io/biocontainers/bioconductor-erssa:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ERSSA, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the ERSSA package and prepare count and condition tables
//  * 2. [Core Analysis] Set a random seed for reproducible subsampling
//  * 3. [Core Analysis] Run the main erssa function to filter counts, generate subsamples, perform DE analysis, and identify DEGs
//  * 4. [Visualization & Output] Customize and save the resulting diagnostic plots (e.g., dot plot, marginal plot, intersect plot, TPR/FPR plot)

nextflow.enable.dsl = 2

process BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("ERSSA", "ggplot2")
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
        library(ERSSA)
        library(ggplot2)
        
        # ==========================================
        # 1. Load and Prepare Count and Condition Tables
        # ==========================================
        
        # Load count table from the working directory
        if (file.exists("count_table.rds")) {
          count_table = readRDS("count_table.rds")
        } else if (file.exists("count_table.csv")) {
          count_table = read.csv("count_table.csv", row.names = 1, check.names = FALSE)
        } else if (file.exists("count_table.tsv")) {
          count_table = read.delim("count_table.tsv", row.names = 1, check.names = FALSE)
        } else {
          stop("Error: count_table file (RDS, CSV, or TSV) not found in the working directory!")
        }
        
        # Load condition table from the working directory
        if (file.exists("condition_table.rds")) {
          condition_table = readRDS("condition_table.rds")
        } else if (file.exists("condition_table.csv")) {
          condition_table = read.csv("condition_table.csv", check.names = FALSE)
        } else if (file.exists("condition_table.tsv")) {
          condition_table = read.delim("condition_table.tsv", check.names = FALSE)
        } else {
          stop("Error: condition_table file (RDS, CSV, or TSV) not found in the working directory!")
        }
        
        # Ensure standard column names for the condition table
        colnames(condition_table) = c("name", "condition")
        
        # Identify the control condition to use in the ERSSA function call
        unique_conds = unique(condition_table\$condition)
        if (length(unique_conds) >= 1) {
          ctrl_val = unique_conds[1]
        }
        
        # Display preview of the loaded data
        cat("--- Count Table Preview ---\n")
        print(head(count_table[, 1:min(2, ncol(count_table)), drop = FALSE]))
        cat("\n--- Condition Table Preview ---\n")
        print(condition_table)
        cat("\n")
        
        # ==========================================
        # 2. Set Random Seed for Reproducibility
        # ==========================================
        set.seed(1) # for reproducible subsample generation
        
        # ==========================================
        # 3. Run ERSSA Sample Size Analysis
        # ==========================================
        ssa = erssa(count_table, condition_table, DE_ctrl_cond=ctrl_val)
        
        # ==========================================
        # 4. Customize and Save Diagnostic Plots
        # ==========================================
        
        # Parse out plot 1 (Number of DE genes)
        de_plot = ssa\$gg.dotPlot.obj\$gg_object 
        
        # Change y-axis label to be more descriptive
        de_plot = de_plot + ylab('Number of differentially expressed genes')
        
        # Save the plot in the current working directory with new dimensions and a lower resolution.
        ggsave(filename='ERSSA_plot_1_NumOfDEGenes.png',
             plot=de_plot, dpi=100, width = 15,
             height = 10, units = "cm")
        
        # Save other diagnostic plots if they are generated and available in the ssa object
        if (!is.null(ssa\$gg.marginPlot.obj\$gg_object)) {
          ggsave(filename='ERSSA_plot_2_MarginalNumOfDEGenes.png',
                 plot=ssa\$gg.marginPlot.obj\$gg_object, dpi=100, width = 15,
                 height = 10, units = "cm")
        }
        
        if (!is.null(ssa\$gg.intersectPlot.obj\$gg_object)) {
          ggsave(filename='ERSSA_plot_3_IntersectDEGenes.png',
                 plot=ssa\$gg.intersectPlot.obj\$gg_object, dpi=100, width = 15,
                 height = 10, units = "cm")
        }
        
        if (!is.null(ssa\$gg.TPR_FPRPlot.obj\$gg_object)) {
          ggsave(filename='ERSSA_plot_4_FPRvTPRPlot.png',
                 plot=ssa\$gg.TPR_FPRPlot.obj\$gg_object, dpi=100, width = 15,
                 height = 10, units = "cm")
        }
        
        # Save the full ssa results object for downstream analysis
        saveRDS(ssa, file = "ERSSA_ssa_results.rds")
        
        cat("ERSSA pipeline completed successfully. Results and plots saved to the working directory.\n")

    writeLines(c(
        '"BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS":',
        paste0('    ERSSA: ', as.character(packageVersion('ERSSA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_erssa_sample_size_analysis.csv versions.yml
    """
}

workflow BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_table, condition_table ] ]

    main:
    BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.tables
    plots    = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.plots
    objects  = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.objects
    versions = BIOC_ERSSA_ERSSA_SAMPLE_SIZE_ANALYSIS.out.versions
}
