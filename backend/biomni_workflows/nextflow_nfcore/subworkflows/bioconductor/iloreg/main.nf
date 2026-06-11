#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ILoReg — scrna_seq_cell_population_identification
// Identify high-resolution cell populations and marker genes from normalized scRNA-seq data using iterative clustering projection (ICP).
// Input: normalized_counts.rds
// Container: quay.io/biocontainers/bioconductor-iloreg:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ILoReg, SingleCellExperiment, cowplot, ggplot2, plyr
// Visualizations: violin plot, PCA plot, elbow plot, scatter plot, cluster plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the SingleCellExperiment object for ILoReg analysis
//  * 2. [Core Analysis] Run the ICP clustering algorithm L times in parallel
//  * 3. [Visualization & Output] Perform PCA transformation on the joint probability matrix and optionally plot elbow
//  * 4. [Core Analysis] Perform nonlinear dimensionality reduction (UMAP and t-SNE)
//  * 5. [Visualization & Output] Visualize gene expression on dimensionality reduction plots
//  * 6. [Core Analysis] Perform hierarchical clustering using Ward's method
//  * 7. [Visualization & Output] Extract consensus clustering with K clusters and plot
//  * 8. [Core Analysis] Identify gene markers for all clusters
//  * 9. [Core Analysis] Select top gene markers
//  * 10. [Visualization & Output] Visualize markers via heatmap or violin plots
//  * 11. [Core Analysis] Optionally rename clusters, merge clusters, or estimate optimal K

nextflow.enable.dsl = 2

process BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION {
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
    .bm_deps <- c("ILoReg", "SingleCellExperiment", "cowplot", "ggplot2")
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
        suppressMessages(library(ILoReg))
        suppressMessages(library(SingleCellExperiment))
        suppressMessages(library(cowplot))
        suppressMessages(library(ggplot2))
        
        # 1. Read user input and prepare the SingleCellExperiment object
        if (!file.exists("normalized_counts.rds")) {
          stop("Error: 'normalized_counts.rds' not found in the working directory.")
        }
        
        normalized_counts <- readRDS("normalized_counts.rds")
        sce <- SingleCellExperiment(assays = list(logcounts = normalized_counts))
        sce <- PrepareILoReg(sce)
        
        # 2. Run the ICP clustering algorithm L times in parallel
        set.seed(1)
        sce <- RunParallelICP(object = sce, k = 15,
                              d = 0.3, L = 30, 
                              r = 5, C = 0.3, 
                              reg.type = "L1", threads = 0)
        
        # 3. Perform PCA transformation on the joint probability matrix and plot elbow
        sce <- RunPCA(sce, p = 50, scale = FALSE)
        
        pdf("pca_elbow_plot.pdf")
        tryCatch({
          PCAElbowPlot(sce)
        }, error = function(e) {
          warning("PCAElbowPlot failed: ", e\$message)
        })
        dev.off()
        
        # 4. Perform nonlinear dimensionality reduction (UMAP and t-SNE)
        sce <- RunUMAP(sce)
        sce <- RunTSNE(sce, perplexity = 30)
        
        # 5. Visualize gene expression on dimensionality reduction plots
        pdf("gene_scatter_plots.pdf", width = 10, height = 8)
        tryCatch({
          top_genes <- rownames(sce)[1:min(4, nrow(sce))]
          GeneScatterPlot(sce, top_genes,
                          dim.reduction.type = "umap",
                          point.size = 0.3)
        }, error = function(e) {
          warning("GeneScatterPlot (umap) failed: ", e\$message)
        })
        
        tryCatch({
          top_genes <- rownames(sce)[1:min(4, nrow(sce))]
          GeneScatterPlot(sce, top_genes,
                          dim.reduction.type = "tsne",
                          point.size = 0.3)
        }, error = function(e) {
          warning("GeneScatterPlot (tsne) failed: ", e\$message)
        })
        dev.off()
        
        # 6. Perform hierarchical clustering using Ward's method
        sce <- HierarchicalClustering(sce)
        
        # 7. Extract consensus clustering with K clusters and plot
        sce <- SelectKClusters(sce, K = 5)
        
        pdf("clustering_scatter_plots.pdf", width = 8, height = 10)
        tryCatch({
          p_grid <- plot_grid(ClusteringScatterPlot(sce,
                                          dim.reduction.type = "umap",
                                          return.plot = TRUE,
                                          title = "UMAP",
                                          show.legend = FALSE),
                    ClusteringScatterPlot(sce,
                                          dim.reduction.type = "tsne",
                                          return.plot = TRUE,
                                          title = "t-SNE",
                                          show.legend = FALSE),
                    ncol = 1
          )
          print(p_grid)
        }, error = function(e) {
          warning("ClusteringScatterPlot grid failed: ", e\$message)
        })
        dev.off()
        
        # 8. Identify gene markers for all clusters
        gene_markers <- FindAllGeneMarkers(sce,
                                           clustering.type = "manual",
                                           test = "wilcox",
                                           log2fc.threshold = 0.25,
                                           min.pct = 0.25,
                                           min.diff.pct = NULL,
                                           min.cells.group = 3,
                                           return.thresh = 0.01,
                                           only.pos = TRUE,
                                           max.cells.per.cluster = NULL)
        write.csv(gene_markers, "all_gene_markers.csv", row.names = FALSE)
        
        # 9. Select top gene markers
        top10_log2FC <- SelectTopGenes(gene_markers,
                                       top.N = 10,
                                       criterion.type = "log2FC",
                                       inverse = FALSE)
        top1_log2FC <- SelectTopGenes(gene_markers,
                                      top.N = 1,
                                      criterion.type = "log2FC",
                                      inverse = FALSE)
        top10_adj.p.value <- SelectTopGenes(gene_markers,
                                            top.N = 10,
                                            criterion.type = "adj.p.value",
                                            inverse = TRUE)
        top1_adj.p.value <- SelectTopGenes(gene_markers,
                                           top.N = 1,
                                           criterion.type = "adj.p.value",
                                           inverse = TRUE)
        
        write.csv(top10_log2FC, "top10_log2FC_markers.csv", row.names = FALSE)
        
        pdf("top1_log2FC_scatter_plot.pdf", width = 10, height = 10)
        tryCatch({
          GeneScatterPlot(sce,
                          genes = unique(top1_log2FC\$gene),
                          dim.reduction.type = "tsne",
                          point.size = 0.5, ncol = 2)
        }, error = function(e) {
          warning("GeneScatterPlot for top1_log2FC failed: ", e\$message)
        })
        dev.off()
        
        # 10. Visualize markers via heatmap or violin plots (with cluster renaming)
        tryCatch({
          sce <- RenameAllClusters(sce,
                                   new.cluster.names = paste0("Cluster_", 1:5))
        }, error = function(e) {
          warning("RenameAllClusters to 5 cell types failed: ", e\$message)
        })
        
        pdf("gene_heatmap.pdf", width = 12, height = 12)
        tryCatch({
          GeneHeatmap(sce, gene.markers = top10_log2FC)
        }, error = function(e) {
          warning("GeneHeatmap failed: ", e\$message)
        })
        dev.off()
        
        pdf("violin_plot.pdf")
        tryCatch({
          VlnPlot(sce, genes = rownames(sce)[1], return.plot = FALSE, rotate.x.axis.labels = TRUE)
        }, error = function(e) {
          warning("VlnPlot failed: ", e\$message)
        })
        dev.off()
        
        # 11. Estimate optimal K, rename clusters, merge clusters, and find specific DE markers
        tryCatch({
          sce <- CalcSilhInfo(sce, K.start = 2, K.end = 50)
          pdf("silhouette_curve.pdf")
          SilhouetteCurve(sce, return.plot = FALSE)
          dev.off()
        }, error = function(e) {
          warning("CalcSilhInfo or SilhouetteCurve failed: ", e\$message)
        })
        
        tryCatch({
          sce <- SelectKClusters(sce, K = 20)
          sce <- RenameCluster(sce, old.cluster.name = 1, new.cluster.name = "A")
        }, error = function(e) {
          warning("SelectKClusters K=20 or RenameCluster failed: ", e\$message)
        })
        
        tryCatch({
          sce <- SelectKClusters(sce, K = 5)
          custom_annotation <- plyr::mapvalues(metadata(sce)\$iloreg\$clustering.manual, c(1, 2, 3, 4, 5), LETTERS[1:5])
          pdf("annotation_scatter_plot.pdf")
          AnnotationScatterPlot(sce,
                                annotation = custom_annotation,
                                return.plot = FALSE,
                                dim.reduction.type = "tsne",
                                show.legend = FALSE)
          dev.off()
        }, error = function(e) {
          warning("Custom annotation plotting failed: ", e\$message)
        })
        
        tryCatch({
          sce <- SelectKClusters(sce, K = 20)
          sce <- MergeClusters(sce, clusters.to.merge = c(3, 4))
        }, error = function(e) {
          warning("MergeClusters failed: ", e\$message)
        })
        
        tryCatch({
          sce <- SelectKClusters(sce, K = 5)
          sce <- RenameAllClusters(sce,
                                   new.cluster.names = paste0("Cluster_", 1:5))
          
          GM_naive_memory_CD4 <- FindGeneMarkers(sce,
                                                 clusters.1 = "Cluster_1",
                                                 clusters.2 = "Cluster_2",
                                                 logfc.threshold = 0.25,
                                                 min.pct = 0.25,
                                                 return.thresh = 0.01,
                                                 only.pos = TRUE)
          write.csv(GM_naive_memory_CD4, "GM_naive_memory_CD4.csv", row.names = FALSE)
          
          GM_dendritic <- FindGeneMarkers(sce,
                                          clusters.1 = "Cluster_3",
                                          logfc.threshold = 0.25,
                                          min.pct = 0.25,
                                          return.thresh = 0.01,
                                          only.pos = TRUE)
          write.csv(GM_dendritic, "GM_dendritic.csv", row.names = FALSE)
        }, error = function(e) {
          warning("Specific cluster marker identification failed: ", e\$message)
        })
        
        # Save final processed SingleCellExperiment object
        saveRDS(sce, "iloreg_processed_sce.rds")
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION":',
        paste0('    ILoReg: ', as.character(packageVersion('ILoReg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_seq_cell_population_identification.csv versions.yml
    """
}

workflow BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normalized_counts.rds ] ]

    main:
    BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION(ch_input)

    emit:
    tables   = BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION.out.tables
    plots    = BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION.out.plots
    objects  = BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION.out.objects
    versions = BIOC_ILOREG_SCRNA_SEQ_CELL_POPULATION_IDENTIFICATION.out.versions
}
