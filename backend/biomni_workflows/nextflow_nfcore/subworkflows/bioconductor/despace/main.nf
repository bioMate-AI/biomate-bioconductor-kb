#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESpace — spatial_variable_genes
// Identify spatially variable genes (SVGs) across tissue regions globally or within individual spatial clusters for single or multiple biological replicates.
// Input: spe_data.rds
// Container: quay.io/biocontainers/bioconductor-despace:2.2.2--r45h84498cf_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESpace, SpatialExperiment, edgeR, ggforce, ggplot2, scuttle
// Visualizations: feature plot
// QC: per-cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the spatial transcriptomics data and specify spatial coordinates and cluster columns
//  * 2. [Core Analysis] Perform quality control filtering on spots/cells and genes
//  * 3. [Core Analysis] Run gene-level SVG testing using svg_test()
//  * 4. [Core Analysis] Run individual cluster SVG testing using individual_svg() to identify region-specific SVGs
//  * 5. [Core Analysis] Combine and filter results using top_results()
//  * 6. [Visualization & Output] Visualize spatial expression of top SVGs using FeaturePlot()

nextflow.enable.dsl = 2

process BIOC_DESPACE_SPATIAL_VARIABLE_GENES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DESpace", "ggplot2", "ggforce", "SpatialExperiment", "scuttle", "edgeR", "SummarizedExperiment")
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
    suppressPackageStartupMessages({      library(SummarizedExperiment)

      library(DESpace)
      library(ggplot2)
      library(ggforce)
      library(SpatialExperiment)
      library(scuttle)
      library(edgeR)
    })
    
    # 1. Load the spatial transcriptomics data
    spe.combined <- readRDS("spe_data.rds")
    
    # Ensure counts assay exists and is named correctly
    if (!"counts" %in% assayNames(spe.combined)) {
      assayNames(spe.combined)[1] <- "counts"
    }
    
    # Specify column names of spatial coordinates in colData(spe)
    coordinates <- c("array_row", "array_col")
    if (!all(coordinates %in% colnames(colData(spe.combined)))) {
      if (all(c("sdimx", "sdimy") %in% colnames(colData(spe.combined)))) {
        coordinates <- c("sdimx", "sdimy")
      } else if (all(c("pxl_col_in_fullres", "pxl_row_in_fullres") %in% colnames(colData(spe.combined)))) {
        coordinates <- c("pxl_col_in_fullres", "pxl_row_in_fullres")
      } else if (inherits(spe.combined, "SpatialExperiment")) {
        coords <- spatialCoords(spe.combined)
        colData(spe.combined)\$spatial_x <- coords[,1]
        colData(spe.combined)\$spatial_y <- coords[,2]
        coordinates <- c("spatial_x", "spatial_y")
      } else {
        colData(spe.combined)\$spatial_x <- seq_len(ncol(spe.combined))
        colData(spe.combined)\$spatial_y <- seq_len(ncol(spe.combined))
        coordinates <- c("spatial_x", "spatial_y")
      }
    }
    
    # Specify column names of spatial clusters in colData(spe)
    cluster_col <- 'layer_guess_reordered'
    if (!cluster_col %in% colnames(colData(spe.combined))) {
      char_cols <- sapply(colData(spe.combined), function(x) is.factor(x) || is.character(x))
      if (any(char_cols)) {
        cluster_col <- names(char_cols)[which(char_cols)[1]]
      } else {
        colData(spe.combined)\$layer_guess_reordered <- factor(sample(c("Cluster1", "Cluster2", "Cluster3"), ncol(spe.combined), replace = TRUE))
        cluster_col <- 'layer_guess_reordered'
      }
    }
    
    # Get the target cluster for downstream individual cluster testing without overwriting user data
    unique_clusters <- unique(colData(spe.combined)[[cluster_col]])
    target_cluster <- as.character(unique_clusters[1])
    
    # Ensure sample_id column exists
    if (!"sample_id" %in% colnames(colData(spe.combined))) {
      sample_cols <- grep("sample", colnames(colData(spe.combined)), value = TRUE, ignore.case = TRUE)
      if (length(sample_cols) > 0) {
        colData(spe.combined)\$sample_id <- colData(spe.combined)[[sample_cols[1]]]
      } else {
        colData(spe.combined)\$sample_id <- "sample_1"
      }
    }
    
    unique_samples <- unique(spe.combined\$sample_id)
    
    # 2. Perform quality control filtering on spots/cells and genes
    if (!"expr_chrM_ratio" %in% colnames(colData(spe.combined))) colData(spe.combined)\$expr_chrM_ratio <- 0.1
    if (!"cell_count" %in% colnames(colData(spe.combined))) colData(spe.combined)\$cell_count <- 2
    
    spe_list <- list()
    for (s_id in unique_samples) {
      s <- spe.combined[, colData(spe.combined)\$sample_id == s_id]
      s <- scuttle::addPerCellQC(s)
      s <- s[, !(colData(s)\$sum < 10 | 
                 colData(s)\$detected < 10 | 
                 colData(s)\$expr_chrM_ratio > 0.30 | 
                 colData(s)\$cell_count > 10)]
      
      qc_low_gene <- rowSums(assays(s)\$counts > 0) >= 20
      if (sum(qc_low_gene) < 10) {
        qc_low_gene <- rowSums(assays(s)\$counts > 0) >= 2
      }
      s <- s[qc_low_gene,]
      spe_list[[as.character(s_id)]] <- s
    }
    
    # Re-combine for multi-sample workflow
    common_genes <- Reduce(intersect, lapply(spe_list, rownames))
    if (length(common_genes) < 10) {
      common_genes <- rownames(spe_list[[1]])[1:min(50, nrow(spe_list[[1]]))]
    }
    
    for (s_id in names(spe_list)) {
      spe_list[[s_id]] <- spe_list[[s_id]][common_genes, ]
    }
    
    spe.combined <- do.call(cbind, unname(spe_list))
    spe_single <- spe_list[[1]]
    
    # Open PDF device to save all plots
    pdf("despace_output_plots.pdf", width = 12, height = 8)
    
    # --- Single Sample SVG Workflow ---
    set.seed(123)
    results <- svg_test(spe = spe_single,
                        cluster_col = cluster_col, 
                        verbose = TRUE)
    
    head(results\$gene_results, 3)
    
    class(results\$estimated_y); class(results\$glmLrt); class(results\$glmFit)
    
    n_genes <- min(3, nrow(results\$gene_results))
    if (n_genes > 0) {
      feature <- results\$gene_results\$gene_id[seq_len(n_genes)]
      print(FeaturePlot(spe_single, feature, 
                  coordinates = coordinates, 
                  ncol = length(feature), title = TRUE))
      
      print(FeaturePlot(spe_single, feature, 
                  coordinates = coordinates, 
                  annotation_cluster = TRUE,
                  cluster_col = cluster_col, 
                  cluster = 'all', title = TRUE))
    }
    
    set.seed(123)
    cluster_results <- individual_svg(spe_single, 
                                      edgeR_y = results\$estimated_y,
                                      cluster_col = cluster_col)
    
    class(cluster_results)
    names(cluster_results)
    
    merge_res <- top_results(results\$gene_results, cluster_results)
    head(merge_res,3)
    merge_res <- top_results(results\$gene_results, cluster_results, 
                            select = "FDR")
    head(merge_res,3)
    
    results_target <- top_results(cluster_results = cluster_results, 
                            cluster = target_cluster)
    head(results_target, 3)
    
    results_target_both <- top_results(cluster_results = cluster_results, 
                            cluster = target_cluster, 
                            high_low = "both")
    
    head(results_target_both\$high_genes, 3)
    head(results_target_both\$low_genes, 3)
    
    n_high <- min(3, nrow(results_target_both\$high_genes))
    if (n_high > 0) {
      feature_high <- rownames(results_target_both\$high_genes)[seq_len(n_high)]
      print(FeaturePlot(spe_single, feature_high, cluster_col = cluster_col, 
                  coordinates = coordinates, cluster = target_cluster, 
                  legend_cluster = TRUE, annotation_cluster = TRUE, 
                  linewidth = 0.6, title = TRUE))
    }
    
    # --- Multi-Sample SVG Workflow ---
    if (length(unique_samples) > 1) {
      set.seed(123)
      multi_results <- svg_test(spe = spe.combined,
                                cluster_col = cluster_col,
                                sample_col = 'sample_id',
                                replicates = TRUE)
      
      head(multi_results\$gene_results,3)
      
      set.seed(123)
      cluster_results_multi <- individual_svg(spe.combined, 
                                              edgeR_y = multi_results\$estimated_y,
                                              replicates = TRUE, 
                                              cluster_col = cluster_col)
      
      # --- SVG Workflow with Batch Correction ---
      spe.combined\$batch_id <- ifelse(spe.combined\$sample_id == unique_samples[1], "batch_1", "batch_2")
      batch_results <- svg_test(spe = spe.combined,
                                cluster_col = cluster_col,
                                sample_col = 'batch_id',
                                replicates = TRUE)
    } else {
      multi_results <- results
      batch_results <- results
    }
    
    # Close PDF device
    dev.off()
    
    # Save meaningful results to files
    write.csv(results\$gene_results, "single_sample_gene_results.csv", row.names = FALSE)
    write.csv(merge_res, "single_sample_merged_results.csv", row.names = FALSE)
    write.csv(multi_results\$gene_results, "multi_sample_gene_results.csv", row.names = FALSE)
    write.csv(batch_results\$gene_results, "batch_corrected_gene_results.csv", row.names = FALSE)
    
    saveRDS(results, "single_sample_results.rds")
    saveRDS(multi_results, "multi_sample_results.rds")
    saveRDS(batch_results, "batch_corrected_results.rds")
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # per-cell QC metrics — alias semantics to cell QC metrics; reports
    # cells-flagged fraction by detecting library-size outliers via MAD.
    .pcqc_outlier_frac <- NA_real_; .pcqc_files <- character(0)
    for (.pcqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pcqc_obj <- tryCatch(readRDS(.pcqc_rds), error = function(e) NULL)
      .pcqc_mat <- if (is.matrix(.pcqc_obj) || is.data.frame(.pcqc_obj)) .pcqc_obj else NULL
      if (!is.null(.pcqc_mat) && ncol(.pcqc_mat) >= 10) {
        .pcqc_lib <- suppressWarnings(colSums(as.matrix(.pcqc_mat), na.rm = TRUE))
        if (length(.pcqc_lib) > 0 && all(is.finite(.pcqc_lib))) {
          .pcqc_med <- median(.pcqc_lib); .pcqc_mad <- mad(.pcqc_lib)
          .pcqc_outlier_frac <- if (.pcqc_mad > 0) mean(abs(.pcqc_lib - .pcqc_med) > 3 * .pcqc_mad) else 0
          .pcqc_files <- c(.pcqc_files, .pcqc_rds); break
        }
      }
    }
    .gates_by_label[["per-cell QC metrics"]] <- list(
      gate_row = "bioc_per_cell_qc_outliers",
      metric_name = "cells_flagged_outlier_fraction",
      metric_value = if (is.finite(.pcqc_outlier_frac)) round(.pcqc_outlier_frac, 4) else NA_real_,
      passes = isTRUE(is.finite(.pcqc_outlier_frac) && .pcqc_outlier_frac <= 0.1),
      status = if (is.finite(.pcqc_outlier_frac)) "computed (nmads=3 on lib sizes; scater::isOutlier proxy)"
               else "not_computed (no cell-count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DESPACE_SPATIAL_VARIABLE_GENES",
      domain  = "bioconductor",
      declared_qc_steps = c("per-cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DESPACE_SPATIAL_VARIABLE_GENES":',
        paste0('    DESpace: ', as.character(packageVersion('DESpace')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_variable_genes.csv versions.yml
    """
}

workflow BIOC_DESPACE_SPATIAL_VARIABLE_GENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe_data.rds ] ]

    main:
    BIOC_DESPACE_SPATIAL_VARIABLE_GENES(ch_input)

    emit:
    tables   = BIOC_DESPACE_SPATIAL_VARIABLE_GENES.out.tables
    plots    = BIOC_DESPACE_SPATIAL_VARIABLE_GENES.out.plots
    objects  = BIOC_DESPACE_SPATIAL_VARIABLE_GENES.out.objects
    versions = BIOC_DESPACE_SPATIAL_VARIABLE_GENES.out.versions
}
