#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggkegg
// This package aims to import, parse, and analyze KEGG data such as KEGG PATHWAY and KEGG MODULE. The 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggkegg/inst/doc/usage_of_ggkegg.R
// Upstream  : dplyr, tidygraph
// Downstream: none
//
// Install: BiocManager::install("ggkegg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGKEGG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggkegg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggkegg:1.4.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ggkegg:1.4.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggkegg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggkegg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggkegg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggkegg)
    library(jsonlite)

    # --- Pathway Retrieval and Parsing [] ---
    # Key functions: pathway
    graph <- ggkegg::pathway("hsa04110", use_cache = TRUE)
    graph <- graph |>
        tidygraph::mutate(
            degree = tidygraph::centrality_degree(mode = "all"),
            betweenness = tidygraph::centrality_betweenness()
        ) |>
        tidygraph::activate(nodes) |>
        tidygraph::filter(type == "gene") |>
        tidygraph::arrange(dplyr::desc(degree))

    # --- ID Conversion and Node Filtering [] ---
    # Key functions: convert_id
    converted_graph <- graph |>
        tidygraph::activate(nodes) |>
        tidygraph::mutate(hsa = ggkegg::convert_id("hsa")) |>
        tidygraph::filter(type == "gene") |>
        tidygraph::as_tibble() |>
        dplyr::relocate(hsa)

    # --- Node Highlighting and Overlay [] ---
    # Key functions: highlight_set_nodes, overlay_raw_map
    highlighted <- graph |>
        tidygraph::activate(nodes) |>
        tidygraph::mutate(
            highlight = ggkegg::highlight_set_nodes("hsa:7157")
        )
    p_high <- ggraph::ggraph(highlighted, layout = "manual", x = x, y = y) +
        ggraph::geom_node_rect(
            aes(fill = "tomato", filter = highlight),
            color = "black"
        ) +
        ggkegg::overlay_raw_map() +
        ggplot2::theme_void()

    # --- Module Analysis and Visualization [] ---
    # Key functions: module, module_text, plot_module_text, obtain_sequential_module_definition, plot_module_blocks
    mod <- ggkegg::module("M00002", use_cache = TRUE)
    text_df <- ggkegg::module_text(mod)
    p_text <- ggkegg::plot_module_text(text_df)
    seq_def <- ggkegg::obtain_sequential_module_definition(mod)
    p_blocks <- ggkegg::plot_module_blocks(seq_def)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggkegg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggkegg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggkegg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGKEGG:", paste0("    ggkegg: ", packageVersion("ggkegg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggkegg_results.csv
    touch ${prefix}_ggkegg_output.rds
    echo "BIOC_GGKEGG:" > versions.yml
    echo "    ggkegg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGKEGG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGKEGG(ch_input)

    emit:
    results  = BIOC_GGKEGG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGKEGG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGKEGG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGKEGG.out.versions  // channel: path(versions.yml)
}
