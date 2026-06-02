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

    # --- Knitr Options [] ---
    # Key functions: set
    --------------
    library(knitr)
    opts_chunk$set(fig.align = 'center', fig.width = 6, fig.height = 5, dev = 'png')
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # load in the data
    data("risom_dat")
    # define the markers of interest
    # --- Runfusesom [] ---
    # Key functions: runFuseSOM
    ---------------------------------------------------------------------
    risomRes <- runFuseSOM(data = risom_dat, markers = risomMarkers,
                            numClusters = 23)
    # --- Markerheatmap [] ---
    # Key functions: markerHeatmap
    ---------------------------------------------------------------------
    risomHeat <- FuseSOM::markerHeatmap(data = risom_dat, markers = risomMarkers,
                                clusters = risomRes$clusters, clusterMarkers = TRUE)
    # --- Estimatenumcluster [] ---
    # Key functions: estimateNumCluster
    ---------------------------------------------------------------------
    # lets estimate the number of clusters using all the methods
    # original clustering has 23 clusters so we will set kseq from 2:25
    # we pass it the som model generated in the previous step
    # --- Optiplot [] ---
    # Key functions: optiPlot
    ---------------------------------------------------------------------
    # what is the best number of clusters determined by the discriminant method?
    # optimal number of clusters according to the discriminant method is 7
    risomKest$Discriminant
    # we can plot the results using the optiplot function
    # --- Runfusesom [] ---
    # Key functions: runFuseSOM, colData, metadata
    ---------------------------------------------------------------------
    risomRessce <- runFuseSOM(sce, markers = risomMarkers, assay = 'counts',
                          numClusters = 23, verbose = FALSE)
    colnames(colData(risomRessce))
    names(metadata(risomRessce))
    # --- Coldata [] ---
    # Key functions: colData, markerHeatmap
    ---------------------------------------------------------------------
    data <- risom_dat[, risomMarkers] # get the original data used
    clusters <- colData(risomRessce)$clusters # extract the clusters from the sce object
    # generate the heatmap
    # --- Estimatenumcluster [] ---
    # Key functions: estimateNumCluster, metadata
    ---------------------------------------------------------------------
    # lets estimate the number of clusters using all the methods
    # original clustering has 23 clusters so we will set kseq from 2:25
    # now we pass it a singlecellexperiment object instead of the som model as before
    # this will return a singelcellexperiment object where the metatdata contains the
    # --- Metadata [] ---
    # Key functions: metadata, optiPlot
    ---------------------------------------------------------------------
    # what is the best number of clusters determined by the discriminant method?
    # optimal number of clusters according to the discriminant method is 8
    metadata(risomRessce)$clusterEstimation$Discriminant
    # we can plot the results using the optiplot function

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
