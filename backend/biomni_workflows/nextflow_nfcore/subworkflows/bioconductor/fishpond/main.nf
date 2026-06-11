#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fishpond — bulk_differential_expression
// Perform differential transcript or gene expression analysis on bulk RNA-seq data using inferential replicates.
// Input: coldata.csv, Salmon quantification directories
// Container: quay.io/biocontainers/bioconductor-fishpond:2.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, fishpond, tximeta
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read sample metadata
//  * 2. [Input & Preparation] Import quantification data using tximeta
//  * 3. [Input & Preparation] Scale inferential replicates
//  * 4. [Input & Preparation] Filter out low-expression features
//  * 5. [Input & Preparation] Run Swish differential expression testing

nextflow.enable.dsl = 2

process BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION {
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
        library(tximeta)
        library(fishpond)
        
        # --- Read sample metadata ---
        if (!file.exists("coldata.csv")) {
          stop("Error: coldata.csv not found in the working directory.")
        }
        coldata <- read.csv("coldata.csv")
        
        # Verify required columns for tximeta
        if (!all(c("names", "files") %in% colnames(coldata))) {
          stop("Error: coldata.csv must contain 'names' and 'files' columns.")
        }
        
        # Verify condition column exists for differential expression
        if (!"condition" %in% colnames(coldata)) {
          stop("Error: coldata.csv must contain a 'condition' column.")
        }
        
        # Ensure condition/covariate columns are factors if they exist
        if ("condition" %in% colnames(coldata)) {
          coldata\$condition <- as.factor(coldata\$condition)
        }
        if ("covariate" %in% colnames(coldata)) {
          coldata\$covariate <- as.factor(coldata\$covariate)
        }
        if ("pair" %in% colnames(coldata)) {
          coldata\$pair <- as.factor(coldata\$pair)
        }
        
        # --- Import quantification data using tximeta ---
        message("Importing quantification data using tximeta...")
        y <- tximeta(coldata)
        
        # --- Scale inferential replicates ---
        message("Scaling inferential replicates...")
        y <- scaleInfReps(y)
        
        # --- Filter out low-expression features ---
        message("Labeling features to keep...")
        y <- labelKeep(y)
        
        # Subset to keep only the labeled features
        y <- y[mcols(y)\$keep, ]
        
        # --- Run Swish differential expression testing ---
        set.seed(1)
        
        # Run the simplest Swish case if 'condition' is present and not paired
        if ("condition" %in% colnames(coldata) && !("pair" %in% colnames(coldata))) {
          message("Running simplest Swish case...")
          y <- swish(y, x="condition")
          
          # Save outputs
          write.csv(as.data.frame(mcols(y)), "swish_results_simple.csv", row.names=TRUE)
          saveRDS(y, "y_simple.rds")
          
          pdf("swish_plots_simple.pdf")
          hist(mcols(y)\$pvalue, col="grey", main="P-value Distribution (Simple Swish)")
          plotMASwish(y, alpha=0.05)
          dev.off()
        }
        
        # Run paired Swish designs if 'condition' and 'pair' are present, but no 'covariate'
        if ("condition" %in% colnames(coldata) && "pair" %in% colnames(coldata) && !("covariate" %in% colnames(coldata))) {
          message("Running paired Swish...")
          y_paired <- swish(y, x="condition", pair="pair")
          
          # Save paired outputs
          write.csv(as.data.frame(mcols(y_paired)), "swish_results_paired.csv", row.names=TRUE)
          saveRDS(y_paired, "y_paired.rds")
          
          pdf("swish_plots_paired.pdf")
          hist(mcols(y_paired)\$pvalue, col="grey", main="P-value Distribution (Paired Swish)")
          plotMASwish(y_paired, alpha=0.05)
          dev.off()
          
          # Run fast paired Swish
          message("Running fast paired Swish...")
          y_fast <- swish(y, x="condition", pair="pair", fast=1)
          
          # Save fast paired outputs
          write.csv(as.data.frame(mcols(y_fast)), "swish_results_fast_paired.csv", row.names=TRUE)
          saveRDS(y_fast, "y_fast.rds")
        }
        
        # Run interaction Swish designs if 'condition', 'covariate', and 'pair' are present
        if ("condition" %in% colnames(coldata) && "covariate" %in% colnames(coldata) && "pair" %in% colnames(coldata)) {
          message("Running interaction Swish...")
          y2 <- y
          y2 <- swish(y2, x="condition", cov="covariate", pair="pair", interaction=TRUE)
          
          # Save interaction outputs
          write.csv(as.data.frame(mcols(y2)), "swish_results_interaction.csv", row.names=TRUE)
          saveRDS(y2, "y_interaction.rds")
          
          pdf("swish_plots_interaction.pdf")
          hist(mcols(y2)\$pvalue, col="grey", main="P-value Distribution (Interaction Swish)")
          plotMASwish(y2, alpha=0.05)
          dev.off()
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION":',
        paste0('    fishpond: ', as.character(packageVersion('fishpond')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_differential_expression.csv versions.yml
    """
}

workflow BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coldata.csv, Salmon quantification directories ] ]

    main:
    BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_FISHPOND_BULK_DIFFERENTIAL_EXPRESSION.out.versions
}
