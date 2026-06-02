#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RGraph2js
// Generator of web pages which display interactive network/graph visualizations with D3js, jQuery and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RGraph2js/inst/doc/RGraph2js.R
// Upstream  : graph, sna, xtable
// Downstream: none
//
// Install: BiocManager::install("RGraph2js")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGRAPH2JS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgraph2js"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgraph2js:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgraph2js:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgraph2js_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgraph2js_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgraph2js_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RGraph2js)
    library(jsonlite)

    # --- Tab1 [] ---
    # Key functions: xtable
    library(xtable)
    # --- Tab2 [] ---
    # Key functions: xtable
    library(xtable)
    # --- <Simpleexample [] ---
    # Key functions: path, tempdir, graph2js
    outputDir <- file.path(tempdir(), "RGraph2js_simpleExample")
    g <- graph2js(a1515, outputDir=outputDir)
    # --- Visualappearanceexample [] ---
    # Key functions: frame
    edgesGlobal <- list(width=2, color="#0000ff")
    edgesProp <- data.frame(from=c("D", "D", "B"),
                            to=c("E", "B", "E"),
                            width=c(5, 5, 5))
    # --- Visualappearanceexample [] ---
    # Key functions: getEdgesDataFrame
    getEdgesDataFrame(a1515)
    # --- Visualappearanceexample [] ---
    # Key functions: frame
    nodesGlobal <- list(color="#ebebeb")
    nodesProp <- data.frame(shape=c("triangle", "lozenge", "rect"),
                            color=c("#ff0000", "#0000ff", "#ffff00"))
    rownames(nodesProp) <- c("C", "E", "G")
    # --- Visualappearanceexample [] ---
    # Key functions: getNodesDataFrame
    getNodesDataFrame(A=a1515, nGlobal=nodesGlobal, nProp=nodesProp)
    # --- <Visualappearanceexample [] ---
    # Key functions: path, tempdir, graph2js
    outputDir <- file.path(tempdir(), "RGraph2js_visualAppearance")
    g <- graph2js(a1515,
                  nodesGlobal=nodesGlobal, edgesGlobal=edgesGlobal,
                  nodesProp=nodesProp, edgesProp=edgesProp,
                  outputDir=outputDir, file="index.html")
    # --- Fixednodes2 [] ---
    # Key functions: frame, cos, sin
    r <- 100
    sector <- 2*pi/5
    # --- Fixednodes3 [] ---
    # Key functions: path, tempdir, graph2js
    outputDir <- file.path(tempdir(), "RGraph2js_fixedNodes")
    g <- graph2js(a35, nodesProp=n.prop, outputDir=outputDir)
    # --- Categories2 [] ---
    # Key functions: frame, rbinom, rainbow
    numnodes <- 5
    # --- Categories3 [] ---
    # Key functions: path, tempdir, graph2js
    outputDir <- file.path(tempdir(), "RGraph2js_timeData")
    g <- graph2js(a35,
                  nodesProp=nodesProp,
                  outputDir=outputDir)
    # --- Barplot2 [] ---
    # Key functions: runif, rainbow
    numnodes <- 5
    innerValues <- matrix(runif(numnodes * 8), numnodes, 8)
    rownames(innerValues) <- LETTERS[1:5]
    innerColors <- matrix(rainbow(numnodes * 8), numnodes, 8)
    rownames(innerColors) <- LETTERS[1:5]
    # --- Barplot3 [] ---
    # Key functions: path, tempdir, graph2js
    outputDir <- file.path(tempdir(), "RGraph2js_barplots")
    g <- graph2js(a35,
                  innerValues=innerValues,
                  innerColors=innerColors,
                  outputDir=outputDir)
    # --- Barplots4 [] ---
    # Key functions: getDefaultOptions, graph2js
    opts <- getDefaultOptions()
    opts$displayBarPlotsInsideNodes <- FALSE
    opts$barplotInNodeTooltips <- TRUE

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgraph2js_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgraph2js_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgraph2js_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGRAPH2JS:", paste0("    rgraph2js: ", packageVersion("RGraph2js"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgraph2js_results.csv
    touch ${prefix}_rgraph2js_output.rds
    echo "BIOC_RGRAPH2JS:" > versions.yml
    echo "    rgraph2js: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGRAPH2JS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGRAPH2JS(ch_input)

    emit:
    results  = BIOC_RGRAPH2JS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGRAPH2JS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGRAPH2JS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGRAPH2JS.out.versions  // channel: path(versions.yml)
}
