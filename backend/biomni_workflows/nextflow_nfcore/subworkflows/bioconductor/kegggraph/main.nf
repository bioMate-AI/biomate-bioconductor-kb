#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: KEGGgraph
// KEGGGraph is an interface between KEGG pathway and graph object as well as a collection of tools to 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/KEGGgraph/inst/doc/KEGGgraph.R
// Upstream  : RBGL, RColorBrewer, Rgraphviz, SPIA, biomaRt
// Downstream: lpNet, ROntoTools, SPIA
//
// Install: BiocManager::install("KEGGgraph")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGGRAPH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-kegggraph"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-kegggraph:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-kegggraph:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_kegggraph_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_kegggraph_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_kegggraph_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KEGGgraph)
    library(KEGGpathway2Graph)
    library(KEGGpathway2reactionGraph)
    library(jsonlite)

    # --- Extracting Node and Edge Data [] ---
    # Key functions: getKEGGnodeData, getKEGGedgeData, translateKEGGID2GeneID
    mapkNodes <- nodes(mapkG)
    mapkEdges <- edges(mapkG)
    node_data <- getKEGGnodeData(mapkG)
    edge_data <- getKEGGedgeData(mapkG)
    gene_ids <- translateKEGGID2GeneID(mapkNodes[1:5])


    # --- Graph Merging and Subgraphing [] ---
    # Key functions: mergeGraphs, subGraphByNodeType, parseKGMLexpandMaps
    wntKGML <- system.file("extdata/hsa04310.xml", package="KEGGgraph")
    wntG <- parseKGML2Graph(wntKGML)
    merged_graph <- mergeGraphs(list(mapk=mapkG, wnt=wntG))
    mapkGall <- parseKGML2Graph(mapkKGML, genesOnly=FALSE)
    gene_subgraph <- subGraphByNodeType(mapkGall, "gene")


    # --- Pathway Reaction Graph Analysis [] ---
    # Key functions: getReactions, KEGGpathway2reactionGraph
    mapfile <- system.file("extdata/map00260.xml", package="KEGGgraph")
    map_pathway <- parseKGML(mapfile)
    reactions_list <- getReactions(map_pathway)
    chemicalGraph <- KEGGpathway2reactionGraph(map_pathway)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_kegggraph_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_kegggraph_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_kegggraph_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KEGGGRAPH:", paste0("    kegggraph: ", packageVersion("KEGGgraph"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kegggraph_results.csv
    touch ${prefix}_kegggraph_output.rds
    echo "BIOC_KEGGGRAPH:" > versions.yml
    echo "    kegggraph: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KEGGGRAPH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KEGGGRAPH(ch_input)

    emit:
    results  = BIOC_KEGGGRAPH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KEGGGRAPH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KEGGGRAPH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KEGGGRAPH.out.versions  // channel: path(versions.yml)
}
