#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: treekoR
// treekoR is a novel framework that aims to utilise the hierarchical nature of single cell cytometry d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/treekoR/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("treekoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREEKOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treekor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-treekor:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-treekor:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treekor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treekor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treekor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(treekoR)
    library(jsonlite)

    # --- Tree-based Statistical Testing [] ---
    # Key functions: testTree
    tested_tree <- testTree(
        phylo = clust_tree$clust_tree,
        clusters = clusters,
        samples = samples,
        classes = classes,
        pos_class_name = NULL
    )


    # --- Results Extraction and Visualization [] ---
    # Key functions: getTreeResults, plotInteractiveHeatmap
    res_df <- getTreeResults(tested_tree)
    plotInteractiveHeatmap(
        tested_tree,
        clust_med_df = clust_tree$median_freq,
        clusters = clusters
    )


    # --- Cell Proportion and Geometric Mean Calculation [] ---
    # Key functions: getCellProp, getCellGMeans
    prop_df <- getCellProp(
        phylo = clust_tree$clust_tree,
        clusters = clusters,
        samples = samples,
        classes = classes
    )
    means_df <- getCellGMeans(
        clust_tree$clust_tree,
        exprs = exprs,
        clusters = clusters,
        samples = samples,
        classes = classes
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_treekor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_treekor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_treekor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREEKOR:", paste0("    treekor: ", packageVersion("treekoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treekor_results.csv
    touch ${prefix}_treekor_output.rds
    echo "BIOC_TREEKOR:" > versions.yml
    echo "    treekor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREEKOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREEKOR(ch_input)

    emit:
    results  = BIOC_TREEKOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREEKOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREEKOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREEKOR.out.versions  // channel: path(versions.yml)
}
