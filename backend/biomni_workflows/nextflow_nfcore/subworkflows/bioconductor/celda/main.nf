#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: celda — celda_bi_clustering
// Perform simultaneous bi-clustering of cells and genes into modules, optimize the number of clusters (K) and modules (L), and visualize the co-expression pattern
// Input: simsce
// Container: quay.io/biocontainers/bioconductor-celda:1.26.0--r45ha27e39d_0
// R packages: celda, scater, Seurat, SingleCellExperiment, singleCellTK, tenxpbmcdata
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, celda
// Visualizations: heatmap
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter features using selectFeatures
//  * 2. [Visualization & Output] Optimize the number of modules (L) using recursiveSplitModule and plot perplexity/RPC
//  * 3. [Visualization & Output] Optimize the number of cell clusters (K) using recursiveSplitCell and plot perplexity/RPC
//  * 4. [Core Analysis] Alternatively, perform a parameter grid search using celdaGridSearch
//  * 5. [Core Analysis] Subset the best model using subsetCeldaList
//  * 6. [Core Analysis] Generate 2D embeddings using celdaUmap or celdaTsne
//  * 7. [Visualization & Output] Visualize clusters, modules, and features using plotDimReduceCluster, plotDimReduceModule, plotDimReduceFeature, celdaHeatmap, cel
//  * 8. [Core Analysis] Retrieve feature-to-module assignments using featureModuleLookup and recode cluster labels using recodeClusterZ

nextflow.enable.dsl = 2

