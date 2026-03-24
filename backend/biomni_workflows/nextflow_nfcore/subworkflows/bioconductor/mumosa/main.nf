#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mumosa
// Assorted utilities for multi-modal analyses of single-cell datasets. Includes functions to combine m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mumosa/inst/doc/overview.R
// Upstream  : BiocStyle, DropletUtils, bluster, knitr, scRNAseq
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("mumosa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUMOSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mumosa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mumosa:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mumosa:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_mumosa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mumosa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mumosa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KotliarovPBMCData)
    library(NNGraphParam)
    library(jsonlite)

    # --- Kotliarovpbmcdata [] ---
    # Key functions: KotliarovPBMCData
    ---------------------------------------------------------------------
    library(scater)
    library(scran)
    library(scRNAseq)
    sce <- KotliarovPBMCData()
    # --- Percellqcmetrics [] ---
    # Key functions: perCellQCMetrics, quickPerCellQC, logNormCounts, modelGeneVar
    ---------------------------------------------------------------------
    stats <- perCellQCMetrics(sce, subsets=list(Mito=grep("^MT-", rownames(sce))))
    filter <- quickPerCellQC(stats, sub.fields="subsets_Mito_percent")
    sce <- sce[,!filter$discard]
    sce <- logNormCounts(sce)
    # --- Altexp [] ---
    # Key functions: altExp
    ---------------------------------------------------------------------
    sce2 <- sce[,keep]
    altExp(sce2) <- sceA
    # --- Rescalebyneighbors [] ---
    # Key functions: rescaleByNeighbors, reducedDim, altExp
    ---------------------------------------------------------------------
    library(mumosa)
    output <- rescaleByNeighbors(list(reducedDim(sce2), reducedDim(altExp(sce2))))
    dim(output)
    # --- Buildsnngraph [] ---
    # Key functions: buildSNNGraph, cluster_walktrap, altExp
    ---------------------------------------------------------------------
    g.rna <- buildSNNGraph(sce2, use.dimred="PCA")
    rna.clusters <- igraph::cluster_walktrap(g.rna)$membership
    table(rna.clusters)
    g.adt <- buildSNNGraph(altExp(sce2), use.dimred='PCA')
    # --- Intersectclusters [] ---
    # Key functions: intersectClusters, reducedDim, altExp
    ---------------------------------------------------------------------
    intersected2 <- intersectClusters(list(rna.clusters, adt.clusters),
        list(reducedDim(sce2), reducedDim(altExp(sce2))))
    table(intersected2)
    # --- Clusterrows [] ---
    # Key functions: clusterRows, NNGraphParam
    ---------------------------------------------------------------------
    library(bluster)
    sce2$umap.clustering <- clusterRows(umap.out, NNGraphParam())
    # --- Intersectgraphs [] ---
    # Key functions: intersectGraphs
    ---------------------------------------------------------------------
    g.com <- intersectGraphs(g.rna, g.adt)
    # --- Cluster Walktrap [] ---
    # Key functions: cluster_walktrap
    ---------------------------------------------------------------------
    com.clusters <- igraph::cluster_walktrap(g.com)$membership
    table(com.clusters)
    # --- Computecorrelations [] ---
    # Key functions: computeCorrelations, altExp
    ---------------------------------------------------------------------
    cor.all <- computeCorrelations(sce2, altExp(sce2)[1:5,])
    cor.all[order(cor.all$p.value),]
    # --- Rep [] ---
    # Key functions: computeCorrelations, altExp
    ---------------------------------------------------------------------
    b <- rep(1:3, length.out=ncol(sce2))
    cor.all.batch <- computeCorrelations(sce2, altExp(sce2)[1:5,], block=b)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mumosa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mumosa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mumosa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUMOSA:", paste0("    mumosa: ", packageVersion("mumosa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mumosa_results.csv
    touch ${prefix}_mumosa_output.rds
    echo "BIOC_MUMOSA:" > versions.yml
    echo "    mumosa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUMOSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_MUMOSA(ch_input)

    emit:
    results  = BIOC_MUMOSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUMOSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUMOSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUMOSA.out.versions  // channel: path(versions.yml)
}
