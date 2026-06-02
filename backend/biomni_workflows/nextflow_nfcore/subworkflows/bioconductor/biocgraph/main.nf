#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biocGraph
// This package provides examples and code that make use of the different graph related packages produc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biocGraph/inst/doc/biocGraph.R
// Upstream  : fibroEset, geneplotter, graph
// Downstream: none
//
// Install: BiocManager::install("biocGraph")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCGRAPH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocgraph"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocgraph:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocgraph:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocgraph_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocgraph_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocgraph_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biocGraph)
    library(jsonlite)

    # --- Creategraph2 [] ---
    # Key functions: randomGraph
    g1 <- randomGraph(V, M, 0.2)
    # --- Reg [] ---
    # Key functions: new, addEdge
    rEG <- new("graphNEL", nodes=c("A", "B"), edgemode="directed")
    rEG <- addEdge("A", "B", rEG, 1)
    rEG <- addEdge("B", "A", rEG, 1)
    # --- Getsubgraphs [] ---
    # Key functions: subGraph
    sg1 <- subGraph(c("a","d","j","i"), g1)
    sg1
    sg2 <- subGraph(c("b","e","h"), g1)
    sg3 <- subGraph(c("c","f","g"), g1)
    # --- Subgplot2 [] ---
    # Key functions: subGraph
    sg1 <- subGraph(c("a","c","d","e","j"), g1)
    sg2 <- subGraph(c("f","h","i"), g1)
    plot(g1, subGList=list(list(graph=sg1), list(graph=sg2)))
    # --- Edgenames [] ---
    # Key functions: edgeNames
    edgeNames(g1)
    edgeNames(g1, recipEdges="distinct")
    # --- Defattrs [] ---
    # Key functions: getDefaultAttrs
    defAttrs <- getDefaultAttrs()
    # --- Makelabels1 [] ---
    # Key functions: packageDescription, numNodes, nodes
    z <- strsplit(packageDescription("Rgraphviz")$Description, " ")[[1]]
    z <- z[1:numNodes(g1)]
    names(z) = nodes(g1)
    nAttrs$label <- z
    # --- Edgeweights [] ---
    # Key functions: unlist, edgeWeights, setdiff, removedEdges, edgeNames
    ew <- as.character(unlist(edgeWeights(g1)))
    ew <- ew[setdiff(seq(along=ew), removedEdges(g1))]
    names(ew) <- edgeNames(g1)
    eAttrs$label <- ew
    ## FIXME (wh 17.6.06): This does not work - see bug report:
    # --- Getlists1 [] ---
    # Key functions: buildNodeList, buildEdgeList
    nodes <- buildNodeList(g1)
    edges <- buildEdgeList(g1)
    # --- Buildwithattrs [] ---
    # Key functions: buildNodeList, buildEdgeList
    nodes <- buildNodeList(g1, nodeAttrs=nAttrs, defAttrs=defAttrs$node)
    edges <- buildEdgeList(g1, edgeAttrs=eAttrs, defAttrs=defAttrs$edge)
    nodes[[1]]
    edges[[1]]
    # --- Plotbuild [] ---
    # Key functions: agopen
    vv <- agopen(name="foo", nodes=nodes, edges=edges, attrs=attrs,
      edgeMode="undirected")
    plot(vv)
    # --- Graph17 [] ---
    # Key functions: nodes
    data(graphExamples)
    z <- graphExamples[[8]]
    nNodes <- length(nodes(z))
    nA <- list()
    nA$fixedSize<-rep(FALSE, nNodes)
    # --- Piechartcalc [] ---
    # Key functions: rexp, numNodes, agopen, force, getNodeCenter
    set.seed(123)
    counts = matrix(rexp(numNodes(g1)*4), ncol=4)
    g1layout <- agopen(g1, name="foo")
    # --- Bipartite1 [] ---
    # Key functions: sample, ftM2graphNEL
    set.seed(123)
    nodes1 <- paste(0:7)
    nodes2 <- letters[1:10]
    ft <- cbind(sample(nodes1, 24, replace=TRUE),
                sample(nodes2, 24, replace=TRUE))
    # --- Bipartitelayout [] ---
    # Key functions: nodes, makeNodeAttrs, subGraph
    twocolors <- c("#D9EF8B", "#E0F3F8")
    nodeType <- 1 + (nodes(g) %in% nodes1)
    nA = makeNodeAttrs(g, fillcolor=twocolors[nodeType])
    sg1 = subGraph(nodes1, g)
    sgL = list(list(graph=sg1, cluster = FALSE, attrs = c(rank="sink")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocgraph_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocgraph_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocgraph_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCGRAPH:", paste0("    biocgraph: ", packageVersion("biocGraph"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocgraph_results.csv
    touch ${prefix}_biocgraph_output.rds
    echo "BIOC_BIOCGRAPH:" > versions.yml
    echo "    biocgraph: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCGRAPH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCGRAPH(ch_input)

    emit:
    results  = BIOC_BIOCGRAPH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCGRAPH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCGRAPH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCGRAPH.out.versions  // channel: path(versions.yml)
}
