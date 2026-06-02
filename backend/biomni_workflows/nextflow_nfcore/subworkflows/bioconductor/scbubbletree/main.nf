#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scBubbletree
// scBubbletree is a quantitative method for the visual exploration of scRNA-seq data, preserving key b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scBubbletree/inst/doc/User_manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scBubbletree")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCBUBBLETREE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scbubbletree"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scbubbletree:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scbubbletree:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(seurat)

    output:
    tuple val(meta), path("${meta.id}_scbubbletree_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scbubbletree_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scbubbletree_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scBubbletree)
    library(CreateSeuratObject)
    library(jsonlite)

    # --- Resolution Parameter Estimation [] ---
    # Key functions: get_r
    data("d_ccl", package = "scBubbletree")
    A <- d_ccl$A
    b_r <- get_r(
        B_gap = 5,
        rs = 10^seq(from = -4, to = 0.5, by = 0.5),
        x = A,
        n_start = 10,
        iter_max = 50,
        algorithm = "original",
        knn_k = 50,
        cores = 1
    )

    # --- Cluster Number Estimation [] ---
    # Key functions: get_k
    data("d_ccl", package = "scBubbletree")
    A <- d_ccl$A
    b_k <- get_k(
        B_gap = 5,
        ks = 1:10,
        x = A,
        n_start = 50,
        iter_max = 200,
        kmeans_algorithm = "MacQueen",
        cores = 1
    )

    # --- Bubble Tree Graph Construction [] ---
    # Key functions: get_bubbletree_graph
    data("d_ccl", package = "scBubbletree")
    A <- d_ccl$A
    l <- get_bubbletree_graph(
        x = A,
        r = 0.1,
        algorithm = "original",
        n_start = 20,
        iter_max = 100,
        knn_k = 50,
        cores = 1,
        B = 300,
        N_eff = 200,
        round_digits = 1,
        show_simple_count = FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scbubbletree_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scbubbletree_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scbubbletree_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCBUBBLETREE:", paste0("    scbubbletree: ", packageVersion("scBubbletree"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scbubbletree_results.csv
    touch ${prefix}_scbubbletree_output.rds
    echo "BIOC_SCBUBBLETREE:" > versions.yml
    echo "    scbubbletree: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCBUBBLETREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat) ]

    main:
    BIOC_SCBUBBLETREE(ch_input)

    emit:
    results  = BIOC_SCBUBBLETREE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCBUBBLETREE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCBUBBLETREE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCBUBBLETREE.out.versions  // channel: path(versions.yml)
}
