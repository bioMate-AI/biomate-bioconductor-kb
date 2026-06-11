#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Dune — dune_cluster_merging
// Optimize and merge transcriptomic cluster labels from multiple clustering methods to maximize consensus and replicability using the Dune algorithm.
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Dune, dplyr, ggplot2, tidyr
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DUNE_DUNE_CLUSTER_MERGING {
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
    .bm_deps <- c("Dune", "ggplot2", "dplyr", "tidyr")
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
    suppressPackageStartupMessages({
      library(Dune)
      library(ggplot2)
      library(dplyr)
      library(tidyr)
    })
    
    # ==========================================
    # --- Read Input Data & Preprocess ---
    # ==========================================
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read counts and coldata
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
      stop("counts.csv must contain a 'gene_id' column.")
    }
    rownames(counts_df) <- counts_df\$gene_id
    counts_df\$gene_id <- NULL
    counts_mat <- as.matrix(counts_df)
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (!"sample" %in% colnames(coldata)) {
      stop("coldata.csv must contain a 'sample' column.")
    }
    
    # Ensure sample alignment
    common_samples <- intersect(colnames(counts_mat), coldata\$sample)
    if (length(common_samples) < 10) {
      stop("Too few common samples between counts and coldata to perform robust clustering.")
    }
    counts_mat <- counts_mat[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Normalize counts (Log2 CPM)
    libsizes <- colSums(counts_mat)
    libsizes[libsizes == 0] <- 1
    cpm <- t(t(counts_mat) / libsizes) * 1e6
    log_cpm <- log2(cpm + 1)
    
    # ==========================================
    # --- Generate Multiple Clusterings ---
    # ==========================================
    # Transpose to have samples as rows
    sample_features <- t(log_cpm)
    
    # Perform PCA to reduce dimensionality
    pca <- prcomp(sample_features, scale. = TRUE)
    n_pcs <- min(5, ncol(pca\$x), nrow(sample_features) - 1)
    pcs <- pca\$x[, 1:n_pcs, drop = FALSE]
    
    # Generate 3 distinct clustering runs to simulate different algorithms/parameters
    set.seed(42)
    clus_kmeans_5 <- tryCatch({
      as.character(kmeans(pcs, centers = min(5, nrow(pcs) - 1), nstart = 10)\$cluster)
    }, error = function(e) {
      as.character(rep(1, nrow(pcs)))
    })
    
    clus_kmeans_6 <- tryCatch({
      as.character(kmeans(pcs, centers = min(6, nrow(pcs) - 1), nstart = 10)\$cluster)
    }, error = function(e) {
      as.character(rep(1, nrow(pcs)))
    })
    
    clus_hclust <- tryCatch({
      hc <- hclust(dist(pcs), method = "ward.D2")
      as.character(cutree(hc, k = min(5, nrow(pcs) - 1)))
    }, error = function(e) {
      as.character(rep(1, nrow(pcs)))
    })
    
    # Assemble the clustering matrix
    clusMat <- data.frame(
      Kmeans_K5 = clus_kmeans_5,
      Kmeans_K6 = clus_kmeans_6,
      Hclust_K5 = clus_hclust,
      stringsAsFactors = FALSE
    )
    rownames(clusMat) <- colnames(counts_mat)
    
    # ==========================================
    # --- Run Dune Merging Algorithm ---
    # ==========================================
    message("Running Dune cluster merging...")
    merger <- Dune(clusMat = clusMat, verbose = TRUE)
    
    # ==========================================
    # --- Export Merged Labels & Conversions ---
    # ==========================================
    # Combine initial and merged labels
    output_clusters <- data.frame(
      sample = rownames(merger\$initialMat),
      merger\$initialMat,
      suffix_merged = merger\$currentMat,
      stringsAsFactors = FALSE
    )
    # Rename merged columns for clarity
    colnames(output_clusters) <- c(
      "sample",
      paste0(colnames(clusMat), "_initial"),
      paste0(colnames(clusMat), "_merged")
    )
    write.csv(output_clusters, "merged_clusters.csv", row.names = FALSE)
    
    # Save cluster conversion mapping
    conversions <- clusterConversion(merger)
    sink("clustering_conversion.txt")
    cat("=== DUNE CLUSTER CONVERSION MAPPING ===\n\n")
    for (method in names(conversions)) {
      cat(paste("Method:", method, "\n"))
      print(conversions[[method]])
      cat("\n---------------------------------------\n\n")
    }
    cat(paste("Recommended stopping step based on ARI improvement:", whenToStop(merger), "\n"))
    sink()
    
    # ==========================================
    # --- Generate Diagnostic Visualizations ---
    # ==========================================
    pdf("dune_diagnostics.pdf", width = 8, height = 6)
    
    # 1. Initial ARI Heatmap
    tryCatch({
      p1 <- plotARIs(merger\$initialMat) + 
        ggtitle("Initial Adjusted Rand Index (ARI) Between Methods")
      print(p1)
    }, error = function(e) message("Failed to plot initial ARIs: ", e\$message))
    
    # 2. Final ARI Heatmap
    tryCatch({
      p2 <- plotARIs(merger\$currentMat) + 
        ggtitle("Post-Merging Adjusted Rand Index (ARI) Between Methods")
      print(p2)
    }, error = function(e) message("Failed to plot final ARIs: ", e\$message))
    
    # 3. Pre vs Post Cluster Counts
    tryCatch({
      p3 <- plotPrePost(merger) + 
        ggtitle("Reduction in Cluster Numbers Pre vs Post Dune")
      print(p3)
    }, error = function(e) message("Failed to plot Pre/Post comparison: ", e\$message))
    
    # 4. ARI Improvement Trend
    tryCatch({
      p4 <- ARItrend(merger) + 
        ggtitle("ARI Improvement Trend During Merging Steps")
      print(p4)
    }, error = function(e) message("Failed to plot ARI trend: ", e\$message))
    
    # 5. NMI Improvement Trend
    tryCatch({
      p5 <- NMItrend(merger) + 
        ggtitle("NMI Improvement Trend During Merging Steps")
      print(p5)
    }, error = function(e) message("Failed to plot NMI trend: ", e\$message))
    
    # 6. Confusion Plots for each method
    for (method in colnames(clusMat)) {
      tryCatch({
        p_conf <- ConfusionPlot(merger\$initialMat[, method], merger\$currentMat[, method]) +
          labs(
            title = paste("Confusion Matrix (Before vs After Merging) -", method),
            x = "Initial Clusters",
            y = "Merged Clusters"
          )
        print(p_conf)
      }, error = function(e) message("Failed to plot Confusion Matrix for ", method, ": ", e\$message))
    }
    
    dev.off()
    
    message("Dune pipeline completed successfully!")

    writeLines(c(
        '"BIOC_DUNE_DUNE_CLUSTER_MERGING":',
        paste0('    Dune: ', as.character(packageVersion('Dune')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dune_cluster_merging.csv versions.yml
    """
}

workflow BIOC_DUNE_DUNE_CLUSTER_MERGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DUNE_DUNE_CLUSTER_MERGING(ch_input)

    emit:
    tables   = BIOC_DUNE_DUNE_CLUSTER_MERGING.out.tables
    plots    = BIOC_DUNE_DUNE_CLUSTER_MERGING.out.plots
    objects  = BIOC_DUNE_DUNE_CLUSTER_MERGING.out.objects
    versions = BIOC_DUNE_DUNE_CLUSTER_MERGING.out.versions
}
