#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Nebulosa
// This package provides a enhanced visualization of single-cell data based on gene-weighted density es
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Nebulosa/inst/doc/introduction.R
// Upstream  : BiocFileCache, DropletUtils, Seurat, scater, scran
// Downstream: none
//
// Install: BiocManager::install("Nebulosa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NEBULOSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nebulosa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nebulosa:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nebulosa:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nebulosa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nebulosa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nebulosa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(jsonlite)

    # --- Filter by row sum threshold [] ---
    # Key functions: rowSums, perCellQCMetrics, quickPerCellQC
    is_mito <- grepl("^MT-", rownames(pbmc))
    qcstats <- perCellQCMetrics(pbmc, subsets = list(Mito = is_mito))
    qcfilter <- quickPerCellQC(qcstats, percent_subsets = c("subsets_Mito_percent"))
    # --- Build SNN graph for clustering [] ---
    # Key functions: buildSNNGraph, cluster_louvain, colLabels
    g <- buildSNNGraph(pbmc, k = 10, use.dimred = "PCA")
    clust <- igraph::cluster_louvain(g)$membership
    colLabels(pbmc) <- factor(clust)
    # --- Run PCA [] ---
    # Key functions: runPCA, runUMAP
    set.seed(66)
    pbmc <- runPCA(pbmc, scale = TRUE, subset_row = top_hvgs)
    # --- Feature metadata inspection [] ---
    # Key functions: BiocFileCache, bfcrpath, untar, read10xCounts, rowData, colSums, logcounts, modelGeneVar
    bfc <- BiocFileCache(ask = FALSE)
    data_file <- bfcrpath(bfc, file.path(
    untar(data_file, exdir = tempdir())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nebulosa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nebulosa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nebulosa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NEBULOSA:", paste0("    nebulosa: ", packageVersion("Nebulosa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nebulosa_results.csv
    touch ${prefix}_nebulosa_output.rds
    echo "BIOC_NEBULOSA:" > versions.yml
    echo "    nebulosa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NEBULOSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NEBULOSA(ch_input)

    emit:
    results  = BIOC_NEBULOSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NEBULOSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NEBULOSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NEBULOSA.out.versions  // channel: path(versions.yml)
}
