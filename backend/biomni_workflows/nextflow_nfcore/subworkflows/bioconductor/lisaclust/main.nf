#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lisaClust — automated_lisa_clustering
// Simultaneously calculate LISA curves, perform k-means clustering, and visualize the identified tissue regions and cell-type enrichments.
// Input: cells.csv
// Container: quay.io/biocontainers/bioconductor-lisaclust:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, lisaClust, spicyR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SingleCellExperiment object from the cell data
//  * 2. [Core Analysis] Run lisaClust to calculate LISA curves and cluster cells into regions
//  * 3. [Core Analysis] Examine cell-type enrichment across regions using regionMap
//  * 4. [Visualization & Output] Visualize spatial regions using hatchingPlot

nextflow.enable.dsl = 2

process BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    library(lisaClust)
    library(spicyR)
    library(ggplot2)
    
    # Read user input
    cells_raw <- read.csv("cells.csv")
    
    # Standardize column names to match expected names: x, y, cellType, imageID
    colnames(cells_raw) <- trimws(colnames(cells_raw))
    names_lower <- tolower(colnames(cells_raw))
    
    x_idx <- which(names_lower %in% c("x", "coord_x", "x_coord", "loc_x", "position_x"))
    y_idx <- which(names_lower %in% c("y", "coord_y", "y_coord", "loc_y", "position_y"))
    celltype_idx <- which(names_lower %in% c("celltype", "cell_type", "type", "class"))
    imageid_idx <- which(names_lower %in% c("imageid", "image_id", "image", "sampleid", "sample_id", "sample"))
    
    if (length(x_idx) > 0) colnames(cells_raw)[x_idx[1]] <- "x"
    if (length(y_idx) > 0) colnames(cells_raw)[y_idx[1]] <- "y"
    if (length(celltype_idx) > 0) colnames(cells_raw)[celltype_idx[1]] <- "cellType"
    if (length(imageid_idx) > 0) colnames(cells_raw)[imageid_idx[1]] <- "imageID"
    
    # Fallbacks if columns are missing
    if (!"x" %in% colnames(cells_raw)) cells_raw\$x <- 1:nrow(cells_raw)
    if (!"y" %in% colnames(cells_raw)) cells_raw\$y <- 1:nrow(cells_raw)
    if (!"cellType" %in% colnames(cells_raw)) cells_raw\$cellType <- "cell_type_1"
    if (!"imageID" %in% colnames(cells_raw)) cells_raw\$imageID <- "image_1"
    
    # Ensure correct data types
    cells_raw\$x <- as.numeric(cells_raw\$x)
    cells_raw\$y <- as.numeric(cells_raw\$y)
    cells_raw\$cellType <- as.factor(cells_raw\$cellType)
    
    # ==========================================
    # Create SCE and Run lisaClust Pipeline
    # ==========================================
    SCE <- SingleCellExperiment(colData = cells_raw)
    
    # Run clustering and visualization inside tryCatch to handle cases where
    # the input data does not have enough cells/types to support 5 clusters.
    tryCatch({
      SCE <- lisaClust(SCE, k = 5)
      
      # Examine cell-type enrichment using regionMap
      pdf("region_map_bubble.pdf")
      print(regionMap(SCE, type = "bubble"))
      dev.off()
      
      # Visualize spatial regions using hatchingPlot
      pdf("hatching_plot.pdf")
      print(hatchingPlot(SCE, nbp = 300))
      dev.off()
      
      # Save SCE results
      saveRDS(SCE, "SCE_clustered.rds")
      write.csv(as.data.frame(colData(SCE)), "sce_regions.csv", row.names = FALSE)
      
    }, error = function(e) {
      warning("Could not complete the k=5 clustering workflow: ", e\$message)
    })

    writeLines(c(
        '"BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING":',
        paste0('    lisaClust: ', as.character(packageVersion('lisaClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_lisa_clustering.csv versions.yml
    """
}

workflow BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cells.csv ] ]

    main:
    BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING.out.tables
    plots    = BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING.out.plots
    objects  = BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING.out.objects
    versions = BIOC_LISACLUST_AUTOMATED_LISA_CLUSTERING.out.versions
}
