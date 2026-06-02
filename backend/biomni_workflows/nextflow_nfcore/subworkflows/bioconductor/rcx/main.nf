#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RCX
// Create, handle, validate, visualize and convert networks in the Cytoscape exchange (CX) format to st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RCX/inst/doc/Creating_RCX_from_scratch.R
// Upstream  : base64enc
// Downstream: ndexr
//
// Install: BiocManager::install("RCX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcx:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcx:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RCX)
    library(jsonlite)

    # --- Network Edge Creation [] ---
    # Key functions: createEdges
    edges <- createEdges(
        source = c(1, 2, 3),
        target = c(0, 1, 1),
        interaction = c("aspectOf", "propertyOf", "propertyOf")
    )


    # --- RCX Object Assembly and Annotation [] ---
    # Key functions: createRCX, createNodeAttributes, updateNodeAttributes
    rcx <- createRCX(nodes = nodes, edges = edges)
    nodeAttributesType <- createNodeAttributes(
        propertyOf = nodes$id,
        name = rep("type", length(nodes$id)),
        value = rep("aspect", length(nodes$id))
    )
    rcx <- updateNodeAttributes(rcx, nodeAttributesType)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCX:", paste0("    rcx: ", packageVersion("RCX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcx_results.csv
    touch ${prefix}_rcx_output.rds
    echo "BIOC_RCX:" > versions.yml
    echo "    rcx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCX(ch_input)

    emit:
    results  = BIOC_RCX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCX.out.versions  // channel: path(versions.yml)
}
