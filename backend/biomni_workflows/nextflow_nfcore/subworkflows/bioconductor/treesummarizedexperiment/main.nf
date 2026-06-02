#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TreeSummarizedExperiment
// TreeSummarizedExperiment has extended SingleCellExperiment to include hierarchical information on th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TreeSummarizedExperiment/inst/doc/Introduction_to_treeSummarizedExperiment.R
// Upstream  : ape, ggtree, ggplot2
// Downstream: ExperimentSubset, HoloFoodR, MGnifyR, mia, miaSim
//
// Install: BiocManager::install("TreeSummarizedExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREESUMMARIZEDEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treesummarizedexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-treesummarizedexperiment:2.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-treesummarizedexperiment:2.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treesummarizedexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treesummarizedexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treesummarizedexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TreeSummarizedExperiment)
    library(jsonlite)

    # --- ggtree [] ---
    # Key functions: ggtree, geom_text2
    library(ggtree)
    library(ggplot2)
    ggtree(row_tree, size = 2, branch.length = "none") +
    # --- ggtree [] ---
    # Key functions: ggtree, geom_text2, ylim, xlim, all
    ggtree(col_tree, size = 2, branch.length = "none") +
    geom_text2(aes(label = node), color = "darkblue",
    geom_text2(aes(label = label), color = "darkorange",
    # --- to Tree [] ---
    # Key functions: toTree, ggtree, geom_text2, geom_point2, changeTree
    (taxa <- rowData(both_tse))
    taxa_tree <- toTree(data = taxa)
    ggtree(taxa_tree)+
    # --- ggtree [] ---
    # Key functions: ggtree, geom_text2, convertNode, findDescendant
    data("tinyTree")
    ggtree(tinyTree, branch.length = "none") +
    geom_text2(aes(label = label), hjust = -0.1, size = 5.5) +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_treesummarizedexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_treesummarizedexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_treesummarizedexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREESUMMARIZEDEXPERIMENT:", paste0("    treesummarizedexperiment: ", packageVersion("TreeSummarizedExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treesummarizedexperiment_results.csv
    touch ${prefix}_treesummarizedexperiment_output.rds
    echo "BIOC_TREESUMMARIZEDEXPERIMENT:" > versions.yml
    echo "    treesummarizedexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREESUMMARIZEDEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREESUMMARIZEDEXPERIMENT(ch_input)

    emit:
    results  = BIOC_TREESUMMARIZEDEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREESUMMARIZEDEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREESUMMARIZEDEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREESUMMARIZEDEXPERIMENT.out.versions  // channel: path(versions.yml)
}
