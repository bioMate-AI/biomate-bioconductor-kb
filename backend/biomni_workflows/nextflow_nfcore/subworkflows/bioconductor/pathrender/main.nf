#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pathRender
// build graphs from pathway databases, render them by Rgraphviz.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pathRender/inst/doc/pathRender.R
// Upstream  : ALL, RColorBrewer, Rgraphviz, graph
// Downstream: none
//
// Install: BiocManager::install("pathRender")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHRENDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathrender"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathrender:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathrender:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathrender_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathrender_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathrender_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pathRender)
    library(jsonlite)

    # --- Do1 [] ---
    # Key functions: graphcMAP, nodes
    library(pathRender)
    plot(G1 <- graphcMAP("p53pathway"))
    G1
    nodes(G1)[1:5]
    # --- Do2 [] ---
    # Key functions: graphcMAP
    plot(G2 <- graphcMAP("raspathway"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathrender_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathrender_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathrender_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHRENDER:", paste0("    pathrender: ", packageVersion("pathRender"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathrender_results.csv
    touch ${prefix}_pathrender_output.rds
    echo "BIOC_PATHRENDER:" > versions.yml
    echo "    pathrender: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHRENDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHRENDER(ch_input)

    emit:
    results  = BIOC_PATHRENDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHRENDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHRENDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHRENDER.out.versions  // channel: path(versions.yml)
}
