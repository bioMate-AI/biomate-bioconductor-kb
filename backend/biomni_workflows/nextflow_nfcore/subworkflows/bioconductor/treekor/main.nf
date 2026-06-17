#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: treekoR — hierarchical_cell_subpopulation_analysis
// Identify robust associations between hierarchical cell subsets and clinical outcomes from single-cell cytometry data.
// Input: exprs, clusters, classes, samples
// Container: quay.io/biocontainers/bioconductor-treekor:1.18.0--r45hdfd78af_0
// R packages: SingleCellExperiment, ggtree, treekoR
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggtree, htmlwidgets, treekoR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the hierarchical tree of clusters using getClusterTree
//  * 2. [Core Analysis] Perform significance testing of cell subpopulations using testTree
//  * 3. [Core Analysis] Extract significance results using getTreeResults
//  * 4. [Visualization & Output] Visualize results interactively using plotInteractiveHeatmap
//  * 5. [Core Analysis] Extract cell proportions (%total and %parent) using getCellProp
//  * 6. [Core Analysis] Extract marker geometric means per cell type using getCellGMeans

nextflow.enable.dsl = 2

process BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("SingleCellExperiment", "ggtree", "treekoR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        
        # Load required packages
        suppressPackageStartupMessages({
          library(treekoR)
          library(ggtree)
        })
        
        # Helper function to robustly read user input files with various extensions
        read_input_file <- function(base_name) {
          extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
          for (ext in extensions) {
            path <- paste0(base_name, ext)
            if (file.exists(path)) {
              if (grepl("\\\\.rds\$", path)) {
                return(readRDS(path))
              } else if (grepl("\\\\.csv\$", path)) {
                data <- read.csv(path, header = TRUE, stringsAsFactors = FALSE)
                if (ncol(data) == 1) return(data[[1]])
                if (is.character(data[, 1]) && length(unique(data[, 1])) == nrow(data)) {
                  rownames(data) <- data[, 1]
                  data <- data[, -1, drop = FALSE]
                }
                return(as.matrix(data))
              } else if (grepl("\\\\.tsv\$|\\\\.txt\$", path)) {
                data <- read.delim(path, header = TRUE, stringsAsFactors = FALSE)
                if (ncol(data) == 1) return(data[[1]])
                if (is.character(data[, 1]) && length(unique(data[, 1])) == nrow(data)) {
                  rownames(data) <- data[, 1]
                  data <- data[, -1, drop = FALSE]
                }
                return(as.matrix(data))
              } else {
                # No extension: try RDS first, then table
                res <- tryCatch(readRDS(path), error = function(e) NULL)
                if (!is.null(res)) return(res)
                res <- tryCatch(as.matrix(read.table(path, header = TRUE)), error = function(e) NULL)
                if (!is.null(res)) return(res)
              }
            }
          }
          stop(paste("Required input file not found for:", base_name))
        }
        
        # Read user inputs
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        exprs <- as.matrix(read_input_file("exprs"))
        clusters <- as.vector(read_input_file("clusters"))
        classes <- as.vector(read_input_file("classes"))
        samples <- as.vector(read_input_file("samples"))
        
        # 1. Construct the hierarchical tree of clusters using getClusterTree (hopach)
        clust_tree <- getClusterTree(exprs,
                                     clusters,
                                     hierarchy_method="hopach")
        
        # 2. Perform significance testing of cell subpopulations using testTree
        tested_tree <- testTree(phylo=clust_tree\$clust_tree,
                              clusters=clusters,
                              samples=samples,
                              classes=classes,
                              pos_class_name=NULL)
        
        # 3. Extract significance results using getTreeResults
        res_df <- getTreeResults(tested_tree)
        write.csv(res_df, "tree_results_hopach.csv", row.names = FALSE)
        
        # 4. Visualize results interactively using plotInteractiveHeatmap
        p1 <- plotInteractiveHeatmap(tested_tree,
                               clust_med_df = clust_tree\$median_freq,
                               clusters=clusters)
        
        # Save interactive plot
        tryCatch({
          htmlwidgets::saveWidget(p1, "heatmap_hopach.html", selfcontained = TRUE)
        }, error = function(e) {
          warning("Could not save interactive heatmap as HTML: ", e\$message)
        })
        
        # 5. Construct tree with average linkage, test, and plot
        clust_tree <- getClusterTree(exprs,
                                     clusters,
                                     hierarchy_method="average")
        
        tested_tree <- testTree(clust_tree\$clust_tree,
                              clusters=clusters,
                              samples=samples,
                              classes=classes,
                              pos_class_name=NULL)
        
        p2 <- plotInteractiveHeatmap(tested_tree,
                               clust_med_df = clust_tree\$median_freq,
                               clusters=clusters)
        
        tryCatch({
          htmlwidgets::saveWidget(p2, "heatmap_average.html", selfcontained = TRUE)
        }, error = function(e) {
          warning("Could not save interactive heatmap as HTML: ", e\$message)
        })
        
        # 6. Construct tree with hopach, test with edgeR, and plot
        clust_tree <- getClusterTree(exprs,
                                     clusters,
                                     hierarchy_method="hopach")
        
        tested_tree_edgeR <- testTree(clust_tree\$clust_tree,
                              clusters=clusters,
                              samples=samples,
                              classes=classes,
                              sig_test="edgeR",
                              pos_class_name=unique(classes)[1])
        
        p3 <- plotInteractiveHeatmap(tested_tree_edgeR,
                               clust_med_df = clust_tree\$median_freq,
                               clusters=clusters)
        
        tryCatch({
          htmlwidgets::saveWidget(p3, "heatmap_edgeR.html", selfcontained = TRUE)
        }, error = function(e) {
          warning("Could not save interactive heatmap as HTML: ", e\$message)
        })
        
        # Save edgeR tested tree object
        saveRDS(tested_tree_edgeR, "tested_tree_edgeR.rds")
        
        # Extract and save edgeR FDR values
        edgeR_fdr_df <- tested_tree_edgeR\$data[, c("parent", "node", "isTip", "clusters", "FDR_parent", "FDR_total")]
        # Convert list columns to character for CSV writing compatibility
        edgeR_fdr_df\$clusters <- sapply(edgeR_fdr_df\$clusters, paste, collapse = ", ")
        write.csv(edgeR_fdr_df, "edgeR_fdr_results.csv", row.names = FALSE)
        
        
        # 7. Extract cell proportions (%total and %parent) using getCellProp
        prop_df <- getCellProp(phylo=clust_tree\$clust_tree,
                               clusters=clusters,
                               samples=samples,
                               classes=classes)
        write.csv(prop_df, "cell_proportions.csv", row.names = FALSE)
        
        
        # 8. Extract marker geometric means per cell type using getCellGMeans
        means_df <- getCellGMeans(clust_tree\$clust_tree,
                                  exprs=exprs,
                                  clusters=clusters,
                                  samples=samples,
                                  classes=classes)
        write.csv(means_df, "cell_geometric_means.csv", row.names = FALSE)
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS":',
        paste0('    treekoR: ', as.character(packageVersion('treekoR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hierarchical_cell_subpopulation_analysis.csv versions.yml
    """
}

workflow BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs, clusters, classes, samples ] ]

    main:
    BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS.out.tables
    plots    = BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS.out.plots
    objects  = BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS.out.objects
    versions = BIOC_TREEKOR_HIERARCHICAL_CELL_SUBPOPULATION_ANALYSIS.out.versions
}
