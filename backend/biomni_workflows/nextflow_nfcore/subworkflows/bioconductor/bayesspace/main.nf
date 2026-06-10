#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BayesSpace — spatial_clustering_and_resolution_enhancement
// Perform spatial clustering and subspot-level resolution enhancement on spatial transcriptomics data.
// Input: spaceranger_outs/, rowData.csv, colData.csv, counts.csv.gz
// Container: quay.io/biocontainers/bioconductor-bayesspace:1.20.2--r45h4352baa_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BayesSpace, Matrix, SingleCellExperiment, ggplot2, patchwork, purrr
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load spatial transcriptomics data using readVisium() or manual SingleCellExperiment construction
//  * 2. [Core Analysis] Preprocess data (log-normalization and PCA) using spatialPreprocess()
//  * 3. [Core Analysis] Tune the number of clusters (q) using qTune() and qPlot()
//  * 4. [Core Analysis] Cluster spots using spatialCluster()
//  * 5. [Visualization & Output] Visualize clusters using clusterPlot()
//  * 6. [Core Analysis] Enhance resolution to subspot level using spatialEnhance()
//  * 7. [Core Analysis] Impute subspot-level gene expression using enhanceFeatures()
//  * 8. [Visualization & Output] Visualize enhanced clusters and gene expression using clusterPlot() and featurePlot()
//  * 9. [Core Analysis] Access or clean up MCMC chains using mcmcChain() and removeChain()

nextflow.enable.dsl = 2

process BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT {
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
    library(ggplot2)
    library(BayesSpace)
    library(Matrix)
    library(purrr)
    library(patchwork)
    
    # ==========================================
    # 1. Load Spatial Transcriptomics Data
    # ==========================================
    
    # Load Visium dataset if Space Ranger output directory is present
    if (dir.exists("spaceranger_outs/")) {
      message("Reading Visium data using readVisium...")
      melanoma <- readVisium("spaceranger_outs/")
      saveRDS(melanoma, "sce_visium_raw.rds")
      platform_type <- "Visium"
    } else {
      # Load manual files as specified in the user input requirements
      message("Loading manual CSV files...")
      rowData <- read.csv("rowData.csv", stringsAsFactors = FALSE)
      colData <- read.csv("colData.csv", stringsAsFactors = FALSE, row.names = 1)
      counts <- read.csv("counts.csv.gz", row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
      
      # Construct SingleCellExperiment manually
      melanoma <- SingleCellExperiment(
        assays = list(counts = as(as.matrix(counts), "dgCMatrix")),
        rowData = rowData,
        colData = colData
      )
      platform_type <- "ST"
    }
    
    # ==========================================
    # 2. Preprocess Data
    # ==========================================
    message("Preprocessing data...")
    set.seed(102)
    melanoma <- spatialPreprocess(melanoma, platform = platform_type, n.PCs = 7, n.HVGs = 2000, log.normalize = TRUE)
    
    # ==========================================
    # 3. Tune Number of Clusters (q)
    # ==========================================
    message("Tuning q...")
    melanoma <- qTune(melanoma, qs = seq(2, 10), platform = platform_type, d = 7, cores = 2)
    
    # Plot and save q-tuning results
    p_qplot <- qPlot(melanoma)
    ggsave("q_tuning_plot.pdf", plot = p_qplot, width = 7, height = 5)
    
    # ==========================================
    # 4. Spatial Clustering
    # ==========================================
    message("Performing spatial clustering...")
    set.seed(149)
    melanoma <- spatialCluster(
      melanoma, 
      q = 4, 
      platform = platform_type, 
      d = 7, 
      init.method = "mclust", 
      model = "t", 
      gamma = 2, 
      nrep = 2000, 
      burn.in = 100, 
      save.chain = TRUE
    )
    
    # Save clustered colData
    write.csv(as.data.frame(colData(melanoma)), "melanoma_clustered_metadata.csv")
    
    # ==========================================
    # 5. Visualize Spatial Clusters
    # ==========================================
    message("Visualizing spatial clusters...")
    p_cluster_default <- clusterPlot(melanoma)
    ggsave("cluster_plot_default.pdf", plot = p_cluster_default, width = 7, height = 5)
    
    p_cluster_custom <- clusterPlot(
      melanoma, 
      palette = c("purple", "red", "blue", "yellow"), 
      color = "black"
    ) + 
      theme_bw() + 
      xlab("Column") + 
      ylab("Row") + 
      labs(fill = "BayesSpace \n cluster", title = "Spatial clustering of ST_mel1_rep2")
    
    ggsave("cluster_plot_custom.pdf", plot = p_cluster_custom, width = 7, height = 5)
    
    # ==========================================
    # 6. Enhanced Resolution Clustering
    # ==========================================
    message("Enhancing resolution to subspot level...")
    melanoma.enhanced <- spatialEnhance(
      melanoma, 
      q = 4, 
      platform = platform_type, 
      d = 7, 
      model = "t", 
      gamma = 2, 
      jitter.prior = 0.3, 
      jitter.scale = 0, 
      nrep = 2000, 
      burn.in = 100, 
      save.chain = TRUE, 
      cores = 2
    )
    
    # Save enhanced colData
    write.csv(as.data.frame(colData(melanoma.enhanced)), "melanoma_enhanced_metadata.csv")
    
    p_enhanced_cluster <- clusterPlot(melanoma.enhanced)
    ggsave("cluster_plot_enhanced.pdf", plot = p_enhanced_cluster, width = 7, height = 5)
    
    # ==========================================
    # 7. Impute Subspot-Level Gene Expression
    # ==========================================
    message("Enhancing features...")
    markers <- c("ENSG00000185664", "ENSG00000116824", "ENSG00000177455", "ENSG00000108821")
    
    # Ensure markers exist in the dataset; fallback to first 4 genes if none match
    present_markers <- markers[markers %in% rownames(melanoma)]
    if (length(present_markers) == 0) {
      message("Specified markers not found in dataset. Using top 4 genes as fallback.")
      present_markers <- head(rownames(melanoma), 4)
    }
    
    melanoma.enhanced <- enhanceFeatures(
      melanoma.enhanced, 
      melanoma, 
      feature_names = present_markers, 
      nrounds = 0
    )
    
    # Save enhanced expression matrix and metrics
    write.csv(as.matrix(logcounts(melanoma.enhanced)[present_markers, , drop = FALSE]), "enhanced_expression_logcounts.csv")
    write.csv(as.data.frame(rowData(melanoma.enhanced)[present_markers, , drop = FALSE]), "enhanced_features_metrics.csv")
    
    # ==========================================
    # 8. Visualize Enhanced Gene Expression
    # ==========================================
    message("Visualizing enhanced gene expression...")
    p_feature_single <- featurePlot(melanoma.enhanced, present_markers[1])
    ggsave("feature_plot_single_enhanced.pdf", plot = p_feature_single, width = 7, height = 5)
    
    enhanced.plots <- purrr::map(present_markers, function(x) featurePlot(melanoma.enhanced, x))
    p_enhanced_grid <- patchwork::wrap_plots(enhanced.plots, ncol = 2)
    ggsave("feature_plots_enhanced_grid.pdf", plot = p_enhanced_grid, width = 12, height = 8)
    
    spot.plots <- purrr::map(present_markers, function(x) featurePlot(melanoma, x))
    p_comparison_grid <- patchwork::wrap_plots(c(enhanced.plots, spot.plots), ncol = 4)
    ggsave("feature_plots_comparison_grid.pdf", plot = p_comparison_grid, width = 16, height = 8)
    
    # ==========================================
    # 9. Access Markov Chains
    # ==========================================
    message("Accessing MCMC chains...")
    chain <- mcmcChain(melanoma)
    write.csv(as.matrix(chain[1:5, 1:5]), "mcmc_chain_sample.csv")
    
    # Save final RDS objects
    saveRDS(melanoma, "melanoma_final.rds")
    saveRDS(melanoma.enhanced, "melanoma_enhanced_final.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT":',
        paste0('    BayesSpace: ', as.character(packageVersion('BayesSpace')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_clustering_and_resolution_enhancement.csv versions.yml
    """
}

workflow BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spaceranger_outs/, rowData.csv, colData.csv, counts.csv.gz ] ]

    main:
    BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT(ch_input)

    emit:
    tables   = BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT.out.tables
    plots    = BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT.out.plots
    objects  = BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT.out.objects
    versions = BIOC_BAYESSPACE_SPATIAL_CLUSTERING_AND_RESOLUTION_ENHANCEMENT.out.versions
}
