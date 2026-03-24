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
    library(KEGGpathway2Graph)
    library(KEGGpathway2reactionGraph)
    library(jsonlite)

    # --- Remoteretrieval [] ---
    # Key functions: tempfile, retrieveKGML
    tmp <- tempfile()
    retrieveKGML("04115", organism="mcf", destfile=tmp, method="auto", quiet=TRUE)
    # --- Parsemapk [] ---
    # Key functions: parseKGML2Graph
    mapkG <- parseKGML2Graph(mapkKGML,expandGenes=TRUE)
    mapkG
    # --- Parsemapk2 [] ---
    # Key functions: parseKGML, KEGGpathway2Graph
    mapkpathway <- parseKGML(mapkKGML)
    mapkpathway
    mapkG2 <- KEGGpathway2Graph(mapkpathway, expandGenes=TRUE)
    mapkG2
    # --- Nodeandedge [] ---
    # Key functions: nodes, edges
    mapkNodes <- nodes(mapkG)
    nodes(mapkG)[1:3]
    mapkEdges <- edges(mapkG)
    edges(mapkG)[1]
    # --- Keggnodedata [] ---
    # Key functions: getKEGGnodeData
    mapkGnodedata <- getKEGGnodeData(mapkG)
    mapkGnodedata[[2]]
    # --- Keggnodedataalt [] ---
    # Key functions: getKEGGnodeData
    getKEGGnodeData(mapkG, 'hsa:5924')
    # --- Keggedgedata [] ---
    # Key functions: getKEGGedgeData
    mapkGedgedata <- getKEGGedgeData(mapkG)
    mapkGedgedata[[4]]
    # --- Keggedgedataalt [] ---
    # Key functions: getKEGGedgeData
    getKEGGedgeData(mapkG,'hsa:627~hsa:4915')
    # --- Inout [] ---
    # Key functions: edges, inEdges
    mapkGoutdegrees <- sapply(edges(mapkG), length)
    mapkGindegrees <- sapply(inEdges(mapkG), length)
    topouts <- sort(mapkGoutdegrees, decreasing=T)
    topins <- sort(mapkGindegrees, decreasing=T)
    topouts[1:3]
    # --- Subsetprepare [] ---
    # Key functions: sample, nodes, subGraph
    library(Rgraphviz)
    set.seed(123)
    randomNodes <- sample(nodes(mapkG), 25)
    mapkGsub <- subGraph(randomNodes, mapkG)
    mapkGsub
    # --- Makeattr [] ---
    # Key functions: nodes, missing
    makeAttr <- function(graph, default, valNodeList) {
      tmp <- nodes(graph)
      x <- rep(default, length(tmp)); names(x) <- tmp
      if(!missing(valNodeList)) {
        stopifnot(is.list(valNodeList))
    # --- Subsetplot [] ---
    # Key functions: edges, inEdges, translateKEGGID2GeneID, mget
    outs <- sapply(edges(mapkGsub), length) > 0
    ins <- sapply(inEdges(mapkGsub), length) > 0
    ios <- outs | ins
    ## translate the KEGG IDs into Gene Symbol
    if(require(org.Hs.eg.db)) {
    # --- Mergedemo [] ---
    # Key functions: parseKGML2Graph, mergeGraphs
    wntKGML <- system.file("extdata/hsa04310.xml",package="KEGGgraph")
    wntG <- parseKGML2Graph(wntKGML)
    graphs <- list(mapk=mapkG, wnt=wntG)
    merged <- mergeGraphs(graphs)
    merged
    # --- Bcc [] ---
    # Key functions: centrality
    library(RBGL)
    bcc <- brandes.betweenness.centrality(mapkG)
    rbccs <- bcc$relative.betweenness.centrality.vertices[1L,]
    toprbccs <- sort(rbccs,decreasing=TRUE)[1:4]
    toprbccs
    # --- Bccplot [] ---
    # Key functions: inEdges, edges, unname
    toprbccName <- names(toprbccs)
    toprin <- sapply(toprbccName, function(x) inEdges(mapkG)[x])
    toprout <- sapply(toprbccName, function(x) edges(mapkG)[x])
    toprSubnodes <- unique(unname(c(unlist(toprin), unlist(toprout), toprbccName)))
    toprSub <- subGraph(toprSubnodes, mapkG)

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
