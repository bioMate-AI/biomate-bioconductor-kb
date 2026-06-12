#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lisaClust — custom_lisa_clustering
// Calculate LISA curves separately to allow custom clustering algorithms (e.g., manual k-means) before storing and plotting.
// Input: cells.csv
// Container: quay.io/biocontainers/bioconductor-lisaclust:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, lisaClust
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SingleCellExperiment object
//  * 2. [Core Analysis] Calculate LISA curves using the lisa function with specified radii
//  * 3. [Core Analysis] Perform custom clustering (e.g., kmeans) on the generated curves
//  * 4. [Core Analysis] Store the custom cluster assignments back into the object's colData

nextflow.enable.dsl = 2

process BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("lisaClust", "ggplot2")
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
    library(lisaClust)
    library(ggplot2)
    
    # 1. Read the user input file
    input_file <- "cells.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    cells <- read.csv(input_file)
    
    # Ensure coordinates are numeric and cellType/imageID are appropriate types
    cells\$x <- as.numeric(cells\$x)
    cells\$y <- as.numeric(cells\$y)
    cells\$cellType <- as.factor(cells\$cellType)
    cells\$imageID <- as.character(cells\$imageID)
    
    # 2. Create SingleCellExperiment object
    SCE <- SingleCellExperiment(colData = cells)
    
    # 3. Calculate LISA curves
    lisaCurves <- lisa(SCE, Rs = c(20, 50, 100))
    
    # 4. Perform custom clustering (kmeans)
    kM <- kmeans(lisaCurves, 2)
    
    # 5. Store the custom cluster assignments back into the object's colData
    colData(SCE)\$custom_region <- paste("region", kM\$cluster, sep = "_")
    
    # Save outputs
    # Save the LISA curves
    write.csv(as.data.frame(lisaCurves), "lisa_curves.csv", row.names = TRUE)
    
    # Save the updated colData
    write.csv(as.data.frame(colData(SCE)), "cells_with_custom_regions.csv", row.names = TRUE)
    
    # Save the SingleCellExperiment object
    saveRDS(SCE, "SCE_custom_regions.rds")
    
    # Generate and save plots
    # Plot using ggplot2
    p1 <- ggplot(as.data.frame(colData(SCE)), aes(x = x, y = y, color = custom_region)) +
      geom_point(size = 1, alpha = 0.8) +
      facet_wrap(~imageID) +
      theme_minimal() +
      labs(title = "Custom LISA Clustering Regions", x = "X Coordinate", y = "Y Coordinate", color = "Region")
    
    ggsave("custom_regions_spatial_plot.pdf", plot = p1, width = 8, height = 6)
    
    # Try hatchingPlot (requires 'region' column to be populated)
    tryCatch({
      colData(SCE)\$region <- colData(SCE)\$custom_region
      p2 <- hatchingPlot(SCE)
      ggsave("custom_regions_hatching_plot.pdf", plot = p2, width = 8, height = 6)
    }, error = function(e) {
      warning("Could not generate hatchingPlot: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING":',
        paste0('    lisaClust: ', as.character(packageVersion('lisaClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_lisa_clustering.csv versions.yml
    """
}

workflow BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cells.csv ] ]

    main:
    BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING.out.tables
    plots    = BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING.out.plots
    objects  = BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING.out.objects
    versions = BIOC_LISACLUST_CUSTOM_LISA_CLUSTERING.out.versions
}
