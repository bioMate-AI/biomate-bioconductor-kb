#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SC3
// A tool for unsupervised clustering and analysis of single cell RNA-Seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SC3/inst/doc/SC3.R
// Upstream  : SingleCellExperiment, knitr, mclust, scater
// Downstream: none
//
// Install: BiocManager::install("SC3")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SC3 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sc3"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sc3:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sc3:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sc3_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sc3_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sc3_plots.pdf"),    emit: plots, optional: true
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

    # --- Knitr Options [] ---
    # Key functions: set
    --------------
    library(knitr)
    opts_chunk$set(fig.align = 'center', fig.width = 6, fig.height = 5, dev = 'png')
    # --- Singlecellexperiment [] ---
    # Key functions: SingleCellExperiment, rowData
    ---------------------------------------------------------------------
    # create a SingleCellExperiment object
    # --- Runpca [] ---
    # Key functions: runPCA, plotPCA
    ---------------------------------------------------------------------
    sce <- runPCA(sce)
    plotPCA(sce, colour_by = "cell_type1")
    # --- Sc3 [] ---
    # Key functions: sc3
    ---------------------------------------------------------------------
    sce <- sc3(sce, ks = 2:4, biology = TRUE)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    col_data <- colData(sce)
    head(col_data[ , grep("sc3_", colnames(col_data))])
    # --- Runpca [] ---
    # Key functions: runPCA, plotPCA
    ---------------------------------------------------------------------
    sce <- runPCA(sce)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    row_data <- rowData(sce)
    head(row_data[ , grep("sc3_", colnames(row_data))])
    # --- Sc3 Plot Silhouette [] ---
    # Key functions: sc3_plot_silhouette
    ---------------------------------------------------------------------
    sc3_plot_silhouette(sce, k = 3)
    # --- Sc3 Prepare [] ---
    # Key functions: sc3_prepare, metadata
    ---------------------------------------------------------------------
    sce <- sc3_prepare(sce)
    str(metadata(sce)$sc3)
    # --- Sc3 Estimate K [] ---
    # Key functions: sc3_estimate_k, metadata
    ---------------------------------------------------------------------
    sce <- sc3_estimate_k(sce)
    str(metadata(sce)$sc3)
    # --- Sc3 Calc Dists [] ---
    # Key functions: sc3_calc_dists, metadata
    ---------------------------------------------------------------------
    sce <- sc3_calc_dists(sce)
    names(metadata(sce)$sc3$distances)
    # --- Sc3 Calc Transfs [] ---
    # Key functions: sc3_calc_transfs, metadata
    ---------------------------------------------------------------------
    sce <- sc3_calc_transfs(sce)
    names(metadata(sce)$sc3$transformations)
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(sce)$sc3$distances
    # --- Sc3 Kmeans [] ---
    # Key functions: sc3_kmeans, metadata
    ---------------------------------------------------------------------
    sce <- sc3_kmeans(sce, ks = 2:4)
    names(metadata(sce)$sc3$kmeans)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    col_data <- colData(sce)
    head(col_data[ , grep("sc3_", colnames(col_data))])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sc3_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sc3_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sc3_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SC3:", paste0("    sc3: ", packageVersion("SC3"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc3_results.csv
    touch ${prefix}_sc3_output.rds
    echo "BIOC_SC3:" > versions.yml
    echo "    sc3: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SC3_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SC3(ch_input)

    emit:
    results  = BIOC_SC3.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SC3.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SC3.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SC3.out.versions  // channel: path(versions.yml)
}
