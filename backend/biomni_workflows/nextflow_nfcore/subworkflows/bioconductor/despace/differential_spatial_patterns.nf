#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESpace — differential_spatial_patterns
// Identify genes with differential spatial expression patterns (DSPs) across multiple experimental conditions or time points.
// Input: spe_multi_cond.rds
// Container: quay.io/biocontainers/bioconductor-despace:2.2.2--r45h84498cf_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESpace, SpatialExperiment, dplyr, edgeR, ggplot2, patchwork, purrr, reshape2, tibble, tidyr
// Visualizations: feature plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the multi-sample, multi-condition spatial transcriptomics data
//  * 2. [Core Analysis] Run gene-level DSP testing using dsp_test()
//  * 3. [Core Analysis] Run individual cluster DSP testing using individual_dsp()
//  * 4. [Input & Preparation] (Optional) Create a custom design matrix using natural splines to model continuous time trends and run dsp_test()
//  * 5. [Visualization & Output] Visualize spatial expression and predicted abundance trends using FeaturePlot() and ggplot2

nextflow.enable.dsl = 2

process BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS {
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
    suppressMessages({
      library(DESpace)
      library(ggplot2)
      library(SpatialExperiment)
      library(reshape2)
      library(dplyr)
      library(tidyr)
      library(purrr)
      library(tibble)
      library(patchwork)
      library(splines)
      library(edgeR)
    })
    
    # Set seed for reproducibility
    set.seed(123)
    
    # ==========================================
    # 1. Load the multi-sample, multi-condition spatial transcriptomics data
    # ==========================================
    if (!file.exists("spe_multi_cond.rds")) {
      stop("Required input file 'spe_multi_cond.rds' not found in the working directory.")
    }
    
    spe <- readRDS("spe_multi_cond.rds")
    
    # Define column names for spatial clusters, sample IDs, and condition labels dynamically
    spatial_cluster <- if ("Banksy_smooth" %in% colnames(colData(spe))) "Banksy_smooth" else grep("cluster", colnames(colData(spe)), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(spatial_cluster)) spatial_cluster <- "spatial_cluster"
    
    condition_col <- if ("condition" %in% colnames(colData(spe))) "condition" else grep("condition", colnames(colData(spe)), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(condition_col)) condition_col <- "condition"
    
    sample_col <- if ("sample_id" %in% colnames(colData(spe))) "sample_id" else grep("sample", colnames(colData(spe)), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(sample_col)) sample_col <- "sample_id"
    
    # Ensure metadata columns are factors for downstream modeling and levels extraction
    spe[[spatial_cluster]] <- as.factor(spe[[spatial_cluster]])
    spe[[sample_col]] <- as.factor(spe[[sample_col]])
    spe[[condition_col]] <- as.factor(spe[[condition_col]])
    
    # Determine spatial coordinates column names dynamically
    coords <- spatialCoordsNames(spe)
    if (length(coords) < 2) {
      if (all(c("sdimx", "sdimy") %in% colnames(colData(spe)))) {
        coords <- c("sdimx", "sdimy")
      } else if (all(c("array_row", "array_col") %in% colnames(colData(spe)))) {
        coords <- c("array_row", "array_col")
      } else {
        coords <- c("pxl_col_in_fullres", "pxl_row_in_fullres")
      }
    }
    
    # ==========================================
    # 2. Run gene-level DSP testing using dsp_test()
    # ==========================================
    message("Running gene-level DSP testing...")
    results <- dsp_test(spe = spe,
                        cluster_col = spatial_cluster,
                        sample_col = sample_col,
                        condition_col = condition_col,
                        test = 'QLF',
                        verbose = TRUE)
    
    # Display and save gene-level results
    print(head(results\$gene_results, 2))
    write.csv(results\$gene_results, "dsp_gene_results.csv", row.names = FALSE)
    
    print(class(results\$estimated_y))
    print(class(results\$glmQLFit))    # or results\$glmFit depending on test
    print(class(results\$glmQLFTest))  # or results\$glmLRT depending on test
    
    # Save the full results object
    saveRDS(results, "dsp_results.rds")
    
    # ==========================================
    # 3. Run individual cluster DSP testing using individual_dsp()
    # ==========================================
    message("Running individual cluster DSP testing...")
    cluster_results <- individual_dsp(spe,
                                      cluster_col = spatial_cluster,
                                      sample_col = sample_col,
                                      condition_col = condition_col)
    
    print(class(cluster_results))
    print(names(cluster_results))
    
    # Print head of target cluster results if it exists, otherwise the first available cluster
    target_cl <- if ("2" %in% names(cluster_results)) "2" else names(cluster_results)[1]
    if (!is.null(target_cl)) {
      print(cluster_results[[target_cl]] |> head(n = 4))
    }
    
    # Save individual cluster results
    saveRDS(cluster_results, "dsp_individual_cluster_results.rds")
    for (cl in names(cluster_results)) {
      write.csv(cluster_results[[cl]], paste0("dsp_individual_cluster_", cl, "_results.csv"), row.names = FALSE)
    }
    
    # ==========================================
    # 4. DSP Workflow with Smooth Splines for Time Trends
    # ==========================================
    message("Running DSP workflow with smooth splines...")
    metadata <- expand.grid(sample_id = levels(spe[[sample_col]]),
                            cluster = levels(spe[[spatial_cluster]])
                            )
    
    # Extract condition for each sample_id to derive a continuous time variable generically
    sample_conditions <- colData(spe)[[condition_col]][match(metadata\$sample_id, colData(spe)[[sample_col]])]
    metadata\$day <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", sample_conditions)))
    if (any(is.na(metadata\$day))) {
      metadata\$day <- as.numeric(as.factor(sample_conditions))
    }
    
    design_model <- model.matrix(~ cluster * ns(day, df = 2), 
                                 data = metadata)
    rownames(design_model) <- paste0(metadata\$sample_id, "_",
                                     metadata\$cluster)
    
    results_spline <- dsp_test(spe,
                               design = design_model,
                               cluster_col = spatial_cluster,
                               sample_col = sample_col,
                               condition_col = condition_col,
                               verbose = TRUE)
    
    write.csv(results_spline\$gene_results, "dsp_spline_gene_results.csv", row.names = FALSE)
    
    # ==========================================
    # 4b. Single-Cluster Spline DSP Workflow
    # ==========================================
    message("Running single-cluster spline DSP workflow...")
    new_cluster <- factor(ifelse(spe[[spatial_cluster]] %in% target_cl, target_cl, 'Other'))
    metadata2 <- expand.grid(sample_id = levels(spe[[sample_col]]),
                             cluster = levels(new_cluster))
    
    sample_conditions2 <- colData(spe)[[condition_col]][match(metadata2\$sample_id, colData(spe)[[sample_col]])]
    metadata2\$day <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", sample_conditions2)))
    if (any(is.na(metadata2\$day))) {
      metadata2\$day <- as.numeric(as.factor(sample_conditions2))
    }
    
    design_model2 <- model.matrix(~ cluster * ns(day, df = 2),
                                  data = metadata2)
    rownames(design_model2) <- paste0(metadata2\$sample_id, "_",
                                      metadata2\$cluster)
    
    spe\$cluster2 <- new_cluster
    results2 <- dsp_test(spe,
                         design = design_model2,
                         cluster_col = "cluster2",
                         sample_col = sample_col,
                         condition_col = condition_col,
                         verbose = TRUE)
    
    res_global2 <- results2\$gene_results
    print(table(res_global2\$FDR <= 0.05))
    write.csv(res_global2, "dsp_single_cluster_spline_results.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Visualize spatial expression and predicted abundance trends
    # ==========================================
    message("Generating visualization plots...")
    
    # Identify the top DSP gene from the single-cluster spline results
    feature <- results2\$gene_results\$gene_id[1]
    if (is.null(feature) || is.na(feature)) {
      feature <- rownames(spe)[1]
    }
    
    # 5.1 Predicted Abundance Trend Plot
    fitted_values <- results2[["glmQLFit"]][["fitted.values"]]
    if (!is.null(feature) && feature %in% rownames(fitted_values)) {
      m <- melt(fitted_values[feature,]) |>
        rownames_to_column("row_name_column") |>
        setNames(c("sample_id_cluster", "fitted"))
      
      m\$day <- metadata2\$day[match(m\$sample_id_cluster, rownames(design_model2))]
      m\$cluster <- metadata2\$cluster[match(m\$sample_id_cluster, rownames(design_model2))]
      
      plt <- ggplot(m, aes(x = day, y = fitted, group = cluster, colour = cluster)) +
        geom_jitter(size = 3, width = 0.2, height = 0) +
        scale_y_sqrt() +
        labs(title = paste("Predicted Abundance Trend for", feature),
             x = "Time / Condition (Numeric)",
             y = "Fitted Values (Square Root Scale)") +
        scale_x_continuous(breaks = unique(m\$day)) +
        theme_minimal()
      
      ggsave("predicted_abundance_trend.pdf", plot = plt, width = 6, height = 4)
    }
    
    # 5.2 Spatial Expression FeaturePlot
    sample_ids <- levels(spe[[sample_col]])
    plots <- lapply(sample_ids, function(sample_id) {
      spe_j <- spe[, colData(spe)[[sample_col]] == sample_id]
      plot <- FeaturePlot(spe_j, 
                          feature = feature, 
                          cluster_col = spatial_cluster, 
                          coordinates = coords, 
                          platform = "Stereo-seq", 
                          point_size = 0.1, 
                          diverging = TRUE, 
                          annotation_cluster = TRUE, 
                          title = TRUE) +
              ggtitle(sample_id)
      return(plot)
    })
    
    combined_plot <- wrap_plots(plots, ncol = 2) + plot_layout(guides = 'collect')
    ggsave("spatial_expression_featureplot.pdf", plot = combined_plot, width = 10, height = 8)
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS":',
        paste0('    DESpace: ', as.character(packageVersion('DESpace')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_spatial_patterns.csv versions.yml
    """
}

workflow BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe_multi_cond.rds ] ]

    main:
    BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS(ch_input)

    emit:
    tables   = BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS.out.tables
    plots    = BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS.out.plots
    objects  = BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS.out.objects
    versions = BIOC_DESPACE_DIFFERENTIAL_SPATIAL_PATTERNS.out.versions
}
