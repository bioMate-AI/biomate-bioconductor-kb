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
    library(BayesSpace)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Parameter Tuning and Clustering [] ---
    # Key functions: qTune, spatialCluster
    melanoma <- qTune(
        melanoma,
        qs=seq(2, 10),
        platform="ST",
        d=7,
        cores=1
    )
    melanoma <- spatialCluster(
        melanoma,
        q=4,
        platform="ST",
        d=7,
        init.method="mclust",
        model="t",
        gamma=2,
        nrep=100,
        burn.in=10,
        save.chain=TRUE
    )


    # --- Spatial Resolution Enhancement [] ---
    # Key functions: spatialEnhance, enhanceFeatures
    melanoma_enhanced <- spatialEnhance(
        melanoma,
        q=4,
        platform="ST",
        d=7,
        model="t",
        gamma=2,
        jitter.prior=0.3,
        jitter.scale=3.5,
        nrep=100,
        burn.in=10,
        save.chain=TRUE,
        cores=1
    )
    markers <- c("PMEL", "CD2")
    melanoma_enhanced <- enhanceFeatures(
        melanoma_enhanced,
        melanoma,
        feature_names=markers,
        nrounds=0
    )


    # --- Visualization and Diagnostics [] ---
    # Key functions: clusterPlot, featurePlot, mcmcChain
    p1 <- clusterPlot(melanoma_enhanced)
    p2 <- featurePlot(melanoma_enhanced, "PMEL")
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
