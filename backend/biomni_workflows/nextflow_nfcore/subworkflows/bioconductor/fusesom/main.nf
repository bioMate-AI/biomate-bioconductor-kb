#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FuseSOM
// A correlation-based multiview self-organizing map for the characterization of cell types in highly m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FuseSOM/inst/doc/Introduction.R
// Upstream  : SingleCellExperiment, knitr
// Downstream: none
//
// Install: BiocManager::install("FuseSOM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FUSESOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fusesom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fusesom:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fusesom:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fusesom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fusesom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fusesom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FuseSOM)
    library(jsonlite)

    # --- Cluster Visualization [] ---
    # Key functions: markerHeatmap
    risomHeat <- markerHeatmap(
        data = risom_dat,
        markers = risomMarkers,
        clusters = risomRes$clusters,
        clusterMarkers = TRUE
    )


    # --- Cluster Number Estimation [] ---
    # Key functions: estimateNumCluster
    risomKest <- estimateNumCluster(
        data = risomRes$model,
        kSeq = 2:25,
        method = c("Discriminant", "Distance")
    )
    best_discriminant <- risomKest$Discriminant


    # --- Optimization Plotting [] ---
    # Key functions: optiPlot
    pSlope <- optiPlot(risomKest, method = 'slope')
    pJump <- optiPlot(risomKest, method = 'jump')
    pWcd <- optiPlot(risomKest, method = 'wcd')
    pGap <- optiPlot(risomKest, method = 'gap')
    pSil <- optiPlot(risomKest, method = 'silhouette')


    # --- SingleCellExperiment Integration [] ---
    # Key functions: runFuseSOM, estimateNumCluster, optiPlot
    colDat <- risom_dat[, setdiff(colnames(risom_dat), risomMarkers)]
    sce <- SingleCellExperiment::SingleCellExperiment(
        assays = list(counts = t(risom_dat)),
        colData = colDat
    )
    risomRessce <- runFuseSOM(
        sce,
        markers = risomMarkers,
        assay = 'counts',
        numClusters = 23,
        verbose = FALSE
    )
    risomRessce <- estimateNumCluster(
        data = risomRessce,
        kSeq = 2:25,
        method = c("Discriminant", "Distance")
    )
    pSlopeSce <- optiPlot(risomRessce, method = 'slope')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fusesom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fusesom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fusesom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FUSESOM:", paste0("    fusesom: ", packageVersion("FuseSOM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fusesom_results.csv
    touch ${prefix}_fusesom_output.rds
    echo "BIOC_FUSESOM:" > versions.yml
    echo "    fusesom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FUSESOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FUSESOM(ch_input)

    emit:
    results  = BIOC_FUSESOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FUSESOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FUSESOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FUSESOM.out.versions  // channel: path(versions.yml)
}
