#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rsemmed
// A programmatic interface to the Semantic MEDLINE database. It provides functions for searching the d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rsemmed/inst/doc/rsemmed_user_guide.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rsemmed")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSEMMED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsemmed"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsemmed:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsemmed:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsemmed_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsemmed_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsemmed_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rsemmed)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(rsemmed)
    data(g_small)
    # --- Find Nodes [] ---
    # Key functions: find_nodes
    ---------------------------------------------------------------------
    nodes_sickle <- find_nodes(g_small, pattern = "sickle")
    nodes_sickle
    # --- Disease [] ---
    # Key functions: disease, find_nodes
    ---------------------------------------------------------------------
    ## malaria OR disease (dsyn)
    find_nodes(g_small, pattern = "malaria", semtypes = "dsyn")
    ## malaria AND disease (dsyn)
    find_nodes(g_small, pattern = "malaria") %>%
    # --- Find Nodes [] ---
    # Key functions: find_nodes
    ---------------------------------------------------------------------
    find_nodes(g_small, names = "sickle trait")
    find_nodes(g_small, names = "SICKLE trait")
    # --- Find Paths [] ---
    # Key functions: find_paths
    ---------------------------------------------------------------------
    paths <- find_paths(graph = g_small, from = nodes_sickle, to = nodes_malaria)
    # --- Lengths [] ---
    # Key functions: lengths
    ---------------------------------------------------------------------
    lengths(paths)
    # --- Get Edge Features [] ---
    # Key functions: get_edge_features
    ---------------------------------------------------------------------
    e_feat <- get_edge_features(g_small)
    head(e_feat)
    # --- Make Edge Weights [] ---
    # Key functions: make_edge_weights, find_paths, find_nodes
    ---------------------------------------------------------------------
    w <- make_edge_weights(g_small, e_feat, node_semtypes_out = c("humn", "popg"))
    paths_subset_reweight <- find_paths(
        graph = g_small,
        from = find_nodes(g_small, names = "sickle trait"),
    # --- Nodes [] ---
    # Key functions: nodes, get_middle_nodes, make_edge_weights, find_paths, find_nodes
    ---------------------------------------------------------------------
    ## Obtain the middle nodes (2nd node on the path)
    out_names <- get_middle_nodes(g_small, paths_subset)
    ## Readjust weights
    w <- make_edge_weights(g_small, e_feat,
    # --- Get Middle Nodes [] ---
    # Key functions: get_middle_nodes
    ---------------------------------------------------------------------
    get_middle_nodes(g_small, paths, collapse = FALSE)
    # --- Make Edge Weights [] ---
    # Key functions: make_edge_weights, find_paths, find_nodes
    ---------------------------------------------------------------------
    w <- make_edge_weights(g_small, e_feat,
        node_semtypes_out = c("humn", "popg"),
        node_semtypes_in = c("gngm", "aapp")
    )
    # --- Summarize Semtypes [] ---
    # Key functions: summarize_semtypes
    ---------------------------------------------------------------------
    ## Reweighted paths from "sickle trait" to "Malaria, Cerebral"
    semtype_summary <- summarize_semtypes(g_small, paths_subset_reweight)
    semtype_summary
    semtype_summary$semtypes[[1]]
    # --- Summarize Predicates [] ---
    # Key functions: summarize_predicates
    ---------------------------------------------------------------------
    edge_summary <- summarize_predicates(g_small, paths)
    edge_summary
    edge_summary$predicates[[1]]
    # --- Grow Nodes [] ---
    # Key functions: grow_nodes
    ---------------------------------------------------------------------
    nodes_sickle_trait <- nodes_sickle[2:3]
    nodes_sickle_trait
    nbrs_sickle_trait <- grow_nodes(g_small, nodes_sickle_trait)
    nbrs_sickle_trait
    # --- Summarize Semtypes [] ---
    # Key functions: summarize_semtypes
    ---------------------------------------------------------------------
    nbrs_sickle_trait_summ <- summarize_semtypes(g_small, nbrs_sickle_trait, is_path = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsemmed_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsemmed_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsemmed_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSEMMED:", paste0("    rsemmed: ", packageVersion("rsemmed"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsemmed_results.csv
    touch ${prefix}_rsemmed_output.rds
    echo "BIOC_RSEMMED:" > versions.yml
    echo "    rsemmed: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSEMMED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSEMMED(ch_input)

    emit:
    results  = BIOC_RSEMMED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSEMMED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSEMMED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSEMMED.out.versions  // channel: path(versions.yml)
}
