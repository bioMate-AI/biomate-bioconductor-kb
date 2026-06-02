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

    # --- Hierarchical clustering [] ---
    # Key functions: rowData, hclust
    rts <- rowData(se)$rtmed
    fit <- hclust(dist(rts, "manhattan"))
    plot(as.dendrogram(fit), leaflab = "none")
    # --- Custom ggplot2 visualization [] ---
    # Key functions: imputeIntensity, assay, ggplot, geom_point
    se <- imputeIntensity(faahko_se, i = "raw", name = "knn", method = "knn")
    m <- assay(faahko_se, "raw")
    knn_scaled <- as.data.frame(
    # --- Feature metadata inspection [] ---
    # Key functions: plotMiss, normalizeIntensity, plotBox, reduceFeatures, plotReduced, clusterFeatures, rowData, plotRTgroup
    se <- normalizeIntensity(se, i = "knn", name = "knn_vsn", method = "vsn")
    p1 <- plotBox(se, i = "knn", group = g, log2 = TRUE) # before normalization
    p2 <- plotBox(se, i = "knn_vsn", group = g) # after normalization

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