process BIOC_CELDA_CELDA_BI_CLUSTERING {
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
    .bm_deps <- c("celda", "scater", "Seurat", "SingleCellExperiment", "singleCellTK", "tenxpbmcdata")
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
                library(celda)
                
                # ----------------------------------------------------------------------
                # 1. Read User Input
                # ----------------------------------------------------------------------
                # The pipeline expects a SingleCellExperiment object named 'simsce' in the working directory.
                input_file <- "simsce"
                if (!file.exists(input_file) && file.exists("simsce.rds")) {
                  input_file <- "simsce.rds"
                }
                
                if (!file.exists(input_file)) {
                  stop("Error: Input file 'simsce' or 'simsce.rds' not found in the working directory.")
                }
                
                message("Reading input SingleCellExperiment object...")
                simsce <- readRDS(input_file)
                
                # ----------------------------------------------------------------------
                # 2. Feature Selection
                # ----------------------------------------------------------------------
                message("Selecting features...")
                simsce <- selectFeatures(simsce)
                
                # ----------------------------------------------------------------------
                # 3. Optimize Number of Modules (L) and Cell Clusters (K) via Recursive Split
                # ----------------------------------------------------------------------
                message("Running recursive split for modules (L)...")
                moduleSplit <- recursiveSplitModule(simsce, initialL = 2, maxL = 15)
                
                pdf("module_split_diagnostics.pdf", width = 8, height = 6)
                print(plotGridSearchPerplexity(moduleSplit))
                print(plotRPC(moduleSplit))
                dev.off()
                
                message("Selecting optimal L and running recursive split for cells (K)...")
                moduleSplitSelect <- subsetCeldaList(moduleSplit, params = list(L = 10))
                
                cellSplit <- recursiveSplitCell(moduleSplitSelect, 
                                                initialK = 3, 
                                                maxK = 12, 
                                                yInit = celdaModules(moduleSplitSelect))
                
                pdf("cell_split_diagnostics.pdf", width = 8, height = 6)
                print(plotGridSearchPerplexity(cellSplit))
                print(plotRPC(cellSplit))
                dev.off()
                
                # Subset the recursive split results to the selected model
                sce_split <- subsetCeldaList(cellSplit, params = list(K = 5, L = 10))
                saveRDS(sce_split, "sce_recursive_split_selected.rds")
                
                # ----------------------------------------------------------------------
                # 4. Alternative Parameter Optimization via Grid Search
                # ----------------------------------------------------------------------
                message("Running celdaGridSearch...")
                cgs <- celdaGridSearch(simsce, 
                                       paramsTest = list(K = seq(4, 6), L = seq(9, 11)), 
                                       cores = 1, 
                                       model = "celda_CG", 
                                       nchains = 2, 
                                       maxIter = 100, 
                                       verbose = FALSE, 
                                       bestOnly = TRUE)
                
                pdf("grid_search_diagnostics.pdf", width = 8, height = 6)
                print(plotGridSearchPerplexity(cgs))
                dev.off()
                
                # Subset the grid search results to the selected model
                sce <- subsetCeldaList(cgs, params = list(K = 5, L = 10))
                saveRDS(sce, "sce_grid_search_selected.rds")
                
                # ----------------------------------------------------------------------
                # 5. Dimensionality Reduction and Visualization
                # ----------------------------------------------------------------------
                message("Calculating UMAP coordinates...")
                sce <- celdaUmap(sce)
                
                message("Generating visualization plots...")
                pdf("celda_dim_reduction_plots.pdf", width = 8, height = 8)
                
                # Plot cell populations on 2D-embeddings
                print(plotDimReduceCluster(x = sce, reducedDimName = "celda_UMAP"))
                
                # Plot module probabilities on 2D-embeddings
                print(plotDimReduceModule(x = sce, reducedDimName = "celda_UMAP", rescale = TRUE))
                
                # Plot individual feature expression
                feature_to_plot <- rownames(altExp(sce, "featureSubset"))[1]
                tryCatch({
                  print(plotDimReduceFeature(x = sce, reducedDimName = "celda_UMAP", normalize = TRUE, features = feature_to_plot))
                }, error = function(e) {
                  warning("Could not plot feature '", feature_to_plot, "': ", e\$message)
                })
                
                dev.off()
                
                # Generate Heatmaps
                pdf("celda_heatmaps.pdf", width = 10, height = 10)
                
                # Expression heatmap
                print(celdaHeatmap(sce = sce, nfeatures = 10))
                
                # Probability map showing relationships between modules and cell populations
                print(celdaProbabilityMap(sce))
                
                # Module heatmap for specific feature modules
                tryCatch({
                  print(moduleHeatmap(sce, featureModule = c(1,2), topCells = 100))
                }, error = function(e) {
                  warning("Could not generate module heatmap: ", e\$message)
                })
                
                dev.off()
                
                # ----------------------------------------------------------------------
                # 6. Utility Functions: Feature Lookup and Cluster Recoding
                # ----------------------------------------------------------------------
                message("Performing feature module lookup...")
                lookup_feat <- rownames(altExp(sce, "featureSubset"))[1]
                tryCatch({
                  lookup <- featureModuleLookup(sce, feature = lookup_feat)
                  write.csv(as.data.frame(lookup), paste0("feature_module_lookup_", lookup_feat, ".csv"), row.names = TRUE)
                }, error = function(e) {
                  warning("Could not perform lookup for '", lookup_feat, "': ", e\$message)
                })
                
                message("Recoding cluster labels...")
                tryCatch({
                  clusters <- sort(as.integer(as.character(unique(celdaClusters(sce)))))
                  sceZRecoded <- recodeClusterZ(sce, from = clusters, to = rev(clusters))
                  saveRDS(sceZRecoded, "sce_recoded.rds")
                  
                  # Save comparison table
                  recode_table <- table(celdaClusters(sce), celdaClusters(sceZRecoded))
                  write.csv(as.data.frame(recode_table), "cluster_recoding_comparison.csv")
                }, error = function(e) {
                  warning("Could not recode cluster labels: ", e\$message)
                })
                
                message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_CELDA_CELDA_BI_CLUSTERING":',
        paste0('    celda: ', as.character(packageVersion('celda')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_celda_bi_clustering.csv versions.yml
    """
}

workflow BIOC_CELDA_CELDA_BI_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simsce ] ]

    main:
    BIOC_CELDA_CELDA_BI_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CELDA_CELDA_BI_CLUSTERING.out.tables
    plots    = BIOC_CELDA_CELDA_BI_CLUSTERING.out.plots
    objects  = BIOC_CELDA_CELDA_BI_CLUSTERING.out.objects
    versions = BIOC_CELDA_CELDA_BI_CLUSTERING.out.versions
}
