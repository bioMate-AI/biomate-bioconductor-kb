#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetNet
// MetNet contains functionality to infer metabolic network topologies from quantitative data and high-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetNet/inst/doc/MetNet.R
// Upstream  : MsCoreUtils, Spectra, knitr
// Downstream: none
//
// Install: BiocManager::install("MetNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metnet:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metnet:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetNet)
    library(jsonlite)

    # --- Assay data access [] ---
    # Key functions: rbind, structural, graph_from_adjacency_matrix, assay, rtCorrection, mz_summary, mz_vis, compareSpectra
    adj <- assay(comb_adj, "combine_binary")
    g <- igraph::graph_from_adjacency_matrix(adj, mode = "undirected")
    plot(g, edge.width = 2, vertex.label.cex = 0.5, edge.color = "grey")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METNET:", paste0("    metnet: ", packageVersion("MetNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metnet_results.csv
    touch ${prefix}_metnet_output.rds
    echo "BIOC_METNET:" > versions.yml
    echo "    metnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METNET(ch_input)

    emit:
    results  = BIOC_METNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METNET.out.versions  // channel: path(versions.yml)
}
