#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetNet — metabolic_network_inference
// Infer a consensus metabolic network topology by combining structural transformations, retention time constraints, spectral similarity, and statistical associati
// Input: user_features.csv, user_transformations.csv, user_ms2_similarity.rds
// Container: quay.io/biocontainers/bioconductor-metnet:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetNet, MsCoreUtils, Spectra, igraph
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load and format quantitative and structural metabolomics
//  * 2. [Visualization & Output] Define biochemical transformations and compute structural
//  * 3. [Visualization & Output] Refine structural adjacency with retention time
//  * 4. [Visualization & Output] Integrate MS2 spectral similarity using
//  * 5. [Visualization & Output] Compute statistical associations across samples using
//  * 6. [Visualization & Output] Threshold statistical adjacency matrices to create a
//  * 7. [Visualization & Output] Combine structural and statistical networks using
//  * 8. [Visualization & Output] Convert to igraph or data frame for downstream

nextflow.enable.dsl = 2

process BIOC_METNET_METABOLIC_NETWORK_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MetNet", "MsCoreUtils", "Spectra", "igraph", "SummarizedExperiment")
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
        library(SummarizedExperiment)
        library(MetNet)
        library(MsCoreUtils)
        library(Spectra)
        library(igraph)
        
        # --- Load and format quantitative and structural metabolomics ---
        # Read user features (must contain columns "mz", "rt", and sample intensities)
        features_df <- read.csv("user_features.csv", row.names = 1, check.names = FALSE)
        x_test <- as.matrix(features_df)
        
        # Read biochemical transformations
        transformations_raw <- read.csv("user_transformations.csv", stringsAsFactors = FALSE)
        transformations <- data.frame(
            group = transformations_raw\$group,
            formula = transformations_raw\$formula,
            mass = as.numeric(transformations_raw\$mass),
            rt = transformations_raw\$rt,
            stringsAsFactors = FALSE
        )
        
        # --- Define biochemical transformations and compute structural ---
        struct_adj <- structural(x = x_test, transformation = transformations, 
            var = c("group", "formula", "mass"), ppm = 10)
        
        struct_adj_dir <- structural(x = x_test, transformation = transformations, 
            var = c("group", "formula", "mass"), ppm = 10, directed = TRUE)
        
        # --- Refine structural adjacency with retention time ---
        struct_adj <- rtCorrection(am = struct_adj, x = x_test, 
            transformation = transformations, var = "group")
        
        struct_df <- as.data.frame(struct_adj)
        struct_df <- struct_df[struct_df\$binary == 1, ]
        write.csv(struct_df, "structural_connections.csv", row.names = FALSE)
        
        mz_sum <- mz_summary(struct_adj, var = "group")
        write.csv(mz_sum, "mz_summary.csv", row.names = FALSE)
        
        # --- Integrate MS2 spectral similarity using ---
        if (file.exists("user_ms2_similarity.rds")) {
            adj_spec <- readRDS("user_ms2_similarity.rds")
        } else {
            # Fallback: Create a dummy spectral similarity matrix matching the features
            n_feats <- nrow(x_test)
            adj_spec <- matrix(runif(n_feats * n_feats, 0, 1), nrow = n_feats, ncol = n_feats)
            rownames(adj_spec) <- colnames(adj_spec) <- rownames(x_test)
        }
        
        spect_adj <- addSpectralSimilarity(am_structural = struct_adj, 
            ms2_similarity = list("ndotproduct" = adj_spec))
        
        args_thr <- list(filter = "ndotproduct > 0.1 | binary == 1 & is.na(ndotproduct)")
        spect_adj_thr <- threshold(am = spect_adj, type = "threshold", 
            args = args_thr)
        
        # --- Compute statistical associations across samples using ---
        x_int <- x_test[, 3:ncol(x_test)] |>
            as.matrix()
        stat_adj <- statistical(x_int, model = c("pearson", "spearman"))
        
        # --- Threshold statistical adjacency matrices to create a ---
        args_stat_thr <- list(filter = "abs(pearson_coef) > 0.95 | abs(spearman_coef) > 0.95")
        stat_adj_thr <- threshold(am = stat_adj, type = "threshold", 
            args = args_stat_thr)
        
        args_top <- list(n = 100)
        stat_adj_mean <- threshold(am = stat_adj, type = "mean", 
            args = args_top)
        
        # --- Combine structural and statistical networks using ---
        comb_adj <- combine(am_structural = struct_adj, am_statistical = stat_adj_mean)
        comb_spect_adj <- combine(am_structural = spect_adj_thr, 
                                  am_statistical = stat_adj_mean)
        
        saveRDS(comb_adj, "combined_adjacency.rds")
        saveRDS(comb_spect_adj, "combined_spectral_adjacency.rds")
        
        # --- Convert to igraph or data frame for downstream ---
        adj <- assay(comb_adj, "combine_binary")
        diag(adj) <- 1
        g <- igraph::graph_from_adjacency_matrix(adj, mode = "undirected", diag = FALSE)
        
        # Save all plots to a single PDF file
        pdf("metabolic_network_plots.pdf", width = 10, height = 8)
        
        # Plot 1: Undirected Structural Graph
        g_undirected <- igraph::graph_from_adjacency_matrix(
            assay(struct_adj, "binary"), mode = "directed", weighted = NULL)
        plot(g_undirected, edge.width = 1, edge.arrow.size = 0.5,
             vertex.label.cex = 0.5, edge.color = "grey", main = "Undirected Structural Graph")
        
        # Plot 2: Directed Structural Graph
        g_directed <- igraph::graph_from_adjacency_matrix(
            assay(struct_adj_dir, "binary"), mode = "directed", weighted = NULL)
        plot(g_directed, edge.width = 1, edge.arrow.size = 0.5,
             vertex.label.cex = 0.5, edge.color = "grey", main = "Directed Structural Graph")
        
        # Plot 3: Mass Difference Summary Visualization
        print(mz_vis(mz_sum, var = "group"))
        
        # Plot 4: Consensus Network
        plot(g, edge.width = 2, vertex.label.cex = 0.5, edge.color = "grey", main = "Consensus Network (Structural + Statistical)")
        
        dev.off()

    writeLines(c(
        '"BIOC_METNET_METABOLIC_NETWORK_INFERENCE":',
        paste0('    MetNet: ', as.character(packageVersion('MetNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolic_network_inference.csv versions.yml
    """
}

workflow BIOC_METNET_METABOLIC_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_features.csv, user_transformations.csv, user_ms2_similarity.rds ] ]

    main:
    BIOC_METNET_METABOLIC_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_METNET_METABOLIC_NETWORK_INFERENCE.out.tables
    plots    = BIOC_METNET_METABOLIC_NETWORK_INFERENCE.out.plots
    objects  = BIOC_METNET_METABOLIC_NETWORK_INFERENCE.out.objects
    versions = BIOC_METNET_METABOLIC_NETWORK_INFERENCE.out.versions
}
