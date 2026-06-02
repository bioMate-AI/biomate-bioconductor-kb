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


    # --- Pathway1 [] ---
    # Key functions: pathway, hsa04110
    library(ggkegg)
    library(tidygraph)
    library(dplyr)
    graph <- ggkegg::pathway("hsa04110", use_cache=TRUE)
    graph

    # --- Pathway1 1 [] ---
    # Key functions: mutate, centrality_degree, centrality_betweenness, activate, filter, arrange, desc, as_tibble
    graph |> 
        mutate(degree=centrality_degree(mode="all"),
            betweenness=centrality_betweenness()) |> 
        activate(nodes) |>
        filter(type=="gene") |>
        arrange(desc(degree)) |>
        as_tibble() |>
        relocate(degree, betweenness)

    # --- Plot Pathway1 [] ---
    # Key functions: mutate, vapply, ggraph, geom_edge_parallel, arrow, unit, circle, geom_node_rect

    # --- Plot Pathway2 [] ---
    # Key functions: mutate, ggraph, geom_edge_parallel, arrow, unit, circle, geom_node_point, geom_node_text
    graph |> mutate(x=NULL, y=NULL) |>
    ggraph(layout="nicely")+
        geom_edge_parallel(aes(color=subtype_name),
            arrow=arrow(length=unit(1,"mm"), type="closed"),
            end_cap=circle(0.1,"cm"),
            start_cap=circle(0.1,"cm"))+
        geom_node_point(aes(filter=type == "gene"),
                      color="black")+
        geom_node_point(aes(filter=type == "group"),
                      color="tomato")+

    # --- Convert [] ---
    # Key functions: activate, mutate, convert_id, filter, as_tibble, relocate, hsa, gene
    graph |>
        activate(nodes) |>
        mutate(hsa=convert_id("hsa")) |>
        filter(type == "gene") |>
        as_tibble() |>
        relocate(hsa)

    # --- Highlight [] ---
    # Key functions: activate, mutate, highlight_set_nodes, ggraph, geom_node_rect, geom_node_text, geom_edge_parallel, arrow
    graph |>
        activate(nodes) |>
        mutate(highlight=highlight_set_nodes("hsa:7157")) |>
        ggraph(layout="manual", x=x, y=y)+
        geom_node_rect(aes(fill=I(bgcolor),
                          filter=type == "gene"), color="black")+
        geom_node_rect(aes(fill="tomato", filter=highlight), color="black")+
        geom_node_text(aes(label=showname,
                          filter=type == "gene"), size=2)+

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
