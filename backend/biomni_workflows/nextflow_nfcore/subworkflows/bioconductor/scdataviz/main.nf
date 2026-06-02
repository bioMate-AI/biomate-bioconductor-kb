#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDataviz
// In the single cell World, which includes flow cytometry, mass cytometry, single-cell RNA-seq (scRNA-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDataviz/inst/doc/scDataviz.R
// Upstream  : PCAtools, flowCore, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("scDataviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDATAVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scdataviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scdataviz:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scdataviz:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_scdataviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scdataviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scdataviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scDataviz)
    library(jsonlite)


    # --- Load [] ---
    # Key functions: load, pca, assay, metadata, biplot
    load(system.file('extdata/', 'complosome.rdata', package = 'scDataviz'))
    library(PCAtools)
      p <- pca(assay(sce, 'scaled'), metadata = metadata(sce))

    # --- Add Pcadim [] ---
    # Key functions: reducedDim, performUMAP
    reducedDim(sce, 'PCA') <- p$rotated
    sce <- performUMAP(sce)

    # --- Elbow Horn [] ---
    # Key functions: findElbowPoint, parallelPCA, assay, performUMAP
    elbow <- findElbowPoint(p$variance)
      horn <- parallelPCA(assay(sce, 'scaled'))

      elbow
      horn$n
    sce <- performUMAP(sce, reducedDim = 'PCA', dims = c(1:5))

    # --- Ex2 [] ---
    # Key functions: contourPlot, plot_grid, sample, markerExpression
    ggout1 <- contourPlot(sce,
        reducedDim = 'UMAP',
        bins = 150,
        subtitle = 'UMAP performed on expression values',
        legendLabSize = 18,
        axisLabSize = 22,
        titleLabSize = 22,
        subtitleLabSize = 18,
        captionLabSize = 18)

    markers <- sample(rownames(sce), 6)
      markers

    # --- Metadata Plot [] ---
    # Key functions: metadata, metadataPlot, plot_grid
    head(metadata(sce))

      levels(metadata(sce)$group)

      levels(metadata(sce)$treatment)
    ggout1 <- metadataPlot(sce,
        colby = 'group',
        colkey = c(Healthy = 'royalblue', Disease = 'red2'),
        title = 'Disease status',
        subtitle = 'UMAP performed on expression values',
        legendLabSize = 16,
        axisLabSize = 20,
        titleLabSize = 20,
        subtitleLabSize = 16,
        captionLabSize = 16)

    # --- Ex5 [] ---
    # Key functions: clusKNN, plotClusters, plot_grid, metadata, sample, markerExpressionPerCluster
    sce <- clusKNN(sce,
        k.param = 20,
        prune.SNN = 1/15,
        resolution = 0.01,
        algorithm = 2,
        verbose = FALSE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scdataviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scdataviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scdataviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDATAVIZ:", paste0("    scdataviz: ", packageVersion("scDataviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scdataviz_results.csv
    touch ${prefix}_scdataviz_output.rds
    echo "BIOC_SCDATAVIZ:" > versions.yml
    echo "    scdataviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDATAVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SCDATAVIZ(ch_input)

    emit:
    results  = BIOC_SCDATAVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDATAVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDATAVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDATAVIZ.out.versions  // channel: path(versions.yml)
}
