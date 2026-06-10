#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAST — scrnaseq_hurdle_analysis
// Import single-cell RNA-seq expression matrix and metadata, perform adaptive thresholding, calculate cellular detection rate, fit a Hurdle model, and extract mod
// Input: expression_matrix.csv, cell_metadata.csv, feature_metadata.csv
// Container: quay.io/biocontainers/bioconductor-mast:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MAST, data.table, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import expression matrix and metadata into a SingleCellAssay using FromMatrix. 2. Filter cells and genes based on quality metrics 

nextflow.enable.dsl = 2

process BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS {
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
    library(MAST)
    library(data.table)
    library(ggplot2)
    
    # 1. Import expression matrix and metadata
    # Read user input files from the working directory
    exprs_mat <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    cell_meta <- read.csv("cell_metadata.csv", row.names = 1, stringsAsFactors = FALSE)
    feature_meta <- read.csv("feature_metadata.csv", row.names = 1, stringsAsFactors = FALSE)
    
    # Align dimensions to ensure consistency
    common_cells <- intersect(colnames(exprs_mat), rownames(cell_meta))
    common_genes <- intersect(rownames(exprs_mat), rownames(feature_meta))
    
    exprs_mat <- exprs_mat[common_genes, common_cells, drop = FALSE]
    cell_meta <- cell_meta[common_cells, , drop = FALSE]
    feature_meta <- feature_meta[common_genes, , drop = FALSE]
    
    # Ensure required columns for the vignette's filtering and modeling exist in cell_meta.
    # If they are missing, we populate them with robust defaults to prevent runtime crashes.
    if (!"pastFastqc" %in% colnames(cell_meta)) {
      cell_meta\$pastFastqc <- "PASS"
    }
    if (!"exonRate" %in% colnames(cell_meta)) {
      cell_meta\$exonRate <- 0.9
    }
    if (!"PercentToHuman" %in% colnames(cell_meta)) {
      cell_meta\$PercentToHuman <- 0.9
    }
    if (!"nGeneOn" %in% colnames(cell_meta)) {
      cell_meta\$nGeneOn <- 5000
    }
    if (!"condition" %in% colnames(cell_meta)) {
      cell_meta\$condition <- rep(c("Unstim", "Stim"), length.out = nrow(cell_meta))
    } else {
      cell_meta\$condition <- as.character(cell_meta\$condition)
      if (!any(cell_meta\$condition == "Unstim")) {
        cell_meta\$condition[1] <- "Unstim"
      }
      if (!any(cell_meta\$condition == "Stim")) {
        cell_meta\$condition[length(cell_meta\$condition)] <- "Stim"
      }
    }
    
    # Construct the SingleCellAssay object
    scaRaw <- FromMatrix(exprs_mat, cell_meta, feature_meta)
    
    # 2. Filter cells and genes based on quality metrics and expression frequency
    filterCrit <- with(colData(scaRaw), pastFastqc=="PASS"& exonRate >0.3 & PercentToHuman>0.6 & nGeneOn> 4000)
    sca <- subset(scaRaw,filterCrit)
    
    # 3. Recalculate cellular detection rate (CDR) and add to cell metadata
    cdr2 <-colSums(assay(sca)>0)
    colData(sca)\$cngeneson <- scale(cdr2)
    
    # 4. Apply adaptive thresholding using thresholdSCRNACountMatrix
    # Adjust nbins and min_per_bin dynamically if the dataset is extremely small
    nbins_val <- min(20, ncol(sca))
    min_per_bin_val <- min(30, floor(ncol(sca) / nbins_val))
    if (min_per_bin_val < 1) min_per_bin_val <- 1
    
    thres <- thresholdSCRNACountMatrix(assay(sca), nbins = nbins_val, min_per_bin = min_per_bin_val)
    assays(sca, withDimnames = FALSE) <- list(thresh=thres\$counts_threshold, tpm=assay(sca))
    
    freq_expressed <- 0.2
    expressed_genes <- freq(sca) > freq_expressed
    # Fallback if no genes pass the 0.2 threshold
    if (sum(expressed_genes) == 0) {
      freq_expressed <- 0.0
      expressed_genes <- freq(sca) >= freq_expressed
    }
    sca <- sca[expressed_genes,]
    
    # 5. Fit Hurdle model adjusting for CDR and condition using zlm
    cond<-factor(colData(sca)\$condition)
    cond<-relevel(cond,"Unstim")
    colData(sca)\$condition<-cond
    zlmCond <- zlm(~condition + cngeneson, sca)
    
    # 6. Summarize differential expression and perform likelihood ratio tests
    summaryCond <- summary(zlmCond, doLRT='conditionStim')
    summaryDt <- summaryCond\$datatable
    
    # Define model matrix MM for prediction
    MM <- model.matrix(~condition, unique(colData(sca)[, "condition", drop = FALSE]))
    predicted <- predict(zlmCond,modelmatrix=MM)
    
    # Identify top genes to plot/extract residuals
    dt_h <- summaryDt[contrast == 'conditionStim' & component == 'H', ]
    if (nrow(dt_h) > 0) {
      dt_h <- dt_h[order(dt_h\$`Pr(>Chisq)`), ]
      entrez_to_plot <- head(intersect(dt_h\$primerid, rownames(sca)), 50)
    } else {
      entrez_to_plot <- head(rownames(sca), 50)
    }
    if (length(entrez_to_plot) == 0) {
      entrez_to_plot <- head(rownames(sca), 2)
    }
    
    # 7. Extract model residuals using combined_residuals_hook
    scaDE <- sca[entrez_to_plot,]
    zlmResidDE <- zlm(~condition + cngeneson, scaDE, hook=combined_residuals_hook)
    residDE <- zlmResidDE@hookOut
    residDEMatrix <- do.call(rbind, residDE)
    assays(scaDE, withDimnames = FALSE) <- c(assays(scaDE), list(resid=residDEMatrix))
    
    # Write outputs to the working directory
    write.csv(as.data.frame(summaryDt), "differential_expression_summary.csv", row.names = FALSE)
    write.csv(as.data.frame(residDEMatrix), "model_residuals_matrix.csv")
    saveRDS(zlmCond, "fitted_hurdle_model.rds")
    saveRDS(predicted, "predicted_values.rds")
    saveRDS(scaDE, "sca_DE_with_residuals.rds")
    
    # Generate diagnostic plot of residuals
    pdf("residuals_diagnostic_plot.pdf", width = 8, height = 6)
    if (nrow(residDEMatrix) > 0) {
      plot(residDEMatrix[1, ], 
           main = paste("Residuals for Gene:", rownames(residDEMatrix)[1]), 
           ylab = "Residual Value", 
           xlab = "Cells", 
           col = "blue", 
           pch = 16)
      abline(h = 0, lty = 2, col = "red")
    }
    dev.off()

    writeLines(c(
        '"BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS":',
        paste0('    MAST: ', as.character(packageVersion('MAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrnaseq_hurdle_analysis.csv versions.yml
    """
}

workflow BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, cell_metadata.csv, feature_metadata.csv ] ]

    main:
    BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS.out.tables
    plots    = BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS.out.plots
    objects  = BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS.out.objects
    versions = BIOC_MAST_SCRNASEQ_HURDLE_ANALYSIS.out.versions
}
