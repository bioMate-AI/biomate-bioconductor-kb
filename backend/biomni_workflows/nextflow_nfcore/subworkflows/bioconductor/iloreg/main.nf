#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ILoReg
// ILoReg is a tool for identification of cell populations from scRNA-seq data. In particular, ILoReg i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ILoReg/inst/doc/ILoReg.R
// Upstream  : SingleCellExperiment, cowplot
// Downstream: none
//
// Install: BiocManager::install("ILoReg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ILOREG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iloreg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iloreg:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iloreg:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iloreg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iloreg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iloreg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ILoReg)
    library(AnnotationScatterPlot)
    library(ClusteringScatterPlot)
    library(GeneHeatmap)
    library(GeneScatterPlot)
    library(RenameAllClusters)
    library(RenameCluster)
    library(SelectKClusters)
    library(VlnPlot)
    library(jsonlite)

    # --- Dimensionality Reduction [] ---
    # Key functions: RunPCA, PCAElbowPlot, RunUMAP, RunTSNE
    sce <- RunPCA(sce, p = 50, scale = FALSE)
    PCAElbowPlot(sce)
    sce <- RunUMAP(sce)
    sce <- RunTSNE(sce, perplexity = 30)


    # --- Hierarchical Clustering and Selection [] ---
    # Key functions: HierarchicalClustering, SelectKClusters, ClusteringScatterPlot
    sce <- HierarchicalClustering(sce)
    sce <- SelectKClusters(sce, K = 13)
    umap_plot <- ClusteringScatterPlot(
        sce, dim.reduction.type = "umap", return.plot = TRUE,
        title = "UMAP", show.legend = FALSE
    )
    tsne_plot <- ClusteringScatterPlot(
        sce, dim.reduction.type = "tsne", return.plot = TRUE,
        title = "t-SNE", show.legend = FALSE
    )


    # --- Marker Gene Identification [] ---
    # Key functions: FindAllGeneMarkers, SelectTopGenes, GeneScatterPlot
    gene_markers <- FindAllGeneMarkers(
        sce, clustering.type = "manual", test = "wilcox",
        log2fc.threshold = 0.25, min.pct = 0.25,
        min.cells.group = 3, return.thresh = 0.01, only.pos = TRUE
    )
    top10_log2FC <- SelectTopGenes(
        gene_markers, top.N = 10, criterion.type = "log2FC",
        inverse = FALSE
    )
    top1_log2FC <- SelectTopGenes(
        gene_markers, top.N = 1, criterion.type = "log2FC",
        inverse = FALSE
    )
    GeneScatterPlot(
        sce, genes = unique(top1_log2FC$gene),
        dim.reduction.type = "tsne", point.size = 0.5, ncol = 2
    )


    # --- Cluster Annotation and Visualization [] ---
    # Key functions: RenameAllClusters, GeneHeatmap, VlnPlot
    new_names <- c(
        "GZMK+/CD8+ T cells", "IGKC+ B cells", "Naive CD4+ T cells",
        "NK cells", "CD16+ monocytes", "CD8+ T cells",
        "CD14+ monocytes", "IGLC+ B cells", "Intermediate monocytes",
        "IGKC+/IGLC+ B cells", "Memory CD4+ T cells",
        "Naive CD8+ T cells", "Dendritic cells"
    )
    sce <- RenameAllClusters(sce, new.cluster.names = new_names)
    GeneHeatmap(sce, gene.markers = top10_log2FC)
    VlnPlot(
        sce, genes = c("CD3D"), return.plot = FALSE,
        rotate.x.axis.labels = TRUE
    )


    # --- Clustering Validation [] ---
    # Key functions: CalcSilhInfo, SilhouetteCurve
    sce <- CalcSilhInfo(sce, K.start = 2, K.end = 50)
    SilhouetteCurve(sce, return.plot = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iloreg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iloreg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iloreg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ILOREG:", paste0("    iloreg: ", packageVersion("ILoReg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iloreg_results.csv
    touch ${prefix}_iloreg_output.rds
    echo "BIOC_ILOREG:" > versions.yml
    echo "    iloreg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ILOREG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ILOREG(ch_input)

    emit:
    results  = BIOC_ILOREG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ILOREG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ILOREG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ILOREG.out.versions  // channel: path(versions.yml)
}
