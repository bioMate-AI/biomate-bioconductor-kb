#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RCyjs
// Interactive viewing and exploration of graphs, connecting R to Cytoscape.js, using websockets.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RCyjs/inst/doc/RCyjs.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RCyjs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCYJS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcyjs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcyjs:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcyjs:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcyjs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcyjs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcyjs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RCyjs)
    library(jsonlite)

    # --- GraphNEL analysis [] ---
    # Key functions: graphNEL, addEdge, nodeDataDefaults, edgeDataDefaults, nodeData, edgeData, RCyjs, setGraph
    nodeData(g, nodes, attr="label") <- c("Activator", "Target")
    nodeData(g, nodes, attr="type") <- c("ligand", "receptor")
    edgeData(g, "A", "T", attr="edgeType") <- "binds"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcyjs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcyjs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcyjs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCYJS:", paste0("    rcyjs: ", packageVersion("RCyjs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcyjs_results.csv
    touch ${prefix}_rcyjs_output.rds
    echo "BIOC_RCYJS:" > versions.yml
    echo "    rcyjs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCYJS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCYJS(ch_input)

    emit:
    results  = BIOC_RCYJS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCYJS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCYJS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCYJS.out.versions  // channel: path(versions.yml)
}
