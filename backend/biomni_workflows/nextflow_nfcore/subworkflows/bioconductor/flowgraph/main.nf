#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowGraph
// Identifies maximal differential cell populations in flow cytometry data taking into account dependen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowGraph/inst/doc/flowGraph.R
// Upstream  : BiocManager
// Downstream: none
//
// Install: BiocManager::install("flowGraph")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWGRAPH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowgraph"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowgraph:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowgraph:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowgraph_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowgraph_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowgraph_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowGraph)
    library(jsonlite)

    # --- Feature Manipulation [] ---
    # Key functions: fg_get_feature_desc, fg_add_feature, fg_rm_feature
    mc <- fg_get_feature(fg, type = "node", feature = "count")
    fg <- fg_add_feature(
        fg,
        type = "node",
        feature = "count_copy",
        m = mc
    )
    feat_desc <- fg_get_feature_desc(fg)
    fg <- fg_rm_feature(fg, type = "node", feature = "count_copy")


    # --- Statistical Testing [] ---
    # Key functions: fg_summary, fg_get_summary_desc, fg_get_summary
    fg <- fg_summary(
        fg,
        no_cores = 1,
        class = "class",
        label1 = "control",
        node_features = "count",
        edge_features = "NONE",
        overwrite = FALSE,
        test_name = "t",
        diminish = FALSE
    )
    sum_desc <- fg_get_summary_desc(fg)
    fg_sum <- fg_get_summary(
        fg,
        type = "node",
        summary_meta = list(
            feature = "count",
            test_name = "t",
            class = "class",
            label1 = "control",
            label2 = "exp"
        )
    )


    # --- Visualisation [] ---
    # Key functions: fg_plot, plot_gr, fg_plot_qq, fg_plot_box
    gr <- fg_plot(fg, index = 1, p_thres = 0.01, show_bgedges = TRUE)
    plot_gr(gr, interactive = FALSE)
    fg_plot_qq(fg, type = "node", index = 1, logged = TRUE)
    fg_plot_box(
        fg,
        type = "node",
        summary_meta = NULL,
        index = 1,
        node_edge = "A+"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowgraph_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowgraph_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowgraph_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWGRAPH:", paste0("    flowgraph: ", packageVersion("flowGraph"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowgraph_results.csv
    touch ${prefix}_flowgraph_output.rds
    echo "BIOC_FLOWGRAPH:" > versions.yml
    echo "    flowgraph: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWGRAPH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWGRAPH(ch_input)

    emit:
    results  = BIOC_FLOWGRAPH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWGRAPH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWGRAPH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWGRAPH.out.versions  // channel: path(versions.yml)
}
