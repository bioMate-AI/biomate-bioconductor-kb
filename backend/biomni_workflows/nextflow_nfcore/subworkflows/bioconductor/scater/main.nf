#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scater
// A collection of tools for doing various analyses of single-cell RNA-seq gene expression data, with a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scater/inst/doc/overview.R
// Upstream  : scRNAseq
// Downstream: netSmooth, OSCA.advanced, OSCA.basic, OSCA.intro, OSCA.multisample
//
// Install: BiocManager::install("scater")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCATER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scater"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scater:1.34.1--r44_0' :
        'quay.io/biocontainers/bioconductor-scater:1.34.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scater_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scater_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scater_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scater)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Normalisation and Variance Explanation [] ---
    # Key functions: logNormCounts, getVarianceExplained, plotExplanatoryVariables
    example_sce <- logNormCounts(example_sce)
    vars <- getVarianceExplained(example_sce,
        variables=c("tissue", "total mRNA mol", "sex", "age"))
    var_plot <- plotExplanatoryVariables(vars)


    # --- Dimensionality Reduction [] ---
    # Key functions: runPCA, runTSNE, runUMAP
    example_sce <- runPCA(example_sce, ncomponents=20)
    example_sce <- runTSNE(example_sce, perplexity=10,
        dimred="PCA", n_dimred=10)
    example_sce <- runUMAP(example_sce)


    # --- Reduced Dimension Visualisation [] ---
    # Key functions: plotPCA, plotTSNE, plotReducedDim
    pca_plot <- plotPCA(example_sce, colour_by="Mog")
    tsne_plot <- plotTSNE(example_sce, colour_by="Snap25")
    reduced_plot <- plotReducedDim(example_sce, dimred="PCA",
        colour_by="level1class")


    # --- Gene Expression Visualisation [] ---
    # Key functions: plotExpression, ggcells, ggfeatures
    expr_plot <- plotExpression(example_sce,
        rownames(example_sce)[1:6], x="level1class",
        colour_by="tissue")
    cell_plot <- ggcells(example_sce,
        mapping=ggplot2::aes(x=level1class, y=Snap25))
    colnames(example_sce) <- make.names(colnames(example_sce))
    feat_plot <- ggfeatures(example_sce,
        mapping=ggplot2::aes(x=featureType, y=X1772062111_E06))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scater_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scater_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scater_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCATER:", paste0("    scater: ", packageVersion("scater"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scater_results.csv
    touch ${prefix}_scater_output.rds
    echo "BIOC_SCATER:" > versions.yml
    echo "    scater: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCATER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCATER(ch_input)

    emit:
    results  = BIOC_SCATER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCATER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCATER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCATER.out.versions  // channel: path(versions.yml)
}
