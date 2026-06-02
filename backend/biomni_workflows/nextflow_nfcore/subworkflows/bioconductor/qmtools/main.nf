#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qmtools
// The qmtools (quantitative metabolomics tools) package provides basic tools for processing quantitati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qmtools/inst/doc/qmtools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("qmtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QMTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qmtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qmtools:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qmtools:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_qmtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qmtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qmtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qmtools)
    library(jsonlite)

    # --- Intensity Imputation [] ---
    # Key functions: imputeIntensity
    se_imputed <- imputeIntensity(
        se_filtered, i = "raw",
        name = "knn", method = "knn"
    )


    # --- Intensity Normalization [] ---
    # Key functions: normalizeIntensity, plotBox
    se_norm <- normalizeIntensity(
        se_imputed, i = "knn",
        name = "knn_vsn", method = "vsn"
    )
    p1 <- plotBox(se_norm, i = "knn", group = g, log2 = TRUE)
    p2 <- plotBox(se_norm, i = "knn_vsn", group = g)


    # --- Dimensionality Reduction [] ---
    # Key functions: reduceFeatures, plotReduced
    m_pca <- reduceFeatures(
        se_norm, i = "knn_vsn",
        method = "pca", ncomp = 2
    )
    m_plsda <- reduceFeatures(
        se_norm, i = "knn_vsn",
        method = "plsda", ncomp = 2, y = g
    )
    p_pca <- plotReduced(m_pca, group = g)
    p_plsda <- plotReduced(m_plsda, label = TRUE, ellipse = TRUE)


    # --- Feature Clustering [] ---
    # Key functions: clusterFeatures, plotRTgroup
    se_clust <- clusterFeatures(
        se_norm, i = "knn_vsn",
        rtime_var = "rtmed",
        rt_cut = 10, cor_cut = 0.7,
        cor_grouping = "louvain"
    )
    plotRTgroup(se_clust, i = "knn_vsn", group = "FG.22")


    # --- Differential Abundance Analysis [] ---
    # Key functions: compareSamples
    fit <- compareSamples(
        se_clust, i = "knn_vsn",
        group = "sample_group",
        class1 = "WT", class2 = "KO"
    )
    head(fit, 5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qmtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qmtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qmtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QMTOOLS:", paste0("    qmtools: ", packageVersion("qmtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qmtools_results.csv
    touch ${prefix}_qmtools_output.rds
    echo "BIOC_QMTOOLS:" > versions.yml
    echo "    qmtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QMTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_QMTOOLS(ch_input)

    emit:
    results  = BIOC_QMTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QMTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QMTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QMTOOLS.out.versions  // channel: path(versions.yml)
}
