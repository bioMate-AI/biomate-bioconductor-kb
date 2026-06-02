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

    # --- Path Finding [] ---
    # Key functions: find_paths
    data(g_small)
    nodes_sickle <- find_nodes(g_small, pattern = "sickle")[c(1, 3, 5)]
    nodes_malaria <- find_nodes(g_small, pattern = "malaria")
    paths <- find_paths(
        graph = g_small,
        from = nodes_sickle,
        to = nodes_malaria
    )
    path_lengths <- lengths(paths)


    # --- Edge Weighting and Customization [] ---
    # Key functions: get_edge_features, make_edge_weights, find_paths
    data(g_small)
    e_feat <- get_edge_features(g_small)
    w <- make_edge_weights(
        g_small,
        e_feat,
        node_semtypes_out = c("humn", "popg")
    )
    paths_reweight <- find_paths(
        graph = g_small,
        from = find_nodes(g_small, names = "sickle trait"),
        to = find_nodes(g_small, names = "Malaria, Cerebral"),
        weights = w
    )


    # --- Path Refinement and Middle Node Filtering [] ---
    # Key functions: get_middle_nodes, make_edge_weights, find_paths
    data(g_small)
    e_feat <- get_edge_features(g_small)
    paths_subset <- find_paths(
        graph = g_small,
        from = find_nodes(g_small, names = "sickle trait"),
        to = find_nodes(g_small, names = "Malaria, Cerebral")
    )[[1]]
    out_names <- get_middle_nodes(g_small, paths_subset)
    w_refined <- make_edge_weights(
        g_small,
        e_feat,
        node_names_out = out_names,
        node_semtypes_out = c("humn", "popg")
    )
    paths_refined <- find_paths(
        graph = g_small,
        from = find_nodes(g_small, pattern = "sickle trait"),
        to = find_nodes(g_small, pattern = "Malaria, Cerebral"),
        weights = w_refined
    )[[1]]


    # --- Path Summarization and Visualization [] ---
    # Key functions: summarize_semtypes, summarize_predicates, text_path, plot_path
    data(g_small)
    paths_subset <- find_paths(
        graph = g_small,
        from = find_nodes(g_small, names = "sickle trait"),
        to = find_nodes(g_small, names = "Malaria, Cerebral")
    )[[1]]
    semtype_summary <- summarize_semtypes(g_small, paths_subset)
    edge_summary <- summarize_predicates(g_small, paths_subset)
    this_path <- paths_subset[[1]]
    tp_text <- text_path(g_small, this_path)
    plot_path(g_small, this_path)

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
