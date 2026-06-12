#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CatsCradle — spatial_neighborhood_analysis
// Define cellular neighborhoods in spatial transcriptomics data, cluster them by cell type composition or aggregate gene expression, and perform ligand-receptor a
// Input: spatial_seurat.rds
// Container: quay.io/biocontainers/bioconductor-catscradle:1.4.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CatsCradle, Seurat, SpatialExperiment, SummarizedExperiment, deldir
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute cell type composition per neighborhood using computeCellTypesPerCellTypeMatrix
//  * 2. [Visualization & Output] Visualize neighborhood relationships using cellTypesPerCellTypeGraphFromCellMatrix
//  * 3. [Core Analysis] Aggregate gene expression across neighborhoods using aggregateGeneExpression

nextflow.enable.dsl = 2

process BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS {
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
    .bm_deps <- c("Seurat", "CatsCradle", "deldir", "SpatialExperiment", "SummarizedExperiment")
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
        library(Seurat)
        library(CatsCradle)
        library(deldir)
        library(SpatialExperiment)
        library(grDevices)
        
        # ----------------------------------------------------------------------
        # Stage 0: Load User Input and Extract Coordinates & Annotations
        # ----------------------------------------------------------------------
        
        # Read the user-provided spatial transcriptomics object
        spatial_obj <- readRDS("spatial_seurat.rds")
        
        # Extract cell type annotations (clusters) and spatial coordinates
        if (inherits(spatial_obj, "SpatialExperiment") || inherits(spatial_obj, "SingleCellExperiment")) {
          col_data <- SummarizedExperiment::colData(spatial_obj)
          cluster_col <- grep("cell_type|celltype|cluster|class|ident", colnames(col_data), ignore.case = TRUE, value = TRUE)
          if (length(cluster_col) > 0) {
            clusters <- col_data[[cluster_col[1]]]
            names(clusters) <- rownames(col_data)
          } else {
            clusters <- as.factor(rep("Unknown", ncol(spatial_obj)))
            names(clusters) <- colnames(spatial_obj)
          }
          
          coords <- as.data.frame(SpatialExperiment::spatialCoords(spatial_obj))
          colnames(coords) <- c("x", "y")
          
          smallXenium <- spatial_obj
        } else {
          smallXenium <- spatial_obj
          clusters <- Seurat::Idents(smallXenium)
          if (is.null(clusters) || length(unique(clusters)) <= 1) {
            meta_data <- smallXenium@meta.data
            cluster_col <- grep("cell_type|celltype|cluster|class|ident", colnames(meta_data), ignore.case = TRUE, value = TRUE)
            if (length(cluster_col) > 0) {
              clusters <- meta_data[[cluster_col[1]]]
              names(clusters) <- rownames(meta_data)
            } else {
              clusters <- as.factor(rep("Unknown", ncol(smallXenium)))
              names(clusters) <- colnames(smallXenium)
            }
          }
          
          coords <- tryCatch({
            Seurat::GetTissueCoordinates(smallXenium)
          }, error = function(e) {
            if ("x" %in% colnames(smallXenium@meta.data) && "y" %in% colnames(smallXenium@meta.data)) {
              smallXenium@meta.data[, c("x", "y")]
            } else {
              images <- names(smallXenium@images)
              if (length(images) > 0) {
                Seurat::GetTissueCoordinates(smallXenium[[images[1]]])
              } else {
                NULL
              }
            }
          })
          if (is.null(coords)) {
            stop("Could not extract spatial coordinates from Seurat object.")
          }
          colnames(coords) <- c("x", "y")
        }
        
        # Ensure clusters is a named factor
        clusters <- as.factor(clusters)
        
        # ----------------------------------------------------------------------
        # Stage 1: Compute Neighborhoods and Neighborhood Composition Matrix
        # ----------------------------------------------------------------------
        
        # Compute Delaunay triangulation to find immediate neighbors
        vt <- deldir::deldir(coords\$x, coords\$y)
        edges <- vt\$delsgs
        cell_names <- rownames(coords)
        delaunayNeighbours <- data.frame(
          nodeA = as.character(cell_names[edges\$ind1]),
          nodeB = as.character(cell_names[edges\$ind2]),
          stringsAsFactors = FALSE
        )
        
        # Compute extended neighborhoods (radius = 4)
        extendedNBHDs <- getExtendedNBHDs(delaunayNeighbours, radius = 4)
        extendedNeighbours <- collapseExtendedNBHDs(extendedNBHDs)
        
        # Construct the NBHDByCTMatrixExtended (cell types by neighborhoods matrix)
        all_cells <- names(clusters)
        unique_cts <- as.character(unique(clusters))
        NBHDByCTMatrixExtended <- matrix(0, nrow = length(unique_cts), ncol = length(all_cells),
                                         dimnames = list(unique_cts, all_cells))
        
        nodeB_celltype <- as.character(clusters[extendedNeighbours\$nodeB])
        tab <- table(nodeB_celltype, extendedNeighbours\$nodeA)
        NBHDByCTMatrixExtended[rownames(tab), colnames(tab)] <- as.matrix(tab)
        
        # Define colors for each cell type
        colours <- setNames(grDevices::rainbow(length(unique_cts)), unique_cts)
        
        # ----------------------------------------------------------------------
        # Stage 2: Run Documented CatsCradle Workflow
        # ----------------------------------------------------------------------
        
        # 1. Compute cell type composition per neighborhood
        cellTypesPerCellTypeMatrixExtended = computeCellTypesPerCellTypeMatrix (NBHDByCTMatrixExtended,clusters)
        
        # 2. Visualize neighborhood relationships
        pdf("cellTypesPerCellTypeGraph.pdf", width = 10, height = 10)
        g <- cellTypesPerCellTypeGraphFromCellMatrix (cellTypesPerCellTypeMatrixExtended, minWeight = 0.05 , colours = colours)
        plot(g)
        dev.off()
        
        # 3. Aggregate gene expression across neighborhoods (Seurat and SingleCellExperiment formats)
        agg = aggregateGeneExpression (smallXenium,extendedNeighbours, verbose= FALSE )
        agg_sce = aggregateGeneExpression (smallXenium,extendedNeighbours, verbose= FALSE , returnType= 'sce' )
        
        # 4. Ligand-receptor analysis
        ligandReceptorResults = performLigandReceptorAnalysis(smallXenium, delaunayNeighbours, clusters)
        
        # ----------------------------------------------------------------------
        # Stage 3: Save Outputs
        # ----------------------------------------------------------------------
        
        write.csv(cellTypesPerCellTypeMatrixExtended, "cellTypesPerCellTypeMatrixExtended.csv", row.names = TRUE)
        saveRDS(agg, "agg_seurat.rds")
        saveRDS(agg_sce, "agg_sce.rds")
        saveRDS(ligandReceptorResults, "ligandReceptorResults.rds")
        
        message("CatsCradle spatial neighborhood analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS":',
        paste0('    CatsCradle: ', as.character(packageVersion('CatsCradle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_neighborhood_analysis.csv versions.yml
    """
}

workflow BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spatial_seurat.rds ] ]

    main:
    BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS.out.tables
    plots    = BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS.out.plots
    objects  = BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS.out.objects
    versions = BIOC_CATSCRADLE_SPATIAL_NEIGHBORHOOD_ANALYSIS.out.versions
}
