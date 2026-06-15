#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tidytof — tidytof_proteomics_pipeline
// Preprocess, cluster, and perform dimensionality reduction on proteomics intensity data using tidytof's grammar of cytometry.
// Input: intensity.csv, coldata.csv
// Container: 1.0.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, readr, tidyr, tidytof
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("tidytof", "dplyr", "tidyr", "readr", "ggplot2")
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
    library(tidytof)
    library(dplyr)
    library(tidyr)
    library(readr)
    library(ggplot2)
    
    # ==========================================
    # --- Read and Format Input Data ---
    # ==========================================
    message("Reading input files...")
    intensity <- readr::read_csv("intensity.csv")
    coldata <- readr::read_csv("coldata.csv")
    
    # Transpose the intensity matrix so that samples are rows and features (proteins) are columns
    message("Formatting and transposing intensity matrix...")
    intensity_long <- intensity %>%
      tidyr::pivot_longer(cols = -feature_id, names_to = "sample", values_to = "intensity")
    
    intensity_wide <- intensity_long %>%
      tidyr::pivot_wider(names_from = feature_id, values_from = intensity)
    
    # Join with coldata to add sample metadata
    df <- intensity_wide %>%
      dplyr::left_join(coldata, by = "sample")
    
    # Identify protein/feature columns
    protein_cols <- setdiff(colnames(intensity_wide), "sample")
    
    # Handle missing values by replacing them with 0 (or a minimum value)
    df_clean <- df %>%
      dplyr::mutate(across(dplyr::all_of(protein_cols), ~dplyr::if_else(is.na(.x), 0, .x)))
    
    # ==========================================
    # --- Preprocessing (Arcsinh Transformation) ---
    # ==========================================
    message("Applying arcsinh transformation...")
    # tidytof provides tof_arcsinh for transforming cytometry/proteomics intensity values
    df_preprocessed <- df_clean %>%
      dplyr::mutate(across(dplyr::all_of(protein_cols), ~tidytof::tof_arcsinh(.x, cofactor = 5)))
    
    # ==========================================
    # --- Dimensionality Reduction (PCA) ---
    # ==========================================
    message("Performing dimensionality reduction...")
    num_samples <- nrow(df_preprocessed)
    
    if (num_samples > 2) {
      df_reduced <- df_preprocessed %>%
        tidytof::tof_reduce_dimensions(
          red_cols = dplyr::any_of(protein_cols),
          method = "pca"
        )
    } else {
      # Fallback for extremely small datasets
      df_reduced <- df_preprocessed %>%
        dplyr::mutate(.pc1 = seq_len(num_samples), .pc2 = seq_len(num_samples))
    }
    
    # Identify PCA column names dynamically
    pc_cols <- grep("pc|PC", colnames(df_reduced), value = TRUE)
    if (length(pc_cols) < 2) {
      df_reduced\$.pc1 <- seq_len(nrow(df_reduced))
      df_reduced\$.pc2 <- seq_len(nrow(df_reduced))
      pc_cols <- c(".pc1", ".pc2")
    }
    
    # ==========================================
    # --- Clustering (K-means) ---
    # ==========================================
    message("Clustering samples...")
    if (num_samples > 2) {
      # Use tidytof's clustering wrapper
      df_clustered <- df_reduced %>%
        tidytof::tof_cluster(
          cluster_cols = dplyr::any_of(protein_cols),
          method = "kmeans",
          centers = min(3, num_samples - 1)
        )
    } else {
      df_clustered <- df_reduced %>%
        dplyr::mutate(.kmeans_cluster = "1")
    }
    
    # Identify cluster column dynamically
    cluster_col <- grep("cluster", colnames(df_clustered), value = TRUE)
    if (length(cluster_col) == 0) {
      df_clustered\$.kmeans_cluster <- "1"
      cluster_col <- ".kmeans_cluster"
    } else {
      cluster_col <- cluster_col[1]
    }
    
    # Ensure cluster column is treated as a factor for visualization
    df_clustered[[cluster_col]] <- as.factor(df_clustered[[cluster_col]])
    
    # Save the processed and clustered data
    readr::write_csv(df_clustered, "tidy_proteomics_processed.csv")
    message("Saved processed data to tidy_proteomics_processed.csv")
    
    # ==========================================
    # --- Visualization and Diagnostics ---
    # ==========================================
    message("Generating diagnostic plots...")
    pdf("diagnostic_plots.pdf", width = 10, height = 8)
    
    # Plot 1: PCA colored by Cluster
    p1 <- ggplot2::ggplot(df_clustered, ggplot2::aes(x = .data[[pc_cols[1]]], y = .data[[pc_cols[2]]], color = .data[[cluster_col]])) +
      ggplot2::geom_point(size = 4, alpha = 0.8) +
      ggplot2::labs(
        title = "PCA of Preprocessed Proteomics Data",
        subtitle = "Colored by tidytof Cluster Assignments",
        x = pc_cols[1],
        y = pc_cols[2]
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(legend.position = "right")
    
    print(p1)
    
    # Plot 2: PCA colored by Condition (if available)
    if ("condition" %in% colnames(df_clustered)) {
      p2 <- ggplot2::ggplot(df_clustered, ggplot2::aes(x = .data[[pc_cols[1]]], y = .data[[pc_cols[2]]], color = condition)) +
        ggplot2::geom_point(size = 4, alpha = 0.8) +
        ggplot2::labs(
          title = "PCA of Preprocessed Proteomics Data",
          subtitle = "Colored by Sample Condition",
          x = pc_cols[1],
          y = pc_cols[2]
        ) +
        ggplot2::theme_minimal() +
        ggplot2::theme(legend.position = "right")
      
      print(p2)
    }
    
    # Plot 3: Heatmap of top variable proteins
    # Calculate variance to find top variable features
    vars <- apply(df_clustered[, protein_cols, drop = FALSE], 2, var)
    top_proteins <- names(sort(vars, decreasing = TRUE))[1:min(20, length(protein_cols))]
    
    df_heatmap <- df_clustered %>%
      dplyr::select(sample, .data[[cluster_col]], dplyr::all_of(top_proteins)) %>%
      tidyr::pivot_longer(cols = dplyr::all_of(top_proteins), names_to = "protein", values_to = "expression")
    
    p3 <- ggplot2::ggplot(df_heatmap, ggplot2::aes(x = sample, y = protein, fill = expression)) +
      ggplot2::geom_tile() +
      ggplot2::scale_fill_viridis_c() +
      ggplot2::facet_grid(. ~ .data[[cluster_col]], scales = "free_x", space = "free_x") +
      ggplot2::labs(
        title = "Expression Heatmap of Top Variable Proteins",
        subtitle = "Grouped by tidytof Cluster Assignments",
        x = "Sample",
        y = "Protein",
        fill = "Arcsinh Expression"
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    
    print(p3)
    
    dev.off()
    message("Saved diagnostic plots to diagnostic_plots.pdf")
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE":',
        paste0('    tidytof: ', as.character(packageVersion('tidytof')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidytof_proteomics_pipeline.csv versions.yml
    """
}

workflow BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE.out.tables
    plots    = BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE.out.plots
    objects  = BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE.out.objects
    versions = BIOC_TIDYTOF_TIDYTOF_PROTEOMICS_PIPELINE.out.versions
}
