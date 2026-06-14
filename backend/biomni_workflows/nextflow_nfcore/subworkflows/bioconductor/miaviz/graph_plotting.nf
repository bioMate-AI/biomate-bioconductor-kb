#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — graph_plotting
// Plot sample or feature graphs integrated with metadata from a SummarizedExperiment.
// Input: col_graph, GlobalPatterns
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: ggplot2, mia, miaViz, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, miaViz, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load graph data
//  * 2. [Visualization & Output] Plot column graph mapping sample metadata to node colors and edge weights
//  * 3. [Visualization & Output] Store graph in metadata slot and plot

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_GRAPH_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ggplot2", "mia", "miaViz", "scater")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(miaViz)
    library(scater)
    library(mia)
    library(ggplot2)
    
    # 1. Load graph data and TreeSummarizedExperiment object from user input files
    col_graph <- readRDS("col_graph")
    GlobalPatterns <- readRDS("GlobalPatterns")
    
    # Ensure the "Genus" alternative experiment exists in GlobalPatterns
    if (!"Genus" %in% altExpNames(GlobalPatterns)) {
        altExp(GlobalPatterns, "Genus") <- agglomerateByRank(GlobalPatterns, "Genus")
    }
    
    # 2. Plot column graph mapping sample metadata to node colors and edge weights
    plot1 <- plotColGraph(
        col_graph,
        altExp(GlobalPatterns,"Genus"),
        colour.by = "SampleType",
        edge.colour.by = "weight",
        edge.width.by = "weight",
        show.label = TRUE)
    
    # Save the first plot
    ggsave("col_graph_plot_direct.pdf", plot = plot1, width = 10, height = 8)
    
    # 3. Store graph in metadata slot and plot
    metadata(altExp(GlobalPatterns,"Genus"))\$graph <- col_graph
    
    plot2 <- plotColGraph(
        altExp(GlobalPatterns,"Genus"),
        name = "graph",
        colour.by = "SampleType",
        edge.colour.by = "weight",
        edge.width.by = "weight",
        show.label = TRUE)
    
    # Save the second plot
    ggsave("col_graph_plot_metadata.pdf", plot = plot2, width = 10, height = 8)
    
    # Save the updated TreeSummarizedExperiment object with the graph in metadata
    saveRDS(GlobalPatterns, "GlobalPatterns_with_graph.rds")

    writeLines(c(
        '"BIOC_MIAVIZ_GRAPH_PLOTTING":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graph_plotting.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_GRAPH_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ col_graph, GlobalPatterns ] ]

    main:
    BIOC_MIAVIZ_GRAPH_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_GRAPH_PLOTTING.out.tables
    plots    = BIOC_MIAVIZ_GRAPH_PLOTTING.out.plots
    objects  = BIOC_MIAVIZ_GRAPH_PLOTTING.out.objects
    versions = BIOC_MIAVIZ_GRAPH_PLOTTING.out.versions
}
