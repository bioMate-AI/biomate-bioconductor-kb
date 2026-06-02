#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BayesSpace
// Tools for clustering and enhancing the resolution of spatial gene expression experiments. BayesSpace
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BayesSpace/inst/doc/BayesSpace.R
// Upstream  : Matrix
// Downstream: none
//
// Install: BiocManager::install("BayesSpace")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAYESSPACE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bayesspace"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bayesspace:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bayesspace:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bayesspace_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bayesspace_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bayesspace_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- read Visium [] ---
    # Key functions: readVisium
    sce <- readVisium("path/to/spaceranger/outs/")
    # --- get R D S [] ---
    # Key functions: getRDS
    melanoma <- getRDS(dataset="2018_thrane_melanoma", sample="ST_mel1_rep2")
    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment
    library(Matrix)
    rowData <- read.csv("path/to/rowData.csv", stringsAsFactors=FALSE)
    colData <- read.csv("path/to/colData.csv", stringsAsFactors=FALSE, row.names=1)
    # --- spatial Preprocess [] ---
    # Key functions: spatialPreprocess
    set.seed(102)
    melanoma <- spatialPreprocess(melanoma, platform="ST",
    # --- tuning q [] ---
    # Key functions: qTune, qPlot
    melanoma <- qTune(melanoma, qs=seq(2, 10), platform="ST", d=7, cores=2)
    qPlot(melanoma)
    # --- spatial Cluster [] ---
    # Key functions: spatialCluster
    set.seed(149)
    melanoma <- spatialCluster(melanoma, q=4, platform="ST", d=7,
    # --- cluster Plot [] ---
    # Key functions: clusterPlot
    clusterPlot(melanoma)
    # --- cluster.plot.customize [] ---
    # Key functions: clusterPlot, theme_bw, xlab, ylab, labs
    clusterPlot(melanoma, palette=c("purple", "red", "blue", "yellow"), color="black") +
    theme_bw() +
    xlab("Column") +
    # --- cluster Plot [] ---
    # Key functions: clusterPlot
    clusterPlot(melanoma.enhanced)
    # --- enhanced.logcount [] ---
    # Key functions: logcounts
    logcounts(melanoma.enhanced)[markers, 1:5]
    # --- row Data [] ---
    # Key functions: rowData
    rowData(melanoma.enhanced)[markers, ]
    # --- feature Plot [] ---
    # Key functions: featurePlot
    featurePlot(melanoma.enhanced, "PMEL")
    # --- enhanced.markers [] ---
    # Key functions: wrap_plots
    enhanced.plots <- purrr::map(markers, function(x) featurePlot(melanoma.enhanced, x))
    patchwork::wrap_plots(enhanced.plots, ncol=2)
    # --- compare.resolution [] ---
    # Key functions: wrap_plots
    spot.plots <- purrr::map(markers, function(x) featurePlot(melanoma, x))
    patchwork::wrap_plots(c(enhanced.plots, spot.plots), ncol=4)
    # --- mcmc Chain [] ---
    # Key functions: mcmcChain
    chain <- mcmcChain(melanoma)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bayesspace_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bayesspace_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bayesspace_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAYESSPACE:", paste0("    bayesspace: ", packageVersion("BayesSpace"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesspace_results.csv
    touch ${prefix}_bayesspace_output.rds
    echo "BIOC_BAYESSPACE:" > versions.yml
    echo "    bayesspace: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAYESSPACE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAYESSPACE(ch_input)

    emit:
    results  = BIOC_BAYESSPACE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAYESSPACE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAYESSPACE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAYESSPACE.out.versions  // channel: path(versions.yml)
}
