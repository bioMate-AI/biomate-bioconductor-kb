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
    library(GrunPancreasData)
    library(jsonlite)

    # --- Grunpancreasdata [] ---
    # Key functions: GrunPancreasData
    ---------------------------------------------------------------------
    library(scRNAseq)
    sce <- GrunPancreasData()
    sce
    # --- Percellqcmetrics [] ---
    # Key functions: perCellQCMetrics, quickPerCellQC
    ---------------------------------------------------------------------
    library(scuttle)
    qcstats <- perCellQCMetrics(sce)
    qcfilter <- quickPerCellQC(qcstats, percent_subsets="altexps_ERCC_percent")
    sce <- sce[,!qcfilter$discard]
    # --- Quickcluster [] ---
    # Key functions: quickCluster, computeSumFactors, sizeFactors, logNormCounts
    ---------------------------------------------------------------------
    library(scran)
    clusters <- quickCluster(sce)
    sce <- computeSumFactors(sce, clusters=clusters)
    summary(sizeFactors(sce))
    # --- Modelgenevar [] ---
    # Key functions: modelGeneVar, curve, metadata, trend
    ---------------------------------------------------------------------
    dec <- modelGeneVar(sce)
    plot(dec$mean, dec$total, xlab="Mean log-expression", ylab="Variance")
    curve(metadata(dec)$trend(x), col="blue", add=TRUE)
    # --- Modelgenevarwithspikes [] ---
    # Key functions: modelGeneVarWithSpikes, metadata, curve, trend
    ---------------------------------------------------------------------
    dec2 <- modelGeneVarWithSpikes(sce, 'ERCC')
    plot(dec2$mean, dec2$total, xlab="Mean log-expression", ylab="Variance")
    points(metadata(dec2)$mean, metadata(dec2)$var, col="red")
    curve(metadata(dec2)$trend(x), col="blue", add=TRUE)
    # --- Gettophvgs [] ---
    # Key functions: getTopHVGs
    ---------------------------------------------------------------------
    # Get the top 10% of genes.
    top.hvgs <- getTopHVGs(dec, prop=0.1)
    # Get the top 2000 genes.
    top.hvgs2 <- getTopHVGs(dec, n=2000)
    # --- Fixedpca [] ---
    # Key functions: fixedPCA, reducedDimNames
    ---------------------------------------------------------------------
    sce <- fixedPCA(sce, subset.row=top.hvgs)
    reducedDimNames(sce)
    # --- Denoisepca [] ---
    # Key functions: denoisePCA, getTopHVGs, reducedDim
    ---------------------------------------------------------------------
    sced <- denoisePCA(sce, dec2, subset.row=getTopHVGs(dec2, prop=0.1))
    ncol(reducedDim(sced, "PCA"))
    # --- Getclusteredpcs [] ---
    # Key functions: getClusteredPCs, reducedDim, metadata
    ---------------------------------------------------------------------
    output <- getClusteredPCs(reducedDim(sce))
    npcs <- metadata(output)$chosen
    reducedDim(sce, "PCAsub") <- reducedDim(sce, "PCA")[,1:npcs,drop=FALSE]
    npcs
    # --- Getclusteredpcs [] ---
    # Key functions: getClusteredPCs, buildSNNGraph, cluster_walktrap, colLabels, factor
    ---------------------------------------------------------------------
    # In this case, using the PCs that we chose from getClusteredPCs().
    g <- buildSNNGraph(sce, use.dimred="PCAsub")
    cluster <- igraph::cluster_walktrap(g)$membership
    # Assigning to the 'colLabels' of the 'sce'.
    # --- Runtsne [] ---
    # Key functions: runTSNE, plotTSNE
    ---------------------------------------------------------------------
    library(scater)
    sce <- runTSNE(sce, dimred="PCAsub")
    plotTSNE(sce, colour_by="label", text_by="label")
    # --- Pairwisemodularity [] ---
    # Key functions: pairwiseModularity, pheatmap, colors
    ---------------------------------------------------------------------
    library(bluster)
    ratio <- pairwiseModularity(g, cluster, as.ratio=TRUE)
    library(pheatmap)
    pheatmap(log10(ratio+1), cluster_cols=FALSE, cluster_rows=FALSE,
    # --- Bootstrapstability [] ---
    # Key functions: bootstrapStability, buildSNNGraph, cluster_walktrap, pheatmap, colorRampPalette
    ---------------------------------------------------------------------
    ass.prob <- bootstrapStability(sce, FUN=function(x) {
        g <- buildSNNGraph(x, use.dimred="PCAsub")
        igraph::cluster_walktrap(g)$membership
    }, clusters=sce$cluster)
    # --- Quicksubcluster [] ---
    # Key functions: quickSubCluster, colLabels, metadata
    ---------------------------------------------------------------------
    subout <- quickSubCluster(sce, groups=colLabels(sce))
    table(metadata(subout)$subcluster) # formatted as '<parent>.<subcluster>'
    # --- Collabels [] ---
    # Key functions: colLabels, scoreMarkers
    ---------------------------------------------------------------------
    # Uses clustering information from 'colLabels(sce)' by default:
    markers <- scoreMarkers(sce)
    markers
    colnames(markers[[1]])

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
