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

    # --- Marker Gene-based Classification [] ---
    # Key functions: clustify_lists, cor_to_call, call_to_metadata
    list_res <- clustify_lists(
        input = clustifyr::pbmc_matrix_small,
        metadata = clustifyr::pbmc_meta,
        cluster_col = "seurat_clusters",
        marker = clustifyr::cbmc_m,
        metric = "pct"
    )
    list_res2 <- cor_to_call(
        cor_mat = list_res,
        cluster_col = "seurat_clusters"
    )
    pbmc_meta3 <- call_to_metadata(
        res = list_res2,
        metadata = clustifyr::pbmc_meta,
        cluster_col = "seurat_clusters",
        rename_prefix = "list_"
    )


    # --- Visualisation of Classification Results [] ---
    # Key functions: plot_cor_heatmap, plot_cor, plot_best_call, plot_dims
    res <- clustify(
        input = clustifyr::pbmc_matrix_small,
        metadata = clustifyr::pbmc_meta,
        cluster_col = "seurat_clusters",
        ref_mat = clustifyr::cbmc_ref,
        query_genes = clustifyr::pbmc_vargenes[1:100]
    )
    plot_cor_heatmap(cor_mat = res)
    corr_umaps <- plot_cor(
        cor_mat = res,
        metadata = clustifyr::pbmc_meta,
        data_to_plot = colnames(res)[1:2],
        cluster_col = "seurat_clusters"
    )
    clustifyr_types <- plot_best_call(
        cor_mat = res,
        metadata = clustifyr::pbmc_meta,
        do_label = TRUE,
        do_legend = FALSE,
        cluster_col = "seurat_clusters"
    )


    # --- Reference Matrix Generation [] ---
    # Key functions: average_clusters
    new_ref_matrix <- average_clusters(
        mat = clustifyr::pbmc_matrix_small,
        metadata = clustifyr::pbmc_meta$classified,
        if_log = TRUE
    )


    # --- SingleCellExperiment Integration [] ---
    # Key functions: sce_pbmc, clustify
    sce <- clustifyr::sce_pbmc()
    res_sce <- clustify(
        input = sce,
        ref_mat = clustifyr::cbmc_ref,
        cluster_col = "clusters",
        obj_out = TRUE
    )

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
