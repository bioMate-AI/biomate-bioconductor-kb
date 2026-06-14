#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mumosa — multimodal_integration_and_clustering
// Integrate multiple single-cell modalities (e.g., RNA and ADT) for downstream clustering and dimensionality reduction using neighbor-based rescaling, cluster int
// Input: sce2
// Container: quay.io/biocontainers/bioconductor-mumosa:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, bluster, igraph, mumosa, scater, scran
// Visualizations: ordination plot, t-SNE plot, UMAP plot
// QC: cell QC metrics, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Rescale modality matrices by neighbor distance using rescaleByNeighbors()
//  * 2. [Core Analysis] Perform clustering on the combined rescaled matrix
//  * 3. [Core Analysis] Intersect independent clusterings using intersectClusters()
//  * 4. [Core Analysis] Compute multi-metric UMAP using calculateMultiUMAP() or runMultiUMAP()
//  * 5. [Core Analysis] Intersect nearest-neighbor graphs using intersectGraphs()

nextflow.enable.dsl = 2

process BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING {
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
    .bm_deps <- c("scater", "scran", "mumosa", "bluster", "igraph")
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
    library(scater)
    library(scran)
    library(mumosa)
    library(bluster)
    library(igraph)
    
    # 1. Read the input file
    sce2 <- readRDS("sce2.rds")
    
    # 2. Rescale modality matrices by neighbor distance
    output <- rescaleByNeighbors(list(reducedDim(sce2), reducedDim(altExp(sce2))))
    saveRDS(output, "rescaled_matrix.rds")
    
    # 3. Perform clustering on the combined rescaled matrix
    set.seed(100001)
    sce2\$combined.clustering <- clusterRows(output, NNGraphParam())
    reducedDim(sce2, "combined") <- output
    
    # Run and plot t-SNE
    sce2 <- runTSNE(sce2, dimred="combined")
    pdf("tsne_combined.pdf")
    print(plotTSNE(sce2, colour_by="combined.clustering"))
    dev.off()
    
    # 4. Build SNN graphs and get clusters for each modality
    g.rna <- buildSNNGraph(sce2, use.dimred="PCA")
    rna.clusters <- igraph::cluster_walktrap(g.rna)\$membership
    write.csv(as.data.frame(table(rna.clusters)), "rna_clusters_table.csv", row.names=FALSE)
    
    g.adt <- buildSNNGraph(altExp(sce2), use.dimred='PCA')
    adt.clusters <- igraph::cluster_walktrap(g.adt)\$membership
    write.csv(as.data.frame(table(adt.clusters)), "adt_clusters_table.csv", row.names=FALSE)
    
    # 5. Intersect independent clusterings
    intersected2 <- intersectClusters(list(rna.clusters, adt.clusters), list(reducedDim(sce2), reducedDim(altExp(sce2))))
    write.csv(as.data.frame(table(intersected2)), "intersected_clusters_table.csv", row.names=FALSE)
    
    # 6. Compute multi-metric UMAP
    set.seed(100002)
    umap.out <- calculateMultiUMAP(list(reducedDim(sce2), reducedDim(altExp(sce2))), n_components=20)
    saveRDS(umap.out, "umap_output.rds")
    
    sce2\$umap.clustering <- clusterRows(umap.out, NNGraphParam())
    
    set.seed(100002)
    sce2 <- runMultiUMAP(sce2, dimred="PCA", extras=list(reducedDim(altExp(sce2))))
    
    pdf("multiumap_plot.pdf")
    print(plotReducedDim(sce2, "MultiUMAP", colour_by="umap.clustering"))
    dev.off()
    
    # 7. Intersect nearest-neighbor graphs
    g.com <- intersectGraphs(g.rna, g.adt)
    com.clusters <- igraph::cluster_walktrap(g.com)\$membership
    write.csv(as.data.frame(table(com.clusters)), "combined_graphs_clusters_table.csv", row.names=FALSE)
    
    # Save the final SingleCellExperiment object
    saveRDS(sce2, "sce2_integrated.rds")

    writeLines(c(
        '"BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING":',
        paste0('    mumosa: ', as.character(packageVersion('mumosa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multimodal_integration_and_clustering.csv versions.yml
    """
}

workflow BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce2 ] ]

    main:
    BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING.out.tables
    plots    = BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING.out.plots
    objects  = BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING.out.objects
    versions = BIOC_MUMOSA_MULTIMODAL_INTEGRATION_AND_CLUSTERING.out.versions
}
