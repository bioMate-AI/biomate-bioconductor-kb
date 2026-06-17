#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tomoda — tomoda_tomo_seq_pipeline
// Perform a complete spatial transcriptomics analysis of tomo-seq data, including normalization, correlation analysis, dimensionality reduction, clustering, and p
// Input: counts.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, tomoda
// Visualizations: heatmap, PCA plot, t-SNE plot, UMAP plot, cluster plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE {
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
    .bm_deps <- c("tomoda", "ggplot2", "SummarizedExperiment")
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
    library(tomoda)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # Define parameters
    MIN_SECTION <- 3
    PEAK_THRESHOLD <- 1.0
    PEAK_LENGTH <- 3
    N_PERMUTATIONS <- 1000
    
    # ==========================================
    # --- Data Loading and Preprocessing ---
    # ==========================================
    
    message("Loading input datasets...")
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    }
    counts_matrix <- as.matrix(counts_df)
    
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    # Align coldata with counts columns (representing consecutive spatial sections)
    coldata <- coldata[colnames(counts_matrix), , drop = FALSE]
    
    message("Creating Tomo object and performing normalization/scaling...")
    # Adjust min.section if the dataset has fewer sections than the default threshold
    actual_min_section <- min(MIN_SECTION, ncol(counts_matrix))
    zh <- createTomo(counts_matrix, min.section = actual_min_section)
    
    # Append custom colData
    colData(zh) <- cbind(colData(zh), coldata)
    
    # ==========================================
    # --- Correlation & Dimensionality Reduction ---
    # ==========================================
    
    message("Performing section correlation analysis...")
    pdf("section_correlation_heatmap.pdf", width = 8, height = 7)
    print(corHeatmap(zh, max.cor = 0.3))
    dev.off()
    
    message("Running PCA on sections...")
    zh <- runPCA(zh)
    pdf("section_pca_plot.pdf", width = 6, height = 5)
    print(embedPlot(zh, method = "PCA"))
    dev.off()
    
    message("Running t-SNE on sections...")
    tryCatch({
      set.seed(42)
      zh <- runTSNE(zh)
      pdf("section_tsne_plot.pdf", width = 6, height = 5)
      print(embedPlot(zh, method = "TSNE"))
      dev.off()
    }, error = function(e) {
      message("t-SNE failed: ", e\$message)
    })
    
    message("Running UMAP on sections...")
    tryCatch({
      zh <- runUMAP(zh)
      pdf("section_umap_plot.pdf", width = 6, height = 5)
      print(embedPlot(zh, method = "UMAP"))
      dev.off()
    }, error = function(e) {
      message("UMAP failed: ", e\$message)
    })
    
    # ==========================================
    # --- Clustering Analysis ---
    # ==========================================
    
    message("Performing hierarchical clustering...")
    hc_zh <- hierarchClust(zh)
    pdf("section_hierarchical_clustering.pdf", width = 8, height = 5)
    plot(hc_zh)
    dev.off()
    
    message("Performing K-means clustering...")
    # Determine number of centers dynamically based on sample size
    centers_num <- min(3, ncol(counts_matrix) - 1)
    if (centers_num >= 2) {
      zh <- kmeansClust(zh, centers = centers_num)
      pdf("section_kmeans_plot.pdf", width = 6, height = 5)
      print(embedPlot(zh, group = "kmeans_cluster"))
      dev.off()
    }
    
    # Save section metadata with embeddings and cluster labels
    write.csv(as.data.frame(colData(zh)), "section_metadata_with_results.csv", row.names = TRUE)
    
    # ==========================================
    # --- Peak Gene Analysis ---
    # ==========================================
    
    message("Identifying spatially upregulated (peak) genes...")
    # Adjust peak length if the dataset has very few sections
    actual_peak_length <- min(PEAK_LENGTH, ncol(counts_matrix))
    peak_genes <- findPeakGene(zh, threshold = PEAK_THRESHOLD, length = actual_peak_length, nperm = N_PERMUTATIONS)
    write.csv(peak_genes, "peak_genes.csv", row.names = FALSE)
    
    if (nrow(peak_genes) > 0) {
      message(sprintf("Found %d peak genes. Generating downstream visualizations...", nrow(peak_genes)))
      
      # Expression Heatmap of Peak Genes
      pdf("peak_genes_expression_heatmap.pdf", width = 8, height = 8)
      print(expHeatmap(zh, peak_genes\$gene, size = 0))
      dev.off()
      
      # Gene Correlation Heatmap
      pdf("peak_genes_correlation_heatmap.pdf", width = 8, height = 8)
      print(geneCorHeatmap(zh, peak_genes, size = 0))
      dev.off()
      
      # Gene Embeddings
      tryCatch({
        zh <- runTSNE(zh, peak_genes\$gene)
        pdf("peak_genes_tsne.pdf", width = 6, height = 5)
        print(geneEmbedPlot(zh, peak_genes))
        dev.off()
      }, error = function(e) {
        message("Gene t-SNE failed: ", e\$message)
      })
      
      tryCatch({
        zh <- runUMAP(zh, peak_genes\$gene)
        pdf("peak_genes_umap.pdf", width = 6, height = 5)
        print(geneEmbedPlot(zh, peak_genes, method = "UMAP"))
        dev.off()
      }, error = function(e) {
        message("Gene UMAP failed: ", e\$message)
      })
      
      # Line plots for top 3 peak genes
      top_genes <- head(peak_genes\$gene, 3)
      pdf("top_peak_genes_traces.pdf", width = 8, height = 5)
      print(linePlot(zh, top_genes, facet = TRUE))
      dev.off()
    } else {
      message("No peak genes identified with the current thresholds.")
      # Create empty placeholder files to satisfy output declarations
      pdf("peak_genes_expression_heatmap.pdf", width = 5, height = 5)
      plot.new()
      text(0.5, 0.5, "No peak genes found")
      dev.off()
      
      file.copy("peak_genes_expression_heatmap.pdf", "peak_genes_correlation_heatmap.pdf")
      file.copy("peak_genes_expression_heatmap.pdf", "peak_genes_tsne.pdf")
      file.copy("peak_genes_expression_heatmap.pdf", "peak_genes_umap.pdf")
      file.copy("peak_genes_expression_heatmap.pdf", "top_peak_genes_traces.pdf")
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE":',
        paste0('    tomoda: ', as.character(packageVersion('tomoda')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tomoda_tomo_seq_pipeline.csv versions.yml
    """
}

workflow BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE(ch_input)

    emit:
    tables   = BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE.out.tables
    plots    = BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE.out.plots
    objects  = BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE.out.objects
    versions = BIOC_TOMODA_TOMODA_TOMO_SEQ_PIPELINE.out.versions
}
