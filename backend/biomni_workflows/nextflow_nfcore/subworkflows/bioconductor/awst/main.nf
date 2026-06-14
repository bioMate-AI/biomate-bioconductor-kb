#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: awst — awst_normalization_pipeline
// Regularize RNA-seq read counts using Asymmetric Within-Sample Transformation (AWST) combined with full-quantile normalization and entropy-based gene filtering t
// Input: counts.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EDASeq, SummarizedExperiment, awst, ggplot2
// Visualizations: density plot, PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AWST_AWST_NORMALIZATION_PIPELINE {
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
    .bm_deps <- c("awst", "EDASeq", "ggplot2", "SummarizedExperiment")
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
    
    # Load required libr    library(SummarizedExperiment)
aries
    library(awst)
    library(EDASeq)
    library(ggplot2)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input datasets...")
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Ensure sample alignment between counts and coldata
    common_samples <- intersect(colnames(counts_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between counts.csv and coldata.csv.")
    }
    
    counts_mat <- as.matrix(counts_df[, common_samples, drop = FALSE])
    coldata_aligned <- coldata_df[common_samples, , drop = FALSE]
    
    # Create SummarizedExperiment object
    se <- SummarizedExperiment(
      assays = list(counts = counts_mat),
      colData = coldata_aligned
    )
    message(sprintf("Initial dataset dimensions: %d genes, %d samples", nrow(se), ncol(se)))
    
    # ==========================================
    # --- Pre-filtering Lowly Expressed Genes ---
    # ==========================================
    message("Pre-filtering lowly expressed genes...")
    # Filter out genes with low average counts across all samples (default threshold: 10)
    mean_counts <- rowMeans(assay(se, "counts"))
    keep_genes <- mean_counts >= 10
    
    if (sum(keep_genes) < 2) {
      warning("Very few genes passed the pre-filtering threshold. Retaining all genes instead.")
      keep_genes <- rep(TRUE, nrow(se))
    }
    
    se <- se[keep_genes, ]
    message(sprintf("Genes remaining after pre-filtering: %d", nrow(se)))
    
    # ==========================================
    # --- Normalization & AWST Transformation ---
    # ==========================================
    message("Performing full-quantile normalization...")
    # Full-quantile normalization is recommended prior to AWST to stabilize parameters
    norm_counts <- EDASeq::betweenLaneNormalization(assay(se, "counts"), which = "full")
    assay(se, "fq") <- norm_counts
    
    message("Applying Asymmetric Within-Sample Transformation (AWST)...")
    # Run AWST on the normalized counts
    se <- awst::awst(se, expr_values = "fq")
    
    # Save the complete AWST-transformed matrix
    awst_counts <- assay(se, "awst")
    write.csv(awst_counts, "awst_transformed_counts.csv", row.names = TRUE)
    message("Saved AWST-transformed counts to 'awst_transformed_counts.csv'")
    
    # ==========================================
    # --- Entropy-based Gene Filtering ---
    # ==========================================
    message("Filtering uninformative genes using entropy...")
    # Remove genes that contribute little to sample distances
    filtered_se <- tryCatch({
      awst::gene_filter(se)
    }, error = function(e) {
      message("Gene filtering failed or returned empty. Returning original SE. Error: ", e\$message)
      return(se)
    })
    
    # Save the filtered AWST-transformed matrix
    filtered_awst_counts <- assay(filtered_se, "awst")
    write.csv(filtered_awst_counts, "filtered_awst_counts.csv", row.names = TRUE)
    message(sprintf("Saved filtered AWST counts (%d genes) to 'filtered_awst_counts.csv'", nrow(filtered_se)))
    
    # ==========================================
    # --- Diagnostics and Visualization ---
    # ==========================================
    message("Generating diagnostic plots...")
    
    # 1. Density Plot of AWST values for the first sample
    pdf("density_plot.pdf", width = 6, height = 5)
    plot(density(awst_counts[, 1]), 
         main = paste("AWST Density -", colnames(awst_counts)[1]), 
         xlab = "AWST transformed values", 
         col = "blue", lwd = 2)
    grid()
    dev.off()
    message("Saved density plot to 'density_plot.pdf'")
    
    # 2. PCA Plot of the filtered AWST counts
    tryCatch({
      # Perform PCA on transposed filtered counts
      pca_res <- prcomp(t(filtered_awst_counts))
      pca_df <- as.data.frame(pca_res\$x)
      
      # Merge PCA coordinates with sample metadata
      pca_df <- cbind(pca_df, colData(filtered_se))
      
      # Determine color variable based on metadata columns
      color_var <- if ("condition" %in% colnames(pca_df)) "condition" else colnames(pca_df)[1]
      
      p <- ggplot(pca_df, aes_string(x = "PC1", y = "PC2", color = color_var)) +
        geom_point(size = 3, alpha = 0.8) +
        theme_classic() +
        labs(title = "PCA of AWST-Regularized Profiles",
             x = paste0("PC1 (", round(100 * (pca_res\$sdev[1]^2 / sum(pca_res\$sdev^2)), 1), "%)"),
             y = paste0("PC2 (", round(100 * (pca_res\$sdev[2]^2 / sum(pca_res\$sdev^2)), 1), "%)")) +
        theme(plot.title = element_text(hjust = 0.5, face = "bold"))
      
      ggsave("pca_plot.pdf", plot = p, width = 7, height = 6)
      message("Saved PCA plot to 'pca_plot.pdf'")
    }, error = function(e) {
      message("Could not generate PCA plot. Creating an empty PDF placeholder. Error: ", e\$message)
      pdf("pca_plot.pdf", width = 7, height = 6)
      plot.new()
      text(0.5, 0.5, "PCA Plot Generation Failed\n(Check sample size or metadata columns)", cex = 1.2)
      dev.off()
    })
    
    message("AWST pipeline completed successfully!")

    writeLines(c(
        '"BIOC_AWST_AWST_NORMALIZATION_PIPELINE":',
        paste0('    awst: ', as.character(packageVersion('awst')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_awst_normalization_pipeline.csv versions.yml
    """
}

workflow BIOC_AWST_AWST_NORMALIZATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_AWST_AWST_NORMALIZATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AWST_AWST_NORMALIZATION_PIPELINE.out.tables
    plots    = BIOC_AWST_AWST_NORMALIZATION_PIPELINE.out.plots
    objects  = BIOC_AWST_AWST_NORMALIZATION_PIPELINE.out.objects
    versions = BIOC_AWST_AWST_NORMALIZATION_PIPELINE.out.versions
}
