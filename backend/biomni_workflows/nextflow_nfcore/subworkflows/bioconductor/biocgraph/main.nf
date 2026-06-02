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

    # --- Graph Construction and Manipulation ---
    # Key functions: randomGraph, subGraph, addEdge, removedEdges, edgeNames
    V <- letters[1:10]
    M <- 1:4
    g1 <- randomGraph(V, M, 0.2)
    sg1 <- subGraph(c("a", "d", "j", "i"), g1)
    sg2 <- subGraph(c("b", "e", "h"), g1)
    rEG <- new("graphNEL", nodes = c("A", "B"), edgemode = "directed")
    rEG <- addEdge("A", "B", rEG, 1)
    rEG <- addEdge("B", "A", rEG, 1)
    edges_removed <- removedEdges(g1)
    all_edges <- edgeNames(g1)

    # --- Attribute Customization ---
    # Key functions: getDefaultAttrs, edgeWeights, edgeNames, removedEdges
    defAttrs <- getDefaultAttrs()
    nAttrs <- list()
    eAttrs <- list()
    nAttrs$color <- c(a = "red", b = "red", g = "green", d = "blue")
    eAttrs$color <- c("a~d" = "blue", "c~h" = "purple")
    nAttrs$fillcolor <- c(j = "yellow")
    attrs <- list(node = list(shape = "ellipse", fixedsize = FALSE))
    ew <- as.character(unlist(edgeWeights(g1)))
    ew <- ew[setdiff(seq(along = ew), removedEdges(g1))]
    names(ew) <- edgeNames(g1)
    eAttrs$label <- ew

    # --- Layout and Rendering ---
    # Key functions: agopenSimple, graphDataDefaults, nodeDataDefaults, edgeDataDefaults
    sgl <- vector(mode = "list", length = 2)
    sgl[[1]] <- list(graph = sg1, cluster = FALSE)
    sgl[[2]] <- list(graph = sg2, cluster = TRUE)
    ng <- agopenSimple(g1, "tmpsg", subGList = sgl)
    graphDataDefaults(ng, c("size", "bgcolor")) <- c("1", "yellow")
    nodeDataDefaults(ng, c("fontcolor", "width")) <- c("blue", 0.5)
    edgeDataDefaults(ng, c("color", "style")) <- c("green", "dotted")
    plot(ng)

    # --- Advanced Visualization with Custom Glyphs ---
    # Key functions: agopen, getNodeCenter, pieGlyph, getX, getY
    counts <- matrix(rexp(numNodes(g1) * 4), ncol = 4)
    g1layout <- agopen(g1, name = "foo")
    makeNodeDrawFunction <- function(x) {
        force(x)
        function(node, ur, attrs, radConv) {
            nc <- getNodeCenter(node)
            pieGlyph(x, xpos = getX(nc), ypos = getY(nc),
                     radius = getNodeRW(node), col = rainbow(4))
        }
    }
    drawFuns <- apply(counts, 1, makeNodeDrawFunction)
    plot(g1layout, drawNode = drawFuns, main = "Example Pie Chart Plot")


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
