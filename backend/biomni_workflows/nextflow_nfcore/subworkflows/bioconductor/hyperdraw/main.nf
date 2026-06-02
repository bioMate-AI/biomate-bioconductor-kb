#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hyperdraw
// Functions for visualizing hypergraphs.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hyperdraw/inst/doc/hyperdraw.R
// Upstream  : none
// Downstream: BiGGR
//
// Install: BiocManager::install("hyperdraw")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HYPERDRAW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hyperdraw"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hyperdraw:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hyperdraw:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hyperdraw_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hyperdraw_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hyperdraw_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hyperdraw)
    library(DirectedHyperedge)
    library(Hypergraph)
    library(jsonlite)

    # --- Specific Element Customization [] ---
    # Key functions: edgeData, nodeData
    edgeData(testrabph, c("A", "R1"), c("R1", "B"), "lwd") <- c("5", "3")
    edgeData(testrabph, c("A", "R1"), c("R1", "B"), "color") <- "red"
    nodeData(testrabph, c("A", "B"), "color") <- "blue"


    # --- Hypergraph Rendering [] ---
    # Key functions: plot
    plot(testrabph)
    plot(testbph)
    plot(testgnel)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hyperdraw_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hyperdraw_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hyperdraw_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HYPERDRAW:", paste0("    hyperdraw: ", packageVersion("hyperdraw"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hyperdraw_results.csv
    touch ${prefix}_hyperdraw_output.rds
    echo "BIOC_HYPERDRAW:" > versions.yml
    echo "    hyperdraw: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HYPERDRAW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HYPERDRAW(ch_input)

    emit:
    results  = BIOC_HYPERDRAW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HYPERDRAW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HYPERDRAW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HYPERDRAW.out.versions  // channel: path(versions.yml)
}
