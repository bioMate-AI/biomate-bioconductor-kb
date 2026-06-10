#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COTAN — cell_clustering_and_dea
// Cluster cells based on expression uniformity and perform differential expression analysis (DEA) on the resulting clusters.
// Input: obj, vignette.split.clusters
// Container: quay.io/biocontainers/bioconductor-cotan:2.10.3--r45hdfd78af_0
// R packages: COTAN, ComplexHeatmap, zeallot
// Bioconductor: 3.20 | R: 4.4
// Requires: COTAN, ComplexHeatmap, conflicted, zeallot
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Calibrate the COTAN model without full COEX calculation to save time. 2. Load or establish cell clusterizations. 3. Run Differenti

nextflow.enable.dsl = 2

process BIOC_COTAN_CELL_CLUSTERING_AND_DEA {
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
    .bm_deps <- c("COTAN", "ComplexHeatmap", "zeallot")
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
            library(COTAN)
            library(zeallot)
            library(ComplexHeatmap)
            
            # Resolve conflicts for the multi-assignment operator
            conflicted::conflict_prefer("%<-%", "zeallot")
            
            # Enable parallel processing if supported
            options(parallelly.fork.enable = TRUE)
            
            # -----------------------------------------------------------------------------
            # 1. Load User Inputs
            # -----------------------------------------------------------------------------
            
            # Read the cleaned COTAN object from the working directory
            if (file.exists("obj.RDS")) {
              obj <- readRDS("obj.RDS")
            } else if (file.exists("obj.rds")) {
              obj <- readRDS("obj.rds")
            } else {
              stop("Error: Cleaned COTAN object ('obj.RDS' or 'obj.rds') not found in the working directory.")
            }
            
            # Read the pre-calculated clusterization factor from the working directory
            if (file.exists("vignette.split.clusters.RDS")) {
              vignette.split.clusters <- readRDS("vignette.split.clusters.RDS")
            } else if (file.exists("vignette.split.clusters.rds")) {
              vignette.split.clusters <- readRDS("vignette.split.clusters.rds")
            } else {
              stop("Error: Pre-calculated clusterization factor ('vignette.split.clusters.RDS' or 'vignette.split.clusters.rds') not found.")
            }
            
            # Ensure the clusterization is properly formatted
            vignette.split.clusters <- asClusterization(vignette.split.clusters, allCells = getCells(obj))
            
            # -----------------------------------------------------------------------------
            # 2. Establish Helper Variables and Metadata
            # -----------------------------------------------------------------------------
            
            # Define marker genes for cortical layers
            layersGenes <- list(
              "L1"   = c("Reln", "Lhx5"),
              "L2/3" = c("Cux1", "Satb2"),
              "L4"   = c("Rorb", "Sox5"),
              "L5/6" = c("Bcl11b", "Fezf2"),
              "Prog" = c("Hes1", "Vim")
            )
            
            # Filter marker genes to only include those present in the COTAN object
            all_genes <- getGenes(obj)
            layersGenes <- lapply(layersGenes, function(g) intersect(g, all_genes))
            layersGenes <- layersGenes[sapply(layersGenes, length) > 0]
            
            # Ensure the "origin" condition exists in the object metadata
            if (!"origin" %in% getConditionNames(obj)) {
              dummy_origin <- rep("Other", getNumCells(obj))
              names(dummy_origin) <- getCells(obj)
              obj <- addCondition(obj, condName = "origin", conditions = dummy_origin)
            }
            
            # Define placeholders for uniform clustering merging
            outDir <- "."
            
            # Initialize splitClusters variable before niceFactorLevels is called
            splitClusters <- vignette.split.clusters
            
            # -----------------------------------------------------------------------------
            # 3. Execute Documented Workflow
            # -----------------------------------------------------------------------------
            
            # Calibrate the COTAN model without full COEX calculation to save time
            obj <- proceedToCoex( obj, calcCoex = FALSE, optimizeForSpeed = TRUE, cores = 3L, deviceStr = "cuda" )
            
            # To ensure clName = "merge" exists for findClustersMarkers, we add a placeholder
            vignette.merge.coexDF <- DEAOnClusters(obj, clusters = vignette.split.clusters)
            obj <- addClusterization(obj, clName = "merge", clusters = vignette.split.clusters, coexDF = vignette.merge.coexDF, override = TRUE)
            
            # Run Differential Expression Analysis (DEA) on clusters
            vignette.split.coexDF <- DEAOnClusters(obj, clusters = vignette.split.clusters)
            
            # Add clusterization to the COTAN object
            obj <- addClusterization( obj, clName = "split", clusters = vignette.split.clusters, coexDF = vignette.split.coexDF, override = FALSE )
            
            # Reorder and manipulate clusterizations
            splitClusters <- niceFactorLevels(splitClusters)
            c(splitClusters, splitCoexDF, perm) %<-% reorderClusterization( obj, clName = "split", reverse = FALSE, coexDF = NULL, useDEA = TRUE, distance = NULL, hclustMethod = "ward.D2" )
            
            # Add the reordered clusterization back to the object
            obj <- addClusterization(obj, clName = "split", clusters = splitClusters, coexDF = splitCoexDF, override = TRUE)
            
            # Plot cluster dendrograms
            treePlot <- clustersTreePlot( obj, kCuts = 2L, clName = "split", useDEA = TRUE )[["dend"]]
            
            # Plot marker gene relevance heatmaps
            c(splitHeatmap, splitScoreDF, splitPValueDF) %<-% clustersMarkersHeatmapPlot( obj, groupMarkers = layersGenes, clName = "split", kCuts = 2L, adjustmentMethod = "bonferroni", condNameList = list("origin") )
            
            # Find differentially expressed marker genes for clusters
            mergeClusterMarkers <- findClustersMarkers( obj, clName = "merge", n = 5L, markers = unlist(layersGenes), adjustmentMethod = "bonferroni" )
            
            # Merge uniform clusters and extract summary statistics
            c(mergedClusters, mergedCoexDF) %<-% mergeUniformCellsClusters( obj, clusters = splitClusters, optimizeForSpeed = TRUE, deviceStr = "cuda", cores = 6L, useDEA = TRUE, saveObj = TRUE, outDir = outDir )
            
            # -----------------------------------------------------------------------------
            # 4. Save Outputs
            # -----------------------------------------------------------------------------
            
            # Save updated COTAN object
            saveRDS(obj, file = "updated_cotan_obj.RDS")
            
            # Save data frames and tables
            write.csv(as.data.frame(vignette.split.coexDF), "split_coexDF.csv", row.names = TRUE)
            write.csv(as.data.frame(splitScoreDF), "splitScoreDF.csv", row.names = TRUE)
            write.csv(as.data.frame(splitPValueDF), "splitPValueDF.csv", row.names = TRUE)
            write.csv(as.data.frame(mergeClusterMarkers), "mergeClusterMarkers.csv", row.names = TRUE)
            write.csv(as.data.frame(mergedCoexDF), "mergedCoexDF.csv", row.names = TRUE)
            saveRDS(mergedClusters, "mergedClusters.RDS")
            
            # Save plots to PDF
            pdf("dendrogram_plot.pdf", width = 8, height = 6)
            plot(treePlot)
            dev.off()
            
            pdf("split_heatmap.pdf", width = 10, height = 8)
            ComplexHeatmap::draw(splitHeatmap)
            dev.off()
            
            message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_COTAN_CELL_CLUSTERING_AND_DEA":',
        paste0('    COTAN: ', as.character(packageVersion('COTAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_clustering_and_dea.csv versions.yml
    """
}

workflow BIOC_COTAN_CELL_CLUSTERING_AND_DEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ obj, vignette.split.clusters ] ]

    main:
    BIOC_COTAN_CELL_CLUSTERING_AND_DEA(ch_input)

    emit:
    tables   = BIOC_COTAN_CELL_CLUSTERING_AND_DEA.out.tables
    plots    = BIOC_COTAN_CELL_CLUSTERING_AND_DEA.out.plots
    objects  = BIOC_COTAN_CELL_CLUSTERING_AND_DEA.out.objects
    versions = BIOC_COTAN_CELL_CLUSTERING_AND_DEA.out.versions
}
