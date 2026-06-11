#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scPCA — sparse_contrastive_pca
// Perform Sparse Contrastive Principal Component Analysis (scPCA) to identify stable, interpretable, and condition-specific biological signals by contrasting targ
// Input: counts.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, ggpubr, scPCA
// Visualizations: PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA {
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
    
    # --- Load required libraries ---
    library(scPCA)
    library(dplyr)
    library(ggplot2)
    library(ggpubr)
    
    # --- Read and preprocess input data ---
    message("Reading input files...")
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Set row names for counts if 'gene_id' column is present
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    }
    counts_mat <- as.matrix(counts_df)
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts_mat), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    counts_mat <- counts_mat[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Log-transform counts
    log_counts <- log1p(counts_mat)
    
    # Filter genes by variance to focus on highly variable features
    message("Filtering genes by variance...")
    gene_vars <- apply(log_counts, 1, var)
    n_genes_to_keep <- min(250, nrow(log_counts))
    top_genes <- names(sort(gene_vars, decreasing = TRUE)[1:n_genes_to_keep])
    log_counts_sub <- log_counts[top_genes, , drop = FALSE]
    
    # --- Identify Target and Background Groups ---
    # Contrastive PCA requires splitting the dataset into target (interest) and background (control)
    unique_conds <- unique(coldata\$condition)
    if (length(unique_conds) < 2) {
      stop("At least two conditions are required to perform contrastive PCA (one target, one background).")
    }
    
    # Identify background condition using common keywords, otherwise default to the second unique condition
    bg_idx <- grep("control|background|normal|ref|bg", unique_conds, ignore.case = TRUE)
    if (length(bg_idx) > 0) {
      bg_cond <- unique_conds[bg_idx[1]]
      tg_conds <- unique_conds[-bg_idx[1]]
    } else {
      tg_conds <- unique_conds[1]
      bg_cond <- unique_conds[2:length(unique_conds)]
    }
    
    message("Target conditions: ", paste(tg_conds, collapse = ", "))
    message("Background condition: ", paste(bg_cond, collapse = ", "))
    
    tg_samples <- coldata\$sample[coldata\$condition %in% tg_conds]
    bg_samples <- coldata\$sample[coldata\$condition %in% bg_cond]
    
    # Transpose matrices so that rows represent samples and columns represent genes
    tg_mat <- t(log_counts_sub[, tg_samples, drop = FALSE])
    bg_mat <- t(log_counts_sub[, bg_samples, drop = FALSE])
    
    # --- Run Contrastive PCA (cPCA) and Sparse Contrastive PCA ---
    message("Running cPCA and scPCA...")
    
    # Define hyperparameter grids for contrastive and sparsity parameters
    contrasts <- exp(seq(log(0.1), log(100), length.out = 5))
    penalties <- exp(seq(log(0.001), log(0.1), length.out = 3))
    
    # Determine the number of clusters in the target data
    n_centers <- max(2, length(unique(coldata\$condition[coldata\$sample %in% tg_samples])))
    
    # Run cPCA (by setting penalties to 0)
    cpca_out <- scPCA(
      target = tg_mat,
      background = bg_mat,
      n_centers = n_centers,
      n_eigen = 2,
      contrasts = contrasts,
      penalties = 0,
      center = TRUE,
      scale = TRUE,
      alg = "var_proj"
    )
    
    # Run scPCA (with sparsity penalties)
    scpca_out <- scPCA(
      target = tg_mat,
      background = bg_mat,
      n_centers = n_centers,
      n_eigen = 2,
      contrasts = contrasts,
      penalties = penalties,
      center = TRUE,
      scale = TRUE,
      alg = "var_proj"
    )
    
    # --- Save Results ---
    message("Saving coordinates and loadings...")
    
    # Save scPCA coordinates
    scpca_coords <- as.data.frame(scpca_out\$x)
    colnames(scpca_coords) <- c("scPC1", "scPC2")
    scpca_coords\$sample <- rownames(tg_mat)
    scpca_coords\$condition <- coldata\$condition[match(scpca_coords\$sample, coldata\$sample)]
    write.csv(scpca_coords, "scpca_coordinates.csv", row.names = FALSE)
    
    # Save scPCA gene loadings
    scpca_loadings <- as.data.frame(scpca_out\$rotation)
    colnames(scpca_loadings) <- c("scPC1_loading", "scPC2_loading")
    scpca_loadings\$gene_id <- colnames(tg_mat)
    write.csv(scpca_loadings, "scpca_loadings.csv", row.names = FALSE)
    
    # --- Visualization ---
    message("Generating diagnostic plots...")
    
    # Prepare cPCA dataframe for plotting
    cpca_df <- as.data.frame(cpca_out\$x)
    colnames(cpca_df) <- c("cPC1", "cPC2")
    cpca_df\$condition <- coldata\$condition[match(rownames(tg_mat), coldata\$sample)]
    
    p_cpca <- ggplot(cpca_df, aes(x = cPC1, y = cPC2, color = condition)) +
      geom_point(size = 3, alpha = 0.8) +
      theme_minimal() +
      labs(title = "Contrastive PCA (cPCA)", x = "cPC1", y = "cPC2") +
      scale_color_brewer(palette = "Set1")
    
    p_scpca <- ggplot(scpca_coords, aes(x = scPC1, y = scPC2, color = condition)) +
      geom_point(size = 3, alpha = 0.8) +
      theme_minimal() +
      labs(title = "Sparse Contrastive PCA (scPCA)", x = "scPC1", y = "scPC2") +
      scale_color_brewer(palette = "Set1")
    
    # Combine and save plots
    combined_plot <- ggarrange(p_cpca, p_scpca, ncol = 2, common.legend = TRUE, legend = "right")
    ggsave("scpca_plots.pdf", plot = combined_plot, width = 12, height = 5)
    
    message("Analysis complete. Outputs written successfully.")

    writeLines(c(
        '"BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA":',
        paste0('    scPCA: ', as.character(packageVersion('scPCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sparse_contrastive_pca.csv versions.yml
    """
}

workflow BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA(ch_input)

    emit:
    tables   = BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA.out.tables
    plots    = BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA.out.plots
    objects  = BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA.out.objects
    versions = BIOC_SCPCA_SPARSE_CONTRASTIVE_PCA.out.versions
}
