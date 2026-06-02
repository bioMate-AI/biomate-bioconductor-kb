#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mosbi
// This package is a implementation of biclustering ensemble method MoSBi (Molecular signature Identifi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mosbi/inst/doc/example-workflow.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mosbi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosbi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosbi:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosbi:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosbi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosbi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosbi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mosbi)
    library(jsonlite)

    # --- Biclustering Ensemble Execution [Biclustering] ---
    # Key functions: run_fabia, run_isa, run_plaid, run_qubic, colhistogram
    fb <- mosbi::run_fabia(data_matrix)
    BCisa <- mosbi::run_isa(data_matrix)
    BCplaid <- mosbi::run_plaid(data_matrix)
    BCqubic <- mosbi::run_qubic(data_matrix)
    all_bics <- c(fb, BCisa, BCplaid, BCqubic)
    cols_hist <- mosbi::colhistogram(all_bics)
    rows_hist <- mosbi::rowhistogram(all_bics)

    # --- Bicluster Network Generation [Network Analysis] ---
    # Key functions: bicluster_network, get_adjacency
    bic_net <- mosbi::bicluster_network(
        all_bics,
        data_matrix,
        n_randomizations = 5,
        MARGIN = "both",
        metric = 4,
        n_steps = 1000,
        plot_edge_dist = FALSE
    )
    adj_matrix <- mosbi::get_adjacency(bic_net)

    # --- Network Visualization [Visualisation] ---
    # Key functions: plot_algo_network, plot_piechart_bicluster_network
    weeks <- vapply(
        strsplit(colnames(data_matrix), "\\."),
        function(x) x[1],
        ""
    )
    names(weeks) <- colnames(data_matrix)
    week_cols <- c("yellow", "orange", "red", "green", "brown")
    mosbi::plot_algo_network(bic_net, all_bics, vertex.label = NA)
    mosbi::plot_piechart_bicluster_network(
        bic_net, all_bics, weeks, week_cols, vertex.label = NA
    )

    # --- Community Detection and Ensemble Extraction [Ensemble Clustering] ---
    # Key functions: get_louvain_communities, ensemble_biclusters
    coms <- mosbi::get_louvain_communities(
        bic_net,
        min_size = 3,
        bics = all_bics
    )
    ensemble_bicluster_list <- mosbi::ensemble_biclusters(
        coms,
        all_bics,
        data_matrix,
        row_threshold = 0.1,
        col_threshold = 0.1
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosbi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosbi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosbi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSBI:", paste0("    mosbi: ", packageVersion("mosbi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosbi_results.csv
    touch ${prefix}_mosbi_output.rds
    echo "BIOC_MOSBI:" > versions.yml
    echo "    mosbi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSBI(ch_input)

    emit:
    results  = BIOC_MOSBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSBI.out.versions  // channel: path(versions.yml)
}
