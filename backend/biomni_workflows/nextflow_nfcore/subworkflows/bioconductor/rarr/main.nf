#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rarr — zarr_transcriptomics_pipeline
// Build an end-to-end transcriptomics pipeline that stores, normalizes, and analyzes large-scale expression matrices using chunked Zarr arrays via the Rarr packag
// Input: counts.csv, coldata.csv
// Container: 1.10.1--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Rarr, S4Vectors, SummarizedExperiment
// Visualizations: PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE {
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
    .bm_deps <- c("Rarr", "S4Vectors", "SummarizedExperiment")
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
    library(Rarr)
    library(SummarizedExperiment)
    library(S4Vectors)
    
    # ==========================================
    # --- Load Input Data ---
    # ==========================================
    message("Stage 1: Loading input CSV files...")
    counts_df <- read.csv("counts.csv", row.names = "gene_id", check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata_df) <- coldata_df\$sample
    
    count_matrix <- as.matrix(counts_df)
    storage.mode(count_matrix) <- "integer"
    
    n_genes <- nrow(count_matrix)
    n_samples <- ncol(count_matrix)
    message(sprintf("Loaded dataset with %d genes and %d samples.", n_genes, n_samples))
    
    # ==========================================
    # --- Write Raw Counts to Zarr Array ---
    # ==========================================
    message("Stage 2: Writing raw counts to a chunked Zarr array...")
    raw_zarr_path <- "raw_counts.zarr"
    
    if (dir.exists(raw_zarr_path)) {
      unlink(raw_zarr_path, recursive = TRUE)
    }
    
    # Define chunk dimensions (chunking by genes to allow efficient gene-wise operations)
    chunk_size <- min(100, n_genes)
    chunk_dims <- c(chunk_size, n_samples)
    
    write_zarr_array(
      x = count_matrix,
      zarr_array_path = raw_zarr_path,
      chunk_dim = chunk_dims
    )
    
    # Print overview of the created Zarr array
    message("Zarr Array Overview:")
    zarr_overview(raw_zarr_path)
    
    # ==========================================
    # --- Out-of-Core Normalization (CPM) ---
    # ==========================================
    message("Stage 3: Performing chunk-wise CPM normalization...")
    
    # 1. Compute column sums (library sizes) chunk-by-chunk
    col_sums <- numeric(n_samples)
    n_chunks <- ceiling(n_genes / chunk_size)
    
    for (i in seq_len(n_chunks)) {
      start_idx <- (i - 1) * chunk_size + 1
      end_idx <- min(i * chunk_size, n_genes)
      
      # Read chunk from Zarr
      chunk_data <- read_zarr_array(raw_zarr_path, index = list(start_idx:end_idx, NULL))
      col_sums <- col_sums + colSums(chunk_data)
    }
    
    # Avoid division by zero if library sizes are empty
    col_sums[col_sums == 0] <- 1
    
    # 2. Create an empty Zarr array for normalized counts
    norm_zarr_path <- "normalized_counts.zarr"
    if (dir.exists(norm_zarr_path)) {
      unlink(norm_zarr_path, recursive = TRUE)
    }
    
    create_empty_zarr_array(
      zarr_array_path = norm_zarr_path,
      dim = c(n_genes, n_samples),
      chunk_dim = chunk_dims,
      data_type = "double",
      fill_value = 0.0
    )
    
    # 3. Compute CPM and update the normalized Zarr array chunk-by-chunk
    for (i in seq_len(n_chunks)) {
      start_idx <- (i - 1) * chunk_size + 1
      end_idx <- min(i * chunk_size, n_genes)
      
      chunk_data <- read_zarr_array(raw_zarr_path, index = list(start_idx:end_idx, NULL))
      
      # CPM calculation: (count / library_size) * 1e6
      cpm_chunk <- t(t(chunk_data) / col_sums) * 1e6
      
      update_zarr_array(
        zarr_array_path = norm_zarr_path,
        x = cpm_chunk,
        index = list(start_idx:end_idx, 1:n_samples)
      )
    }
    
    # ==========================================
    # --- Feature Selection (Highly Variable Genes) ---
    # ==========================================
    message("Stage 4: Identifying highly variable genes chunk-by-chunk...")
    gene_vars <- numeric(n_genes)
    
    for (i in seq_len(n_chunks)) {
      start_idx <- (i - 1) * chunk_size + 1
      end_idx <- min(i * chunk_size, n_genes)
      
      chunk_data <- read_zarr_array(norm_zarr_path, index = list(start_idx:end_idx, NULL))
      gene_vars[start_idx:end_idx] <- apply(chunk_data, 1, var)
    }
    
    # Select top 50 highly variable genes (or all if fewer than 50)
    n_top <- min(50, n_genes)
    top_genes_idx <- order(gene_vars, decreasing = TRUE)[1:n_top]
    
    # Retrieve only the top variable genes from the Zarr array
    top_norm_counts <- read_zarr_array(norm_zarr_path, index = list(top_genes_idx, NULL))
    rownames(top_norm_counts) <- rownames(count_matrix)[top_genes_idx]
    colnames(top_norm_counts) <- colnames(count_matrix)
    
    # ==========================================
    # --- Downstream Analysis & Visualization ---
    # ==========================================
    message("Stage 5: Constructing SummarizedExperiment and performing PCA...")
    
    # Construct SummarizedExperiment
    se <- SummarizedExperiment(
      assays = list(logcpm = log2(top_norm_counts + 1)),
      colData = DataFrame(coldata_df[colnames(top_norm_counts), , drop = FALSE])
    )
    
    # Perform PCA on log-transformed CPM of top variable genes
    pca_res <- prcomp(t(assay(se, "logcpm")), scale. = TRUE)
    pca_df <- data.frame(
      PC1 = pca_res\$x[, 1],
      PC2 = pca_res\$x[, 2],
      Condition = colData(se)\$condition,
      Sample = rownames(colData(se))
    )
    
    # Save PCA coordinates
    write.csv(pca_df, "pca_results.csv", row.names = FALSE)
    
    # Generate PCA Plot
    pdf("pca_plot.pdf", width = 7, height = 5)
    plot(
      pca_df\$PC1, pca_df\$PC2,
      col = as.factor(pca_df\$Condition),
      pch = 19, cex = 1.5,
      xlab = paste0("PC1 (", round(100 * (pca_res\$sdev[1]^2 / sum(pca_res\$sdev^2)), 1), "%)"),
      ylab = paste0("PC2 (", round(100 * (pca_res\$sdev[2]^2 / sum(pca_res\$sdev^2)), 1), "%)"),
      main = "PCA of Top Variable Genes (Zarr-Sourced)"
    )
    text(pca_df\$PC1, pca_df\$PC2, labels = pca_df\$Sample, pos = 3, cex = 0.8)
    legend("topright", legend = unique(pca_df\$Condition), col = unique(as.factor(pca_df\$Condition)), pch = 19)
    dev.off()
    
    # ==========================================
    # --- Export Full Normalized Matrix ---
    # ==========================================
    message("Stage 6: Exporting full normalized counts...")
    full_norm_matrix <- read_zarr_array(norm_zarr_path)
    rownames(full_norm_matrix) <- rownames(count_matrix)
    colnames(full_norm_matrix) <- colnames(count_matrix)
    
    write.csv(full_norm_matrix, "normalized_counts.csv")
    
    # Clean up temporary Zarr directories
    if (dir.exists(raw_zarr_path)) unlink(raw_zarr_path, recursive = TRUE)
    if (dir.exists(norm_zarr_path)) unlink(norm_zarr_path, recursive = TRUE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE":',
        paste0('    Rarr: ', as.character(packageVersion('Rarr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zarr_transcriptomics_pipeline.csv versions.yml
    """
}

workflow BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE.out.tables
    plots    = BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE.out.plots
    objects  = BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE.out.objects
    versions = BIOC_RARR_ZARR_TRANSCRIPTOMICS_PIPELINE.out.versions
}
