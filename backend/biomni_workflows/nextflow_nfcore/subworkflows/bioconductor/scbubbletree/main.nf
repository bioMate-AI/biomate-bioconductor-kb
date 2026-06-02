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
    library(CreateSeuratObject)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: create, objects, colData, CreateSeuratObject
    ---------------------------------------------------------------------
    # # This script can be used to generate data("d_ccl", package = "scBubbletree")
    #
    # # create directory
    # dir.create(path = "case_study/")
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # Load the data
    data("d_ccl", package = "scBubbletree")
    # --- Columns [] ---
    # Key functions: columns
    ---------------------------------------------------------------------
    # Extract the 15-dimensional PCA matrix A
    # A has n=cells as rows, f=15 features as columns (e.g. from PCA)
    A <- d_ccl$A
    dim(A)
    # --- Get R [] ---
    # Key functions: get_r
    ---------------------------------------------------------------------
    # --- Kable [] ---
    # Key functions: kable
    ---------------------------------------------------------------------
    knitr::kable(x = b_r$gap_stats_summary[b_r$gap_stats_summary$k == 5, ],
                 digits = 4, row.names = FALSE)
    # --- Get K [] ---
    # Key functions: get_k
    ---------------------------------------------------------------------
    # --- Get Bubbletree Graph [] ---
    # Key functions: get_bubbletree_graph
    ---------------------------------------------------------------------
    # --- Kable [] ---
    # Key functions: kable
    ---------------------------------------------------------------------
    knitr::kable(l$tree_meta, digits = 2, row.names = FALSE)
    # --- Get Bubbletree Kmeans [] ---
    # Key functions: get_bubbletree_kmeans
    ---------------------------------------------------------------------
    # --- Get Gini [] ---
    # Key functions: get_gini
    ---------------------------------------------------------------------
    # gini
    get_gini(labels = m$cell_line_demuxlet,
             clusters = l$cluster)$gi
    # --- Get Gini K [] ---
    # Key functions: get_gini_k
    ---------------------------------------------------------------------
    gini_boot <- get_gini_k(labels = m$cell_line_demuxlet, obj = b_r)

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
