#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clustifyr
// Package designed to aid in classifying cells from single-cell RNA sequencing data using external ref
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clustifyr/inst/doc/clustifyr.R
// Upstream  : SingleCellExperiment, cowplot, ggplot2
// Downstream: none
//
// Install: BiocManager::install("clustifyr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTIFYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clustifyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clustifyr:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clustifyr:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clustifyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clustifyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clustifyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clustifyr)
    library(jsonlite)

    # --- "Run clustifyr()" [] ---
    # Key functions: clustify, cor_to_call, call_to_metadata
    Calculate correlation coefficients for each cluster (spearman by default)
    res <- clustify(
    input = pbmc_matrix, # matrix of normalized scRNA-seq counts (or SCE/Seurat object)
    # --- "Create correlation heatmap" [] ---
    # Key functions: plot_cor_heatmap
    Create heatmap of correlation coefficients using clustifyr() output
    plot_cor_heatmap(cor_mat = res)
    # --- "Overlay corr coefficients on UMAP" [] ---
    # Key functions: plot_cor, plot_grid
    corr_umaps <- plot_cor(
    cor_mat = res, # matrix of correlation coefficients from clustifyr()
    data_to_plot = colnames(res)[1:2], # name of cell type(s) to plot correlation coefficients
    # --- "Label clusters" [] ---
    # Key functions: plot_best_call, ggtitle, plot_dims, plot_grid
    clustifyr_types <- plot_best_call(
    cor_mat = res, # matrix of correlation coefficients from clustifyr()
    ggtitle("clustifyr cell types")
    # --- "clustifyr with gene lists" [] ---
    # Key functions: clustify_lists, plot_cor_heatmap, cor_to_call, call_to_metadata, sce_pbmc
    list_res <- clustify_lists(
    plot_cor_heatmap(
    cor_mat = list_res, # matrix of correlation coefficients from clustify_lists()
    # --- "average" [] ---
    # Key functions: average_clusters, object_ref, seurat_ref
    new_ref_matrix <- average_clusters(
    head(new_ref_matrix)
    new_ref_matrix_sce <- object_ref(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clustifyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clustifyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clustifyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTIFYR:", paste0("    clustifyr: ", packageVersion("clustifyr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustifyr_results.csv
    touch ${prefix}_clustifyr_output.rds
    echo "BIOC_CLUSTIFYR:" > versions.yml
    echo "    clustifyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTIFYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTIFYR(ch_input)

    emit:
    results  = BIOC_CLUSTIFYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTIFYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTIFYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTIFYR.out.versions  // channel: path(versions.yml)
}
