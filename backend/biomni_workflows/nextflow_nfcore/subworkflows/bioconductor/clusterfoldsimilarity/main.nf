#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClusterFoldSimilarity — single_cell_cluster_similarity
// Compare cell clusters or annotated groups across independent single-cell datasets to identify similar populations, key contributing features, and graph-based co
// Input: singlecellObjectList
// Container: quay.io/biocontainers/bioconductor-clusterfoldsimilarity:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, ClusterFoldSimilarity, Seurat, SingleCellExperiment, dplyr
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Set active identities (e.g., cell types or cluster labels) for comparison
//  * 2. [Core Analysis] Compute similarity table using clusterFoldSimilarity()
//  * 3. [Core Analysis] Find closely-related cluster communities using findCommunitiesSimmilarity()
//  * 4. [Core Analysis] Retrieve top-n similar clusters or top-n contributing features
//  * 5. [Visualization & Output] Generate similarity heatmaps using similarityHeatmap()

nextflow.enable.dsl = 2

process BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY {
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
    .bm_deps <- c("Seurat", "ClusterFoldSimilarity", "BiocParallel", "dplyr")
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
    library(Seurat)
    library(ClusterFoldSimilarity)
    library(BiocParallel)
    library(dplyr)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a pre-processed list of Seurat or SingleCellExperiment objects
    input_file <- "singlecellObjectList.rds"
    if (!file.exists(input_file)) {
      if (file.exists("singlecellObjectList.RDS")) {
        input_file <- "singlecellObjectList.RDS"
      } else {
        stop("Error: Input file 'singlecellObjectList.rds' or 'singlecellObjectList.RDS' not found in the working directory.")
      }
    }
    
    singlecellObjectList <- readRDS(input_file)
    
    # Robustness check: Ensure "cell.type" column exists in metadata for all objects.
    # If not present, we fall back to active identities or cluster labels.
    for (i in seq_along(singlecellObjectList)) {
      if (inherits(singlecellObjectList[[i]], "Seurat")) {
        if (!"cell.type" %in% colnames(singlecellObjectList[[i]][[]])) {
          if ("seurat_clusters" %in% colnames(singlecellObjectList[[i]][[]])) {
            singlecellObjectList[[i]]\$cell.type <- singlecellObjectList[[i]]\$seurat_clusters
          } else {
            singlecellObjectList[[i]]\$cell.type <- as.character(Idents(singlecellObjectList[[i]]))
          }
        }
      } else if (inherits(singlecellObjectList[[i]], "SingleCellExperiment")) {
        if (!"cell.type" %in% colnames(colData(singlecellObjectList[[i]]))) {
          labels <- colLabels(singlecellObjectList[[i]])
          if (is.null(labels)) {
            labels <- rep("unknown", ncol(singlecellObjectList[[i]]))
          }
          singlecellObjectList[[i]]\$cell.type <- as.character(labels)
        }
      }
    }
    
    # Open PDF device to capture all automatically generated plots
    pdf("cluster_fold_similarity_plots.pdf", width = 11, height = 8.5)
    
    # -----------------------------------------------------------------------------
    # 2. Documented Workflow Execution
    # -----------------------------------------------------------------------------
    
    # Assign cell-type annotated from the original study to the cell labels for all datasets:
    for (i in seq_along(singlecellObjectList)) {
      if (inherits(singlecellObjectList[[i]], "Seurat")) {
        Idents(singlecellObjectList[[i]]) <- factor(singlecellObjectList[[i]]\$cell.type)
      } else if (inherits(singlecellObjectList[[i]], "SingleCellExperiment")) {
        colLabels(singlecellObjectList[[i]]) <- factor(singlecellObjectList[[i]]\$cell.type)
      }
    }
    
    # Generate dynamic sample names based on the number of datasets
    mySampleNames <- paste0("dataset", seq_along(singlecellObjectList))
    
    library(ClusterFoldSimilarity)
    similarityTable <- clusterFoldSimilarity(scList=singlecellObjectList, 
                                             sampleNames=mySampleNames,
                                             topN=1, 
                                             nSubsampling=24)
    
    cellCommunities <- findCommunitiesSimmilarity(similarityTable = similarityTable)
    
    # Retrieve the top 3 similar cluster for each of the clusters:
    similarityTable3Top <- clusterFoldSimilarity(scList=singlecellObjectList, 
                                                 topN=3,
                                                 sampleNames=mySampleNames, 
                                                 nSubsampling=24)
    
    # Retrieve the top 5 features that contribute the most to the similarity between each pair of clusters:
    similarityTable5TopFeatures <- clusterFoldSimilarity(scList=singlecellObjectList, 
                                                         sampleNames=mySampleNames,
                                                         topNFeatures=5, 
                                                         nSubsampling=24)
    
    similarityTableAllValues <- clusterFoldSimilarity(scList=singlecellObjectList, 
                                                      sampleNames=mySampleNames, 
                                                      topN=Inf)
    
    # Setting the number of CPUs with BiocParallel:
    BiocParallel::register(BPPARAM =  BiocParallel::MulticoreParam(workers = 6))
    
    # Prepare the variable features subset
    singlecellObjectListVariable <- lapply(singlecellObjectList, function(x){
      if (inherits(x, "Seurat")) {
        var_feats <- VariableFeatures(x)
        if (length(var_feats) > 0) {
          return(x[var_feats, ])
        }
      }
      return(x)
    })
    
    similarityTableParallel <- clusterFoldSimilarity(scList=singlecellObjectListVariable,
                                                            sampleNames=mySampleNames,
                                                            topN=1, 
                                                            nSubsampling=24,
                                                            parallel=TRUE)
    
    similarityTableParallelAll <- clusterFoldSimilarity(scList=singlecellObjectListVariable,
                                                              sampleNames=mySampleNames,
                                                              topN=Inf,
                                                              nSubsampling=24,
                                                              parallel=TRUE)
    
    main_dataset <- mySampleNames[min(2, length(mySampleNames))]
    
    ClusterFoldSimilarity::similarityHeatmap(similarityTable=similarityTableParallelAll, mainDataset=main_dataset)
    
    # Turn-off the highlighting:
    ClusterFoldSimilarity::similarityHeatmap(similarityTable=similarityTableParallelAll, mainDataset=main_dataset, highlightTop=FALSE)
    
    # Close PDF device
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    write.csv(similarityTable, "similarityTable_top1.csv", row.names = FALSE)
    write.csv(cellCommunities, "cellCommunities.csv", row.names = FALSE)
    write.csv(similarityTable3Top, "similarityTable_top3.csv", row.names = FALSE)
    write.csv(similarityTable5TopFeatures, "similarityTable_top5_features.csv", row.names = FALSE)
    write.csv(similarityTableAllValues, "similarityTable_all_values.csv", row.names = FALSE)
    write.csv(similarityTableParallel, "similarityTable_parallel_top1.csv", row.names = FALSE)
    write.csv(similarityTableParallelAll, "similarityTable_parallel_all.csv", row.names = FALSE)
    
    saveRDS(similarityTableParallelAll, "similarityTableParallelAll.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY":',
        paste0('    ClusterFoldSimilarity: ', as.character(packageVersion('ClusterFoldSimilarity')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_cluster_similarity.csv versions.yml
    """
}

workflow BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ singlecellObjectList ] ]

    main:
    BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY.out.tables
    plots    = BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY.out.plots
    objects  = BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY.out.objects
    versions = BIOC_CLUSTERFOLDSIMILARITY_SINGLE_CELL_CLUSTER_SIMILARITY.out.versions
}
