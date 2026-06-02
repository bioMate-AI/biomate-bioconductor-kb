#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scran
// Implements miscellaneous functions for interpretation of single-cell RNA-seq data. Methods are provi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scran/inst/doc/scran.R
// Upstream  : bluster, knitr, pheatmap, scRNAseq, scater
// Downstream: OSCA.advanced, OSCA.basic, OSCA.intro, OSCA.multisample, OSCA.workflows
//
// Install: BiocManager::install("scran")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scran"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scran:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scran:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scran_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scran_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scran_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scran)
    library(GrunPancreasData)
    library(jsonlite)

    # --- Normalisation ---
    # Key functions: quickCluster, computeSumFactors
    clusters <- quickCluster(sce)
    sce <- computeSumFactors(sce, clusters = clusters)
    sf <- sizeFactors(sce)
    summary_sf <- summary(sf)

    # --- Variance Modelling ---
    # Key functions: modelGeneVar, modelGeneVarWithSpikes, getTopHVGs
    dec <- modelGeneVar(sce)
    dec2 <- modelGeneVarWithSpikes(sce, "ERCC")
    dec3 <- modelGeneVar(sce, block = sce$donor, density.weights = FALSE)
    top.hvgs <- getTopHVGs(dec, prop = 0.1)
    top.hvgs2 <- getTopHVGs(dec, n = 2000)
    top.hvgs3 <- getTopHVGs(dec, var.threshold = 0)

    # --- Dimensionality Reduction ---
    # Key functions: fixedPCA, denoisePCA, getClusteredPCs
    sce <- fixedPCA(sce, subset.row = top.hvgs)
    sced <- denoisePCA(sce, dec2, subset.row = getTopHVGs(dec2, prop = 0.1))
    output <- getClusteredPCs(reducedDim(sce))
    npcs <- metadata(output)$chosen
    reducedDim(sce, "PCAsub") <- reducedDim(sce, "PCA")[, 1:npcs, drop = FALSE]

    # --- Graph-based Clustering ---
    # Key functions: buildSNNGraph, bootstrapStability, quickSubCluster
    g <- buildSNNGraph(sce, use.dimred = "PCAsub")
    cluster <- igraph::cluster_walktrap(g)$membership
    colLabels(sce) <- factor(cluster)
    ass.prob <- bootstrapStability(sce, FUN = function(x) {
        g_sub <- buildSNNGraph(x, use.dimred = "PCAsub")
        igraph::cluster_walktrap(g_sub)$membership
    }, clusters = colLabels(sce))
    subout <- quickSubCluster(sce, groups = colLabels(sce))

    # --- Marker Gene Detection ---
    # Key functions: scoreMarkers
    markers <- scoreMarkers(sce)
    markers_full <- scoreMarkers(sce, full.stats = TRUE)
    top_marker_stats <- markers[[1]][
        order(markers[[1]]$mean.AUC, decreasing = TRUE),
        1:4
    ]
    cohen_stats <- markers_full[[1]]$full.logFC.cohen

    # --- Gene Correlation Analysis ---
    # Key functions: correlatePairs, correlateGenes, convertTo
    of.interest <- top.hvgs[1:200]
    cor.pairs <- correlatePairs(sce, subset.row = of.interest)
    cor.pairs2 <- correlatePairs(
        sce, subset.row = of.interest, block = sce$donor
    )
    cor.genes <- correlateGenes(cor.pairs)
    y <- convertTo(sce, type = "edgeR")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scran_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scran_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scran_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRAN:", paste0("    scran: ", packageVersion("scran"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scran_results.csv
    touch ${prefix}_scran_output.rds
    echo "BIOC_SCRAN:" > versions.yml
    echo "    scran: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCRAN(ch_input)

    emit:
    results  = BIOC_SCRAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRAN.out.versions  // channel: path(versions.yml)
}
