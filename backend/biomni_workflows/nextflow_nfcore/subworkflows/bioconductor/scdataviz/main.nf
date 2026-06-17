#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDataviz — cytof_fcs_workflow
// Process raw FCS files, perform PCA and UMAP, cluster cells, and identify marker signatures.
// Input: filelist, metadata
// Container: quay.io/biocontainers/bioconductor-scdataviz:1.20.0--r45hdfd78af_0
// R packages: cowplot, flowCore, kableExtra, knitr, PCAtools, scDataviz
// Bioconductor: 3.20 | R: 4.4
// Requires: PCAtools, cowplot, flowCore, scDataviz
// Visualizations: PCA plot, UMAP plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs
//  * 2. [Visualization & Output] Preprocess and Transform FCS Files
//  * 3. [Visualization & Output] Perform PCA
//  * 4. [Visualization & Output] Perform UMAP
//  * 5. [Visualization & Output] Create Contour Plots
//  * 6. [Visualization & Output] Show Marker Expression Across Layout
//  * 7. [Visualization & Output] Shade Cells by Metadata
//  * 8. [Visualization & Output] Find Clusters via k-Nearest Neighbours
//  * 9. [Visualization & Output] Plot Marker Expression Per Cluster
//  * 10. [Visualization & Output] Determine Enriched Markers & Signatures

nextflow.enable.dsl = 2

process BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW {
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
    .bm_deps <- c("cowplot", "flowCore", "kableExtra", "knitr", "PCAtools", "scDataviz", "SummarizedExperiment")
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
           library(SummarizedExperiment)
     library(scDataviz)
        library(PCAtools)
        library(cowplot)
        
        # ==========================================
        # --- Read User Inputs ---
        # ==========================================
        
        # Read metadata
        if (file.exists("metadata.rds")) {
          metadata <- readRDS("metadata.rds")
        } else if (file.exists("metadata.csv")) {
          metadata <- read.csv("metadata.csv", row.names = 1, stringsAsFactors = FALSE)
        } else {
          stop("Metadata file (metadata.rds or metadata.csv) not found in the working directory!")
        }
        
        # Read filelist
        if (file.exists("filelist.rds")) {
          filelist <- readRDS("filelist.rds")
        } else if (file.exists("filelist.txt")) {
          filelist <- readLines("filelist.txt")
        } else {
          # Fallback: list FCS files in the working directory
          filelist <- list.files(path = ".", pattern = "\\\\.[fF][cC][sS]\$", full.names = TRUE)
          if (length(filelist) == 0) {
            stop("Filelist file (filelist.rds or filelist.txt) not found, and no FCS files found in the working directory!")
          }
        }
        
        # Ensure metadata row names match filelist
        if (all(basename(filelist) %in% rownames(metadata))) {
          metadata <- metadata[basename(filelist), , drop = FALSE]
          rownames(metadata) <- filelist
        } else if (all(filelist %in% rownames(metadata))) {
          metadata <- metadata[filelist, , drop = FALSE]
          rownames(metadata) <- filelist
        } else if (nrow(metadata) == length(filelist)) {
          rownames(metadata) <- filelist
        } else {
          stop("Error: The number of rows in metadata does not match the number of FCS files, and row names do not match the FCS file names.")
        }
        
        # Ensure required columns exist in metadata for downstream plotting
        if (!"group" %in% colnames(metadata)) {
          metadata\$group <- "Healthy"
        }
        if (!"treatment" %in% colnames(metadata)) {
          metadata\$treatment <- "Unstim"
        }
        
        # Ensure group is a factor
        metadata\$group <- factor(metadata\$group)
        
        # ==========================================
        # --- Preprocess and Transform FCS Files ---
        # ==========================================
        
        inclusions <- c('Yb171Di','Nd144Di','Nd145Di',
          'Er168Di','Tm169Di','Sm154Di','Yb173Di','Yb174Di',
          'Lu175Di','Nd143Di')
        
        markernames <- c('Foxp3','C3aR','CD4',
          'CD46','CD25','CD3','Granzyme B','CD55',
          'CD279','CD45RA')
        
        names(markernames) <- inclusions
        
        exclusions <- c('Time','Event_length','BCKG190Di',
          'Center','Offset','Width','Residual')
        
        # Dynamically adapt inclusions/exclusions if the user's FCS files have different channels
        if (requireNamespace("flowCore", quietly = TRUE) && length(filelist) > 0) {
          fcs_cols <- colnames(flowCore::read.FCS(filelist[1], which.lines = 1, transformation = FALSE, emptyValue = FALSE))
          if (!all(inclusions %in% fcs_cols)) {
            available_cols <- setdiff(fcs_cols, exclusions)
            inclusions <- head(available_cols, 10)
            markernames <- paste0("Marker_", inclusions)
            names(markernames) <- inclusions
          }
        }
        
        sce <- processFCS(
          files = filelist,
          metadata = metadata,
          transformation = TRUE,
          transFun = function (x) asinh(x),
          asinhFactor = 5,
          downsample = 10000,
          downsampleVar = 0.7,
          colsRetain = inclusions,
          colsDiscard = exclusions,
          newColnames = markernames)
        
        # ==========================================
        # --- Perform PCA ---
        # ==========================================
        
        p <- pca(assay(sce, 'scaled'), metadata = metadata(sce))
        
        pdf("pca_biplot.pdf", width = 8, height = 7)
        biplot(p,
          x = 'PC1', y = 'PC2',
          lab = NULL,
          xlim = c(min(p\$rotated[,'PC1'])-1, max(p\$rotated[,'PC1'])+1),
          ylim = c(min(p\$rotated[,'PC2'])-1, max(p\$rotated[,'PC2'])+1),
          pointSize = 1.0,
          colby = 'treatment',
          legendPosition = 'right',
          title = 'PCA applied to CyTOF data',
          caption = paste0('10000 cells randomly selected after ',
            'having filtered for low variance'))
        dev.off()
        
        reducedDim(sce, 'PCA') <- p\$rotated
        
        # ==========================================
        # --- Perform UMAP ---
        # ==========================================
        
        sce <- performUMAP(sce)
        
        elbow <- findElbowPoint(p\$variance)
        horn <- parallelPCA(assay(sce, 'scaled'))
        
        sce <- performUMAP(sce, reducedDim = 'PCA', dims = c(1:5))
        
        # ==========================================
        # --- Create Contour Plots ---
        # ==========================================
        
        ggout1 <- contourPlot(sce,
          reducedDim = 'UMAP',
          bins = 150,
          subtitle = 'UMAP performed on expression values',
          legendLabSize = 18,
          axisLabSize = 22,
          titleLabSize = 22,
          subtitleLabSize = 18,
          captionLabSize = 18)
        
        ggout2 <- contourPlot(sce,
          reducedDim = 'UMAP_PCA',
          bins = 150,
          subtitle = 'UMAP performed on PC eigenvectors',
          legendLabSize = 18,
          axisLabSize = 22,
          titleLabSize = 22,
          subtitleLabSize = 18,
          captionLabSize = 18)
        
        pdf("umap_contour_plots.pdf", width = 16, height = 7.5)
        cowplot::plot_grid(ggout1, ggout2,
          labels = c('A','B'),
          ncol = 2, align = "l", label_size = 24)
        dev.off()
        
        # ==========================================
        # --- Show Marker Expression Across Layout ---
        # ==========================================
        
        if (length(rownames(sce)) < 6) {
          markers <- rownames(sce)
        } else {
          markers <- sample(rownames(sce), 6)
        }
        
        ggout1 <- markerExpression(sce,
          markers = markers,
          subtitle = 'UMAP performed on expression values',
          nrow = 1, ncol = length(markers),
          legendKeyHeight = 1.0,
          legendLabSize = 18,
          stripLabSize = 22,
          axisLabSize = 22,
          titleLabSize = 22,
          subtitleLabSize = 18,
          captionLabSize = 18)
        
        ggout2 <- markerExpression(sce,
          markers = markers,
          reducedDim = 'UMAP_PCA',
          subtitle = 'UMAP performed on PC eigenvectors',
          nrow = 1, ncol = length(markers),
          col = c('white', 'darkblue'),
          legendKeyHeight = 1.0,
          legendLabSize = 18,
          stripLabSize = 22,
          axisLabSize = 22,
          titleLabSize = 22,
          subtitleLabSize = 18,
          captionLabSize = 18)
        
        pdf("marker_expression_plots.pdf", width = 20, height = 12)
        cowplot::plot_grid(ggout1, ggout2,
          labels = c('A','B'),
          nrow = 2, align = "l", label_size = 24)
        dev.off()
        
        # ==========================================
        # --- Shade Cells by Metadata ---
        # ==========================================
        
        ggout1 <- metadataPlot(sce,
          colby = 'group',
          title = 'Disease status',
          subtitle = 'UMAP performed on expression values',
          legendLabSize = 16,
          axisLabSize = 20,
          titleLabSize = 20,
          subtitleLabSize = 16,
          captionLabSize = 16)
        
        ggout2 <- metadataPlot(sce,
          reducedDim = 'UMAP_PCA',
          colby = 'group',
          title = 'Disease status',
          subtitle = 'UMAP performed on PC eigenvectors',
          legendLabSize = 16,
          axisLabSize = 20,
          titleLabSize = 20,
          subtitleLabSize = 16,
          captionLabSize = 16)
        
        ggout3 <- metadataPlot(sce,
          colby = 'treatment',
          title = 'Treatment type',
          subtitle = 'UMAP performed on expression values',
          legendLabSize = 16,
          axisLabSize = 20,
          titleLabSize = 20,
          subtitleLabSize = 16,
          captionLabSize = 16)
        
        ggout4 <- metadataPlot(sce,
          reducedDim = 'UMAP_PCA',
          colby = 'treatment',
          title = 'Treatment type',
          subtitle = 'UMAP performed on PC eigenvectors',
          legendLabSize = 16,
          axisLabSize = 20,
          titleLabSize = 20,
          subtitleLabSize = 16,
          captionLabSize = 16)
        
        pdf("metadata_plots.pdf", width = 14, height = 12)
        cowplot::plot_grid(ggout1, ggout3, ggout2, ggout4,
          labels = c('A','B','C','D'),
          nrow = 2, ncol = 2, align = "l", label_size = 24)
        dev.off()
        
        # ==========================================
        # --- Find Clusters via k-Nearest Neighbours ---
        # ==========================================
        
        sce <- clusKNN(sce,
          k.param = 20,
          prune.SNN = 1/15,
          resolution = 0.01,
          algorithm = 2,
          verbose = FALSE)
        
        sce <- clusKNN(sce,
          reducedDim = 'UMAP_PCA',
          clusterAssignName = 'Cluster_PCA',
          k.param = 20,
          prune.SNN = 1/15,
          resolution = 0.01,
          algorithm = 2,
          verbose = FALSE)
        
        ggout1 <- plotClusters(sce,
          clusterColname = 'Cluster',
          labSize = 7.0,
          subtitle = 'UMAP performed on expression values',
          caption = paste0('Note: clusters / communities identified via',
            '\nLouvain algorithm with multilevel refinement'),
          axisLabSize = 20,
          titleLabSize = 20,
          subtitleLabSize = 16,
          captionLabSize = 16)
        
        ggout2 <- plotClusters(sce,
          clusterColname = 'Cluster_PCA',
          reducedDim = 'UMAP_PCA',
          labSize = 7.0,
          subtitle = 'UMAP performed on PC eigenvectors',
          caption = paste0('Note: clusters / communities identified via',
            '\nLouvain algorithm with multilevel refinement'),
          axisLabSize = 20,
          titleLabSize = 20,
          subtitleLabSize = 16,
          captionLabSize = 16)
        
        pdf("cluster_plots.pdf", width = 14, height = 8)
        cowplot::plot_grid(ggout1, ggout2,
          labels = c('A','B'),
          ncol = 2, align = "l", label_size = 24)
        dev.off()
        
        # ==========================================
        # --- Plot Marker Expression Per Cluster ---
        # ==========================================
        
        clusters <- unique(metadata(sce)[['Cluster_PCA']])
        
        if (length(rownames(sce)) < 5) {
          markers <- rownames(sce)
        } else {
          markers <- sample(rownames(sce), 5)
        }
        
        pdf("marker_expression_per_cluster.pdf", width = 12, height = 7)
        markerExpressionPerCluster(sce,
          clusters = clusters,
          clusterAssign = metadata(sce)[['Cluster_PCA']],
          markers = markers,
          nrow = 2, ncol = length(markers),
          caption = 'Cluster assignments based on UMAP performed on PC eigenvectors',
          stripLabSize = 22,
          axisLabSize = 22,
          titleLabSize = 22,
          subtitleLabSize = 18,
          captionLabSize = 18)
        dev.off()
        
        # ==========================================
        # --- Determine Enriched Markers & Signatures ---
        # ==========================================
        
        enrich_group <- markerEnrichment(sce,
          method = 'quantile',
          studyvarID = 'group')
        
        enrich_treatment <- markerEnrichment(sce,
          sampleAbundances = FALSE,
          method = 'quantile',
          studyvarID = 'treatment')
        
        # Save enrichment tables
        write.csv(enrich_group, "marker_enrichment_group.csv", row.names = FALSE)
        write.csv(enrich_treatment, "marker_enrichment_treatment.csv", row.names = FALSE)
        
        # Plot signatures
        pdf("signatures_plot.pdf", width = 6, height = 8)
        plotSignatures(sce,
          labCex = 1.2,
          legendCex = 1.2,
          labDegree = 40)
        dev.off()
        
        # Save final processed SingleCellExperiment object
        saveRDS(sce, "processed_sce.rds")

    writeLines(c(
        '"BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW":',
        paste0('    scDataviz: ', as.character(packageVersion('scDataviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytof_fcs_workflow.csv versions.yml
    """
}

workflow BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ filelist, metadata ] ]

    main:
    BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW.out.tables
    plots    = BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW.out.plots
    objects  = BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW.out.objects
    versions = BIOC_SCDATAVIZ_CYTOF_FCS_WORKFLOW.out.versions
}
