#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PIUMA — standard_tda_pipeline
// Perform a standard end-to-end Topological Data Analysis and community detection workflow on a normalized expression data frame or SummarizedExperiment.
// Input: df_TDA, dataSE
// Container: quay.io/biocontainers/bioconductor-piuma:1.5.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PIUMA, SummarizedExperiment, dplyr, ggplot2, ggrepel
// Visualizations: UMAP plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize the TDAobj from a data frame or SummarizedExperiment
//  * 2. [Core Analysis] Compute the distance matrix
//  * 3. [Core Analysis] Project the data into a low-dimensional space (lens)
//  * 4. [Core Analysis] Run the Mapper algorithm to partition data into overlapping nodes
//  * 5. [Core Analysis] Calculate the Jaccard similarity matrix between nodes
//  * 6. [Core Analysis] Perform node enrichment to average feature values per node
//  * 7. [Core Analysis] Assess network topology and predict the graph geometry
//  * 8. [Core Analysis] Perform geometry-guided community detection
//  * 9. [Visualization & Output] Export network files for Cytoscape visualization (optional)

nextflow.enable.dsl = 2

process BIOC_PIUMA_STANDARD_TDA_PIPELINE {
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
    .bm_deps <- c("PIUMA", "ggplot2", "ggrepel", "dplyr")
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
    library(PIUMA)
    library(ggplot2)
    library(ggrepel)
    library(dplyr)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    if (file.exists("df_TDA.rds")) {
      df_TDA <- readRDS("df_TDA.rds")
    } else if (file.exists("df_TDA.csv")) {
      df_TDA <- read.csv("df_TDA.csv", row.names = 1)
    } else {
      stop("Error: df_TDA (RDS or CSV) not found in the working directory.")
    }
    
    # Identify metadata columns (factors or characters) to use as outcomes dynamically
    outcome_cols <- names(df_TDA)[sapply(df_TDA, function(x) is.factor(x) | is.character(x))]
    if (length(outcome_cols) == 0) {
      # Fallback: use the first column if no character/factor columns are found
      outcome_cols <- names(df_TDA)[1]
    }
    
    color_var <- outcome_cols[1]
    facet_var <- if (length(outcome_cols) > 1) outcome_cols[2] else NULL
    
    # ==========================================
    # 2. Initialize the TDAobj
    # ==========================================
    
    # Initialize from the data frame
    TDA_obj <- makeTDAobj(df_TDA, outcome_cols)
    
    # Alternatively, to demonstrate initialization from SummarizedExperiment:
    # TDA_obj_SE <- makeTDAobjFromSE(dataSE, outcome_cols)
    
    # ==========================================
    # 3. Compute the Distance Matrix
    # ==========================================
    
    TDA_obj <- dfToDistance(TDA_obj, distMethod = "euclidean")
    
    # ==========================================
    # 4. Project the Data (Lens)
    # ==========================================
    
    TDA_obj <- dfToProjection(TDA_obj, "UMAP", nComp = 2, umapNNeigh = 25, umapMinDist = 0.3, showPlot = FALSE)
    
    # Plot and save the point-cloud projection
    df_plot <- as.data.frame(cbind(getOutcomeFact(TDA_obj), getComp(TDA_obj)), stringsAsFactors = TRUE)
    
    p_proj <- ggplot(data = df_plot, aes(x = comp1, y = comp2, color = .data[[color_var]])) +
      geom_point(size = 3) +
      theme_minimal() +
      labs(title = "UMAP Projection of Point-Cloud", x = "Component 1", y = "Component 2")
    
    if (!is.null(facet_var)) {
      p_proj <- p_proj + facet_wrap(as.formula(paste("~", facet_var)))
    }
    
    ggsave("umap_projection_plot.pdf", plot = p_proj, width = 8, height = 6)
    
    # ==========================================
    # 5. Run the Mapper Algorithm
    # ==========================================
    
    TDA_obj <- mapperCore(TDA_obj, nBins = 15, overlap = 0.3, clustMeth = "kmeans")
    
    # ==========================================
    # 6. Calculate Jaccard Similarity Matrix
    # ==========================================
    
    TDA_obj <- jaccardMatrix(TDA_obj)
    
    # ==========================================
    # 7. Perform Node Enrichment
    # ==========================================
    
    TDA_obj <- tdaDfEnrichment(TDA_obj, cbind(getScaledData(TDA_obj), getOutcome(TDA_obj)))
    
    # ==========================================
    # 8. Assess Network Topology & Predict Geometry
    # ==========================================
    
    # Calculate network entropy
    entropy_var <- if (!is.null(facet_var)) facet_var else color_var
    entropy <- checkNetEntropy(getNodeDataMat(TDA_obj)[, entropy_var])
    writeLines(as.character(entropy), "entropy.txt")
    
    # Assess scale-free model and save the diagnostic plot
    pdf("scale_free_diagnostic_plot.pdf", width = 10, height = 6)
    netModel <- checkScaleFreeModel(TDA_obj, showPlot = TRUE)
    dev.off()
    
    saveRDS(netModel, "scale_free_model.rds")
    
    # Re-verify graph structure and predict geometry class
    TDA_obj <- jaccardMatrix(TDA_obj)
    TDA_obj <- setGraph(TDA_obj)
    TDA_obj <- predict_mapper_class(TDA_obj, verbose = TRUE)
    
    # ==========================================
    # 9. Geometry-Guided Community Detection
    # ==========================================
    
    TDA_obj <- autoClusterMapper(TDA_obj, method = 'automatic')
    
    # Save clustering results
    write.csv(TDA_obj@clustering\$obs_cluster, "obs_cluster.csv", row.names = FALSE)
    write.csv(TDA_obj@clustering\$nodes_cluster, "nodes_cluster.csv", row.names = FALSE)
    
    # Plot and save the geometry-guided clustering results
    df_plot\$cell_id <- rownames(df_plot)
    df_plot <- merge(df_plot, TDA_obj@clustering\$obs_cluster, by.x = "cell_id", by.y = "obs", all.x = TRUE)
    
    group_vars <- c("cluster")
    if (!is.null(facet_var)) {
      group_vars <- c(facet_var, "cluster")
    }
    
    centroids <- df_plot %>%
      group_by(across(all_of(group_vars))) %>%
      summarize(
        n_cells = dplyr::n(),
        comp1 = mean(comp1, na.rm = TRUE),
        comp2 = mean(comp2, na.rm = TRUE),
        .groups = 'drop'
      ) %>%
      filter(!grepl("^Singleton", as.character(cluster)))
    
    p_clust <- ggplot(df_plot, aes(x = comp1, y = comp2, color = factor(cluster))) +
      geom_point(size = 3, alpha = 0.7) +
      geom_label_repel(
        data = centroids,
        aes(label = cluster, fill = factor(cluster)),
        color = "white",
        fontface = "bold",
        box.padding = 0.5,
        segment.color = NA,
        min.segment.length = 0
      ) +
      labs(color = "Cluster",
           title = "Geometry-Guided Community Detection",
           subtitle = "Cluster centroids labeled (singletons excluded)",
           caption = "Singleton clusters shown without labels") +
      theme_minimal() +
      scale_color_viridis_d(option = "D") +
      scale_fill_viridis_d(option = "D", guide = "none")
    
    if (!is.null(facet_var)) {
      p_clust <- p_clust + facet_wrap(as.formula(paste("~", facet_var)))
    }
    
    ggsave("geometry_guided_clustering_plot.pdf", plot = p_clust, width = 10, height = 8)
    
    # ==========================================
    # 10. Export Network Files for Cytoscape
    # ==========================================
    
    write.table(x = round(getJacc(TDA_obj), 3), file = "./jaccard.matrix.txt", sep = "\t", quote = FALSE, na = "", col.names = NA)
    write.table(x = getNodeDataMat(TDA_obj), file = "./nodeEnrichment.txt", sep = "\t", quote = FALSE, col.names = NA)
    
    # Save the final TDA object
    saveRDS(TDA_obj, "TDA_obj.rds")
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_PIUMA_STANDARD_TDA_PIPELINE":',
        paste0('    PIUMA: ', as.character(packageVersion('PIUMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_tda_pipeline.csv versions.yml
    """
}

workflow BIOC_PIUMA_STANDARD_TDA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ df_TDA, dataSE ] ]

    main:
    BIOC_PIUMA_STANDARD_TDA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PIUMA_STANDARD_TDA_PIPELINE.out.tables
    plots    = BIOC_PIUMA_STANDARD_TDA_PIPELINE.out.plots
    objects  = BIOC_PIUMA_STANDARD_TDA_PIPELINE.out.objects
    versions = BIOC_PIUMA_STANDARD_TDA_PIPELINE.out.versions
}
