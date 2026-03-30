#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ROntoTools
// Suite of tools for functional analysis.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ROntoTools/inst/doc/rontotools.R
// Upstream  : graph
// Downstream: BLMA
//
// Install: BiocManager::install("ROntoTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RONTOTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rontotools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rontotools:2.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rontotools:2.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rontotools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rontotools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rontotools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Summary)
    library(jsonlite)

    # --- Keggpathwaygraphs [] ---
    # Key functions: keggPathwayGraphs
    require(graph)
    require(ROntoTools)
    kpg <- keggPathwayGraphs("hsa", verbose = FALSE)
    # --- Head [] ---
    # Key functions: nodes, edges
    kpg[["path:hsa04110"]]
    head(nodes(kpg[["path:hsa04110"]]))
    head(edges(kpg[["path:hsa04110"]]))
    # --- Head [] ---
    # Key functions: edgeData
    head(edgeData(kpg[["path:hsa04110"]], attr = "subtype"))
    # --- Setedgeweights [] ---
    # Key functions: setEdgeWeights
    kpg <- setEdgeWeights(kpg, edgeTypeAttr = "subtype",
    	edgeWeightByType = list(activation = 1, inhibition = -1,
    		expression = 1, repression = -1),
    	defaultWeight = 0)
    # --- Head [] ---
    # Key functions: edgeData
    head(edgeData(kpg[["path:hsa04110"]], attr = "weight"))
    # --- Keggpathwaynames [] ---
    # Key functions: keggPathwayNames
    kpn <- keggPathwayNames("hsa")
    head(kpn)
    # --- Setnodeweights [] ---
    # Key functions: setNodeWeights, alphaMLG, nodeWeights
    kpg <- setNodeWeights(kpg, weights = alphaMLG(pv), defaultWeight = 1)
    head(nodeWeights(kpg[["path:hsa04110"]]))
    # --- Pe [] ---
    # Key functions: pe
    peRes <- pe(x = fc, graphs = kpg, ref = ref,  nboot = 200, verbose = FALSE)
    # --- Head [] ---
    # Key functions: Summary
    head(Summary(peRes))
    head(Summary(peRes, pathNames = kpn, totalAcc = FALSE, totalPert = FALSE,
                 pAcc = FALSE, pORA = FALSE, comb.pv = NULL, order.by = "pPert"))
    # --- Pepathway Graph Pert [] ---
    # Key functions: layoutGraph, graphRenderInfo, edgeRenderInfo, peEdgeRenderInfo, nodeRenderInfo, peNodeRenderInfo, renderGraph
    p <- peRes@pathways[["path:hsa05216"]]
    g <- layoutGraph(p@map, layoutType = "dot")
    graphRenderInfo(g) <- list(fixedsize = FALSE)
    edgeRenderInfo(g) <- peEdgeRenderInfo(p)
    nodeRenderInfo(g) <- peNodeRenderInfo(p)
    # --- Pepathway Graph Pert2 [] ---
    # Key functions: layoutGraph, graphRenderInfo, edgeRenderInfo, peEdgeRenderInfo, nodeRenderInfo, peNodeRenderInfo, renderGraph
    p <- peRes@pathways[["path:hsa04660"]]
    g <- layoutGraph(p@map, layoutType = "dot")
    graphRenderInfo(g) <- list(fixedsize = FALSE)
    edgeRenderInfo(g) <- peEdgeRenderInfo(p)
    nodeRenderInfo(g) <- peNodeRenderInfo(p)
    # --- Fig5 [] ---
    # Key functions: layoutGraph, graphRenderInfo, edgeRenderInfo, peEdgeRenderInfo, nodeRenderInfo, peNodeRenderInfo, renderGraph
    p <- peRes@pathways[["path:hsa05216"]]
    g <- layoutGraph(p@map, layoutType = "dot")
    graphRenderInfo(g) <- list(fixedsize = FALSE)
    edgeRenderInfo(g) <- peEdgeRenderInfo(p)
    nodeRenderInfo(g) <- peNodeRenderInfo(p)
    # --- Fig6 [] ---
    # Key functions: layoutGraph, graphRenderInfo, edgeRenderInfo, peEdgeRenderInfo, nodeRenderInfo, peNodeRenderInfo, renderGraph
    p <- peRes@pathways[["path:hsa04660"]]
    g <- layoutGraph(p@map, layoutType = "dot")
    graphRenderInfo(g) <- list(fixedsize = FALSE)
    edgeRenderInfo(g) <- peEdgeRenderInfo(p)
    nodeRenderInfo(g) <- peNodeRenderInfo(p)
    # --- Keggpathwaygraphs [] ---
    # Key functions: keggPathwayGraphs
    require(graph)
    require(ROntoTools)
    kpg <- keggPathwayGraphs("hsa", verbose = FALSE)
    # --- Keggpathwaynames [] ---
    # Key functions: keggPathwayNames
    kpn <- keggPathwayNames("hsa")
    head(kpn)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rontotools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rontotools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rontotools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RONTOTOOLS:", paste0("    rontotools: ", packageVersion("ROntoTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rontotools_results.csv
    touch ${prefix}_rontotools_output.rds
    echo "BIOC_RONTOTOOLS:" > versions.yml
    echo "    rontotools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RONTOTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RONTOTOOLS(ch_input)

    emit:
    results  = BIOC_RONTOTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RONTOTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RONTOTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RONTOTOOLS.out.versions  // channel: path(versions.yml)
}
