#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sincell — hierarchy_reconstruction_and_visualization
// Build and visualize cell-state hierarchies from a single-cell expression matrix using dimensionality reduction, optional clustering, and graph-building algorith
// Input: ExpressionMatrix
// Container: quay.io/biocontainers/bioconductor-sincell:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: igraph, sincell
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Log-transform and filter the expression matrix
//  * 2. [Core Analysis] Initialize the Sincell object
//  * 3. [Core Analysis] Perform dimensionality reduction (e.g., ICA, PCA, t-SNE)
//  * 4. [Core Analysis] (Optional) Cluster cells to group highly similar cells
//  * 5. [Input & Preparation] Build the cell-state hierarchy graph (MST, SST, or IMC)
//  * 6. [Visualization & Output] Extract the hierarchy graph for visualization

nextflow.enable.dsl = 2

process BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION {
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
    .bm_deps <- c("sincell", "igraph")
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
    library(sincell)
    library(igraph)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a file named "ExpressionMatrix" (or with .csv/.tsv/.rds extension)
    # in the working directory.
    if (file.exists("ExpressionMatrix.rds")) {
      ExpressionMatrix <- readRDS("ExpressionMatrix.rds")
    } else if (file.exists("ExpressionMatrix.csv")) {
      ExpressionMatrix <- as.matrix(read.csv("ExpressionMatrix.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("ExpressionMatrix.tsv")) {
      ExpressionMatrix <- as.matrix(read.delim("ExpressionMatrix.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("ExpressionMatrix")) {
      ExpressionMatrix <- as.matrix(read.table("ExpressionMatrix", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Input file 'ExpressionMatrix' (or with .csv/.tsv/.rds extension) not found in the working directory.")
    }
    
    # Ensure ExpressionMatrix is a matrix
    ExpressionMatrix <- as.matrix(ExpressionMatrix)
    
    # -----------------------------------------------------------------------------
    # 2. Log-transform and Filter the Expression Matrix
    # -----------------------------------------------------------------------------
    EMlog <- unique(
      log(ExpressionMatrix[which(apply(ExpressionMatrix, 1, var) > 0), ] + 1)
    )
    EMlog <- as.matrix(EMlog[as.logical(apply(!is.nan(EMlog), 1, sum)), ])
    
    # -----------------------------------------------------------------------------
    # 3. Initialize the Sincell Object
    # -----------------------------------------------------------------------------
    SO <- sc_InitializingSincellObject(EMlog)
    
    # -----------------------------------------------------------------------------
    # 4. Perform Dimensionality Reduction (ICA, 2D)
    # -----------------------------------------------------------------------------
    SO <- sc_DimensionalityReductionObj(SO, method = "ICA", dim = 2)
    cellsLowDimensionalSpace_ICA <- SO[["cellsLowDimensionalSpace"]]
    
    # -----------------------------------------------------------------------------
    # 5. Cluster Cells (K-NN Clustering)
    # -----------------------------------------------------------------------------
    SO <- sc_clusterObj(SO, clust.method = "knn", mutual = TRUE, k = 5)
    cellsClustering_KNN <- SO[["cellsClustering"]]
    
    # -----------------------------------------------------------------------------
    # 6. Build the Cell-State Hierarchy Graph (SST)
    # -----------------------------------------------------------------------------
    SO <- sc_GraphBuilderObj(SO, graph.algorithm = "SST", 
                             graph.using.cells.clustering = TRUE)
    cellstateHierarchy_SST_clustKNN <- SO[["cellstateHierarchy"]]
    
    # -----------------------------------------------------------------------------
    # 7. Save Outputs and Visualizations
    # -----------------------------------------------------------------------------
    
    # Save the complete Sincell object and the hierarchy graph as RDS
    saveRDS(SO, "sincell_object.rds")
    saveRDS(cellstateHierarchy_SST_clustKNN, "cellstateHierarchy_SST_clustKNN.rds")
    
    # Save low-dimensional coordinates
    write.csv(t(cellsLowDimensionalSpace_ICA), "cells_low_dimensional_space_ICA.csv", row.names = TRUE)
    
    # Save clustering membership if available
    if (!is.null(cellsClustering_KNN)) {
      if (inherits(cellsClustering_KNN, "communities")) {
        memb <- igraph::membership(cellsClustering_KNN)
        write.csv(data.frame(Cell = names(memb), Cluster = as.vector(memb)), 
                  "cells_clustering_membership.csv", row.names = FALSE)
      } else {
        saveRDS(cellsClustering_KNN, "cells_clustering_object.rds")
      }
    }
    
    # Plot 1: Low-dimensional space (ICA)
    pdf("cells_low_dimensional_space_ICA.pdf", width = 7, height = 7)
    plot(t(cellsLowDimensionalSpace_ICA), col = "black",
         xlab = "First axis after dimensionality reduction",
         ylab = "Second axis after dimensionality reduction",
         main = "ICA Dimensionality Reduction (2D)")
    text(t(cellsLowDimensionalSpace_ICA), colnames(cellsLowDimensionalSpace_ICA),
         pos = 3, cex = 0.5, col = "black")
    dev.off()
    
    # Plot 2: Cell-state hierarchy graph
    pdf("cell_state_hierarchy_SST_clustKNN.pdf", width = 8, height = 8)
    vertex.size <- 5
    edge.color <- "black"
    edge.width <- 2
    vertex.label.cex <- 0.4
    vertex.label.dist <- 1
    vertex.label <- igraph::V(cellstateHierarchy_SST_clustKNN)\$name
    layout.graph <- igraph::layout.kamada.kawai
    
    igraph::plot.igraph(cellstateHierarchy_SST_clustKNN,
                        main = "SST - KNN cluster Hierarchy",
                        vertex.label = vertex.label,
                        vertex.size = vertex.size,
                        edge.color = edge.color,
                        edge.width = edge.width,
                        vertex.label.cex = vertex.label.cex,
                        layout = layout.graph)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION":',
        paste0('    sincell: ', as.character(packageVersion('sincell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hierarchy_reconstruction_and_visualization.csv versions.yml
    """
}

workflow BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionMatrix ] ]

    main:
    BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION.out.tables
    plots    = BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION.out.plots
    objects  = BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION.out.objects
    versions = BIOC_SINCELL_HIERARCHY_RECONSTRUCTION_AND_VISUALIZATION.out.versions
}
