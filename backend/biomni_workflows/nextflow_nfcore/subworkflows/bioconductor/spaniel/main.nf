#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Spaniel — spatial_transcriptomics_visium_analysis
// Import 10X Visium spatial transcriptomics data, perform quality control filtering, normalize gene expression, cluster spots, and visualize the results overlaid 
// Input: pathToTenXOuts
// Container: quay.io/biocontainers/bioconductor-spaniel:1.24.0--r45hdfd78af_0
// R packages: DropletUtils, ggplot2, scater, scran, Spaniel
// Bioconductor: 3.20 | R: 4.4
// Requires: DropletUtils, Spaniel, ggplot2, igraph, scater, scran
// Visualizations: ordination plot, UMAP plot, cluster plot
// QC: cell QC metrics, count normalization, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import Space Ranger output into a SingleCellExperiment
//  * 2. [Visualization & Output] Perform quality control visualization
//  * 3. [Visualization & Output] Filter out low-quality spots
//  * 4. [Visualization & Output] Normalize the filtered data
//  * 5. [Visualization & Output] Visualize the spatial expression of a specific gene
//  * 6. [Visualization & Output] Perform dimensionality reduction and clustering
//  * 7. [Visualization & Output] Visualize the resulting spatial clusters

nextflow.enable.dsl = 2

process BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS {
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
    .bm_deps <- c("DropletUtils", "ggplot2", "scater", "scran", "Spaniel", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(Spaniel)
    library(SummarizedExperiment)
    library(DropletUtils)
    library(scater)
    library(scran)
    library(ggplot2)
    
    # Define input path as specified in the user input requirements
    pathToTenXOuts <- "pathToTenXOuts"
    
    # Verify that the input directory exists
    if (!dir.exists(pathToTenXOuts)) {
      stop(paste("Error: The input directory", pathToTenXOuts, "does not exist."))
    }
    
    # --- Import Space Ranger output into a SingleCellExperiment ---
    sce <- createVisiumSCE(tenXDir=pathToTenXOuts, 
                                resolution="Low")
    
    # Display colData and metadata information
    print("Preview of colData:")
    print(head(colData(sce)[, c("Barcode", "pixel_x", "pixel_y")]))
    
    print("Image Dimensions:")
    print(metadata(sce)\$ImgDims)
    
    print("Grob Metadata:")
    print(metadata(sce)\$Grob)
    
    # --- Perform quality control visualization ---
    filter <- sce\$detected > 0
    
    pdf("qc_filter_plot.pdf", width = 8, height = 8)
    print(spanielPlot(object = sce,
            plotType = "NoGenes", 
            showFilter = filter, 
            techType = "Visium", 
            ptSizeMax = 3))
    dev.off()
    
    # --- Filter out low-quality spots ---
    sce <- sce[, filter]
    
    # --- Normalize the filtered data ---
    sce <- logNormCounts(sce)
    
    # --- Visualize the spatial expression of a specific gene ---
    gene <- rownames(sce)[1]
    p2 <- spanielPlot(object = sce,
            plotType = "Gene", 
            gene = gene,
            techType = "Visium", 
            ptSizeMax = 3)
    
    pdf("gene_expression_plot.pdf", width = 8, height = 8)
    print(p2)
    dev.off()
    
    # --- Perform dimensionality reduction and clustering ---
    library(scran)
    sce <- logNormCounts(sce)
    sce <- runPCA(sce)
    sce <- runUMAP(sce)
    g <- buildSNNGraph(sce, k = 70)
    
    clust <- igraph::cluster_walktrap(g)\$membership
    sce\$clust <- factor(clust)
    
    p3 <- plotReducedDim(sce, "UMAP", colour_by="clust") 
    
    pdf("umap_clustering_plot.pdf", width = 8, height = 8)
    print(p3)
    dev.off()
    
    # --- Visualize the resulting spatial clusters ---
    p4 <- spanielPlot(object = sce,
            plotType = "Cluster", 
            clusterRes = "clust",
            showFilter = NULL, 
            techType = "Visium", 
            ptSizeMax = 1, customTitle = "Section A")  
    
    pdf("spatial_clusters_plot.pdf", width = 8, height = 8)
    print(p4)
    dev.off()
    
    # Save meaningful outputs to the working directory
    saveRDS(sce, "spaniel_processed_sce.rds")
    
    cluster_export <- data.frame(
      Barcode = colData(sce)\$Barcode,
      Cluster = sce\$clust,
      pixel_x = colData(sce)\$pixel_x,
      pixel_y = colData(sce)\$pixel_y
    )
    write.csv(cluster_export, "spatial_clustering_results.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS":',
        paste0('    Spaniel: ', as.character(packageVersion('Spaniel')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_transcriptomics_visium_analysis.csv versions.yml
    """
}

workflow BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pathToTenXOuts ] ]

    main:
    BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.tables
    plots    = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.plots
    objects  = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.objects
    versions = BIOC_SPANIEL_SPATIAL_TRANSCRIPTOMICS_VISIUM_ANALYSIS.out.versions
}
