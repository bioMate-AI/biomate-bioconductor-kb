#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirTarRnaSeq — mirna_mrna_correlation_multi_timepoint
// Identify significant miRNA-mRNA correlations across three or more time points using fold change data and background distribution comparisons.
// Input: mRNA_timepoints.txt.gz, miRNA_timepoints.txt.gz
// Container: quay.io/biocontainers/bioconductor-mirtarrnaseq:1.18.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, mirTarRnaSeq, reshape2, tidyr, viridis
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, mirTarRnaSeq, reshape2, tidyr, viridis
// Visualizations: density plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load time-point specific differential expression files for mRNA and miRNA
//  * 2. [Input & Preparation] Parse fold changes and filter mRNAs by p-value threshold using one2OneRnaMiRNA
//  * 3. [Core Analysis] Calculate Pearson correlation between mRNA and miRNA fold changes using corMirnaRna
//  * 4. [Core Analysis] Generate a background correlation distribution using sampCorRnaMirna
//  * 5. [Visualization & Output] Plot correlation density using mirRnaDensityCor
//  * 6. [Core Analysis] Identify significant correlations below a threshold using threshSig
//  * 7. [Core Analysis] Retrieve species-specific miRanda target predictions using getInputSpecies
//  * 8. [Core Analysis] Intersect significant correlations with miRanda predictions using corMirnaRnaMiranda or miRandaIntersect
//  * 9. [Visualization & Output] Visualize results with a heatmap using mirRnaHeatmap

nextflow.enable.dsl = 2

process BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT {
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
    .bm_deps <- c("dplyr", "ggplot2", "mirTarRnaSeq", "reshape2", "tidyr", "viridis")
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
    
    # Load required libraries
    library(mirTarRnaSeq)
    library(ggplot2)
    library(dplyr)
    library(reshape2)
    library(tidyr)
    library(viridis)
    
    # ==========================================
    # 1. Load and Parse User Input Files
    # ==========================================
    
    # Verify input files exist in the working directory
    if (!file.exists("mRNA_timepoints.txt.gz")) {
      stop("Error: 'mRNA_timepoints.txt.gz' not found in the working directory.")
    }
    if (!file.exists("miRNA_timepoints.txt.gz")) {
      stop("Error: 'miRNA_timepoints.txt.gz' not found in the working directory.")
    }
    
    # Read mRNA timepoints file
    mrna_raw <- read.table("mRNA_timepoints.txt.gz", header = TRUE, sep = "\t", as.is = TRUE)
    if (!is.character(mrna_raw[[1]])) {
      mrna_raw <- cbind(Gene = rownames(mrna_raw), mrna_raw)
    }
    
    # Split mRNA wide table into a list of data frames (one per timepoint)
    # Expected format per timepoint: Column 1 = Gene, Column 2 = FC, Column 3 = Pval
    mrna_files <- list()
    num_cols_mrna <- ncol(mrna_raw)
    i <- 2
    tp_idx <- 1
    while (i < num_cols_mrna) {
      fc_col <- i
      pval_col <- i + 1
      tp_name <- paste0("T", tp_idx)
      
      # Try to extract timepoint name from column header
      col_name <- colnames(mrna_raw)[fc_col]
      clean_name <- gsub("_FC|_foldchange|FC_|_foldchange_", "", col_name, ignore.case = TRUE)
      if (clean_name != "" && !clean_name %in% colnames(mrna_raw)[1]) {
        tp_name <- clean_name
      }
      
      mrna_files[[tp_name]] <- data.frame(
        Gene = mrna_raw[[1]],
        FC = mrna_raw[[fc_col]],
        Pval = mrna_raw[[pval_col]],
        stringsAsFactors = FALSE
      )
      i <- i + 2
      tp_idx <- tp_idx + 1
    }
    
    # Read miRNA timepoints file
    mirna_raw <- read.table("miRNA_timepoints.txt.gz", header = TRUE, sep = "\t", as.is = TRUE)
    if (!is.character(mirna_raw[[1]])) {
      mirna_raw <- cbind(miRNA = rownames(mirna_raw), mirna_raw)
    }
    
    # Split miRNA wide table into a list of data frames (one per timepoint)
    # Expected format per timepoint: Column 1 = miRNA, Column 2 = FC
    mirna_files <- list()
    num_cols_mirna <- ncol(mirna_raw)
    for (j in 2:num_cols_mirna) {
      tp_name <- paste0("T", j - 1)
      col_name <- colnames(mirna_raw)[j]
      clean_name <- gsub("_FC|_foldchange|FC_|_foldchange_", "", col_name, ignore.case = TRUE)
      if (clean_name != "" && !clean_name %in% colnames(mirna_raw)[1]) {
        tp_name <- clean_name
      }
      
      mirna_files[[tp_name]] <- data.frame(
        miRNA = mirna_raw[[1]],
        FC = mirna_raw[[j]],
        stringsAsFactors = FALSE
      )
    }
    
    # ==========================================
    # 2. Parse Fold Changes and Filter mRNAs
    # ==========================================
    mrna <- one2OneRnaMiRNA(mrna_files, pthreshold = 0.05)\$foldchanges
    mirna <- one2OneRnaMiRNA(mirna_files)\$foldchanges
    
    # ==========================================
    # 3. Calculate Pearson Correlation
    # ==========================================
    corr_0 <- corMirnaRna(mrna, mirna, method = "pearson")
    
    # ==========================================
    # 4. Generate Background Correlation Distribution
    # ==========================================
    outs <- sampCorRnaMirna(mrna, mirna, method = "pearson",
                            Shrounds = 100, Srounds = 1000)
    
    # ==========================================
    # 5. Plot Correlation Density
    # ==========================================
    pdf("correlation_density_plot.pdf", width = 6, height = 6)
    mirRnaDensityCor(corr_0, outs)
    dev.off()
    
    # ==========================================
    # 6. Identify Significant Correlations
    # ==========================================
    sig_corrs <- threshSig(corr_0, outs, pvalue = 0.05)
    write.csv(sig_corrs, "significant_correlations.csv", row.names = TRUE)
    
    # ==========================================
    # 7. Retrieve Species-Specific miRanda Predictions
    # ==========================================
    miRanda <- getInputSpecies("Mouse", threshold = 150)
    
    # ==========================================
    # 8. Intersect and Visualize Results
    # ==========================================
    # Extract target correlations based on miRanda and correlation threshold
    newcorr <- corMirnaRnaMiranda(mrna, mirna, -0.7, miRanda)
    
    pdf("heatmap_newcorr.pdf", width = 8, height = 8)
    mirRnaHeatmap(newcorr, upper_bound = -0.6)
    dev.off()
    
    # Intersect significant correlations with miRanda predictions
    results <- miRandaIntersect(sig_corrs, outs, mrna, mirna, miRanda)
    saveRDS(results, "miranda_intersect_results.rds")
    
    if (!is.null(results\$corr)) {
      write.csv(results\$corr, "intersected_correlations.csv", row.names = TRUE)
      
      # Draw final correlation heatmap
      pdf("heatmap_results.pdf", width = 8, height = 8)
      p <- mirRnaHeatmap(results\$corr, upper_bound = -0.99)
      if (!is.null(p)) {
        print(p)
      }
      dev.off()
    }
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT":',
        paste0('    mirTarRnaSeq: ', as.character(packageVersion('mirTarRnaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_mrna_correlation_multi_timepoint.csv versions.yml
    """
}

workflow BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mRNA_timepoints.txt.gz, miRNA_timepoints.txt.gz ] ]

    main:
    BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT(ch_input)

    emit:
    tables   = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.tables
    plots    = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.plots
    objects  = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.objects
    versions = BIOC_MIRTARRNASEQ_MIRNA_MRNA_CORRELATION_MULTI_TIMEPOINT.out.versions
}
