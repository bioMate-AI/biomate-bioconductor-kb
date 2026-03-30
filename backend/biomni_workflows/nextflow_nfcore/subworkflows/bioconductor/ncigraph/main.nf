#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NCIgraph
// Provides various methods to load the pathways from the NCI Pathways Database in R graph objects and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NCIgraph/inst/doc/NCIgraph.R
// Upstream  : Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("NCIgraph")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NCIGRAPH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ncigraph"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ncigraph:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ncigraph:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ncigraph_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ncigraph_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ncigraph_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NCIgraph)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data("NCIgraphVignette", package="NCIgraph")
    # --- Data [] ---
    # Key functions: getNCIPathways
    grList <- getNCIPathways(cyList=NCI.demo.cyList, parseNetworks=TRUE, entrezOnly=TRUE, verbose=TRUE)$pList
    # --- Plotraw [] ---
    # Key functions: unlist, nodes, layoutGraph, nodeRenderInfo
    graph <- NCI.demo.cyList[[1]]
    gNames <- unlist(lapply(graph@nodeData@data,FUN=function(e) e$biopax.name))
    names(gNames) <- nodes(graph)
    graph <- layoutGraph(graph)
    nodeRenderInfo(graph) <- list(label=gNames, cex=0.75)
    # --- Plotparsed [] ---
    # Key functions: unlist, nodes, layoutGraph, nodeRenderInfo
    graph <- grList[[1]]
    gNames <- unlist(lapply(graph@nodeData@data,FUN=function(e) unique(e$biopax.xref.ENTREZGENE)))
    names(gNames) <- nodes(graph)
    graph <- layoutGraph(graph)
    nodeRenderInfo(graph) <- list(label=gNames, cex=0.75)
    # --- Rawgraph [] ---
    # Key functions: unlist, nodes, layoutGraph, nodeRenderInfo
    graph <- NCI.demo.cyList[[1]]
    gNames <- unlist(lapply(graph@nodeData@data,FUN=function(e) e$biopax.name))
    names(gNames) <- nodes(graph)
    graph <- layoutGraph(graph)
    nodeRenderInfo(graph) <- list(label=gNames, cex=0.75)
    # --- Parsedgraph [] ---
    # Key functions: unlist, nodes, layoutGraph, nodeRenderInfo
    graph <- grList[[1]]
    gNames <- unlist(lapply(graph@nodeData@data,FUN=function(e) unique(e$biopax.xref.ENTREZGENE)))
    names(gNames) <- nodes(graph)
    graph <- layoutGraph(graph)
    nodeRenderInfo(graph) <- list(label=gNames, cex=0.75)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ncigraph_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ncigraph_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ncigraph_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NCIGRAPH:", paste0("    ncigraph: ", packageVersion("NCIgraph"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ncigraph_results.csv
    touch ${prefix}_ncigraph_output.rds
    echo "BIOC_NCIGRAPH:" > versions.yml
    echo "    ncigraph: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NCIGRAPH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NCIGRAPH(ch_input)

    emit:
    results  = BIOC_NCIGRAPH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NCIGRAPH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NCIGRAPH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NCIGRAPH.out.versions  // channel: path(versions.yml)
}
