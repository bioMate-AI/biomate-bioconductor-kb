#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: schex — hexbin_plotting_workflow
// Bin single-cell reduced dimension coordinates into hexagons and visualize cell density, metadata, and gene expression.
// Input: pbmc_small, tenx_pbmc3k
// Container: quay.io/biocontainers/bioconductor-schex:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, Seurat, SingleCellExperiment, dplyr, ggplot2, ggrepel, igraph, scater, schex, scran
// Visualizations: density plot, cluster plot
// QC: cell QC metrics, count normalization, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert Seurat object to SingleCellExperiment (optional)
//  * 2. [Core Analysis] Calculate hexagon cell representation using make_hexbin
//  * 3. [Visualization & Output] Plot cell density in hexagons using plot_hexbin_density
//  * 4. [Visualization & Output] Plot metadata using plot_hexbin_meta and optionally label them using make_hexbin_label
//  * 5. [Visualization & Output] Plot gene expression using plot_hexbin_feature or plot_hexbin_feature_plus

nextflow.enable.dsl = 2

process BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    library(schex)
    library(dplyr)
    library(Seurat)
    library(ggplot2)
    library(ggrepel)
    library(scater)
    library(scran)
    library(igraph)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read pbmc_small Seurat object
    if (file.exists("pbmc_small.rds")) {
      pbmc_small <- readRDS("pbmc_small.rds")
    } else if (file.exists("pbmc_small")) {
      pbmc_small <- readRDS("pbmc_small")
    } else {
      stop("Error: 'pbmc_small' file not found in the working directory.")
    }
    
    # Read tenx_pbmc3k SingleCellExperiment object
    if (file.exists("tenx_pbmc3k.rds")) {
      tenx_pbmc3k <- readRDS("tenx_pbmc3k.rds")
    } else if (file.exists("tenx_pbmc3k")) {
      tenx_pbmc3k <- readRDS("tenx_pbmc3k")
    } else {
      stop("Error: 'tenx_pbmc3k' file not found in the working directory.")
    }
    
    # ==========================================
    # 2. Preprocess and Align Objects
    # ==========================================
    
    # Ensure pbmc_small has UMAP reduction (as required by the vignette)
    if (!"umap" %in% names(pbmc_small@reductions)) {
      set.seed(10)
      pbmc_small <- RunUMAP(pbmc_small, dims = 1:10, verbose = FALSE)
    }
    
    # Ensure tenx_pbmc3k has required metadata and assays
    if (!"cluster" %in% colnames(colData(tenx_pbmc3k))) {
      if (!"PCA" %in% reducedDimNames(tenx_pbmc3k)) {
        tenx_pbmc3k <- scater::runPCA(tenx_pbmc3k)
      }
      snn_gr <- scran::buildSNNGraph(tenx_pbmc3k, use.dimred = "PCA", k = 50)
      clusters <- igraph::cluster_louvain(snn_gr)
      tenx_pbmc3k\$cluster <- factor(clusters\$membership)
    }
    
    if (!"total" %in% colnames(colData(tenx_pbmc3k))) {
      tenx_pbmc3k\$total <- colSums(BiocGenerics::counts(tenx_pbmc3k))
    }
    
    if (!"logcounts" %in% assayNames(tenx_pbmc3k)) {
      tenx_pbmc3k <- scater::logNormCounts(tenx_pbmc3k)
    }
    
    # Ensure the specified genes exist in the objects (fallback if missing)
    pbmc_genes <- rownames(pbmc_small)
    gene_id_pbmc <- "CD1C"
    if (!gene_id_pbmc %in% pbmc_genes) {
      gene_id_pbmc <- pbmc_genes[1]
    }
    
    tenx_genes <- rownames(tenx_pbmc3k)
    gene_id_tenx <- "POMGNT1"
    if (!gene_id_tenx %in% tenx_genes) {
      gene_id_tenx <- tenx_genes[1]
    }
    
    # ==========================================
    # 3. Workflow: pbmc_small (Seurat -> SCE)
    # ==========================================
    
    pbmc.sce <- as.SingleCellExperiment(pbmc_small)
    
    pbmc.sce <- make_hexbin(pbmc.sce,
        nbins = 10,
        dimension_reduction = "UMAP"
    )
    
    # Plot and save density
    p1 <- plot_hexbin_density(pbmc.sce)
    ggsave("pbmc_density.pdf", plot = p1, width = 7, height = 7)
    
    # Plot and save metadata
    p2 <- plot_hexbin_meta(pbmc.sce, col = "nCount_RNA", action = "median")
    ggsave("pbmc_meta_nCount_RNA.pdf", plot = p2, width = 7, height = 7)
    
    # Plot and save feature expression
    p3 <- schex::plot_hexbin_feature(pbmc.sce,
        type = "counts", feature = gene_id_pbmc,
        action = "mean", xlab = "UMAP1", ylab = "UMAP2",
        title = paste0("Mean of ", gene_id_pbmc)
    )
    ggsave(paste0("pbmc_feature_", gene_id_pbmc, ".pdf"), plot = p3, width = 7, height = 7)
    
    gg <- schex::plot_hexbin_feature(pbmc.sce,
        type = "counts", feature = gene_id_pbmc,
        action = "mean", xlab = "UMAP1", ylab = "UMAP2",
        title = paste0("Mean of ", gene_id_pbmc)
    )
    p4 <- gg + theme_void()
    ggsave(paste0("pbmc_feature_", gene_id_pbmc, "_void.pdf"), plot = p4, width = 7, height = 7)
    
    # Save processed SCE object
    saveRDS(pbmc.sce, "pbmc_hexbin.rds")
    
    
    # ==========================================
    # 4. Workflow: tenx_pbmc3k (SingleCellExperiment)
    # ==========================================
    
    tenx_pbmc3k <- make_hexbin(tenx_pbmc3k,
        nbins = 40,
        dimension_reduction = "UMAP", use_dims = c(1, 2)
    )
    
    # Plot and save density
    p5 <- plot_hexbin_density(tenx_pbmc3k)
    ggsave("tenx_density.pdf", plot = p5, width = 7, height = 7)
    
    # Plot and save metadata
    p6 <- plot_hexbin_meta(tenx_pbmc3k, col = "cluster", action = "majority")
    ggsave("tenx_meta_cluster.pdf", plot = p6, width = 7, height = 7)
    
    p7 <- plot_hexbin_meta(tenx_pbmc3k, col = "total", action = "median")
    ggsave("tenx_meta_total.pdf", plot = p7, width = 7, height = 7)
    
    # Generate and save labels
    label_df <- make_hexbin_label(tenx_pbmc3k, col = "cluster")
    write.csv(label_df, "tenx_hexbin_labels.csv", row.names = FALSE)
    
    pp <- plot_hexbin_meta(tenx_pbmc3k, col = "cluster", action = "majority")
    p8 <- pp + ggrepel::geom_label_repel(
        data = label_df, aes(x = x, y = y, label = label),
        colour = "black", label.size = NA, fill = NA
    )
    ggsave("tenx_meta_cluster_labeled.pdf", plot = p8, width = 7, height = 7)
    
    # Plot and save feature expression
    p9 <- plot_hexbin_feature(tenx_pbmc3k,
        type = "logcounts", feature = gene_id_tenx,
        action = "mean", xlab = "UMAP1", ylab = "UMAP2",
        title = paste0("Mean of ", gene_id_tenx)
    )
    ggsave(paste0("tenx_feature_", gene_id_tenx, ".pdf"), plot = p9, width = 7, height = 7)
    
    p10 <- plot_hexbin_feature_plus(tenx_pbmc3k,
        col = "cluster", type = "logcounts",
        feature = gene_id_tenx, action = "mean"
    )
    ggsave(paste0("tenx_feature_plus_", gene_id_tenx, ".pdf"), plot = p10, width = 7, height = 7)
    
    # Save processed SCE object
    saveRDS(tenx_pbmc3k, "tenx_hexbin.rds")

    writeLines(c(
        '"BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW":',
        paste0('    schex: ', as.character(packageVersion('schex')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hexbin_plotting_workflow.csv versions.yml
    """
}

workflow BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_small, tenx_pbmc3k ] ]

    main:
    BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.tables
    plots    = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.plots
    objects  = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.objects
    versions = BIOC_SCHEX_HEXBIN_PLOTTING_WORKFLOW.out.versions
}
