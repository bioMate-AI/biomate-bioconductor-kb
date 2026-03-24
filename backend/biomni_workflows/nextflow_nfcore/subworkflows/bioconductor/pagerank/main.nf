#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pageRank
// Implemented temporal PageRank analysis as defined by Rozenshtein and Gionis. Implemented multiplex P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pageRank/inst/doc/introduction.R
// Upstream  : GenomicFeatures, GenomicRanges, JASPAR2018, TFBSTools, annotate
// Downstream: none
//
// Install: BiocManager::install("pageRank")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAGERANK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pagerank"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pagerank:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pagerank:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pagerank_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pagerank_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pagerank_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(P_graph)
    library(V)
    library(jsonlite)

    # --- Tpr [] ---
    # Key functions: game, V, diff_graph
    library(pageRank)
    set.seed(1)
    graph1 <- igraph::erdos.renyi.game(100, 0.01, directed = TRUE)
    igraph::V(graph1)$name <- 1:100
    #the 1st graph with name as vertex attributes
    # --- Mpr [] ---
    # Key functions: game, V, page_rank, multiplex_page_rank
    set.seed(1)
    graph1 <- igraph::erdos.renyi.game(100, 0.01, directed = TRUE)
    igraph::V(graph1)$name <- 1:100
    igraph::V(graph1)$pagerank <- igraph::page_rank(graph1)$vector
    #the base graph with pagerank and name as vertex attributes.
    # --- Clean Graph [] ---
    # Key functions: game, V, page_rank, clean_graph
    set.seed(1)
    graph <- igraph::erdos.renyi.game(100, 0.01, directed = TRUE)
    igraph::V(graph)$name <- 1:100
    igraph::V(graph)$pagerank <- igraph::page_rank(graph)$vector
    #the graph to be cleaned, with pagerank and name as vertex attributes.
    # --- Adjust Graph [] ---
    # Key functions: game, V, page_rank, adjust_graph
    set.seed(1)
    graph <- igraph::erdos.renyi.game(100, 0.01, directed = TRUE)
    igraph::V(graph)$name <- 1:100
    igraph::V(graph)$pagerank <- igraph::page_rank(graph, damping=0.85)$vector
    #the graph to be adjusted, with pagerank and name as vertex attributes.
    # --- Aracne Network [] ---
    # Key functions: aracne_network
    library(bcellViper)
    data(bcellViper)
    head(aracne_network(regulon[1:10]))
    # --- Accessibility Network [] ---
    # Key functions: frame, promoters, genes, getSYMBOL, na
    table <- data.frame(Chr=c("chr1", "chr1"), Start=c(713689, 856337), End=c(714685, 862152),
                        row.names=c("A", "B"), stringsAsFactors=FALSE)
    regulators=c("FOXF2", "MZF1")
    #peaks and regulators to be analyzed
    library(GenomicRanges)
    # --- Conformation Network [] ---
    # Key functions: frame, promoters, genes, getSYMBOL, na, getMatrixSet
    table <- data.frame(Chr1=c("chr1", "chr1"), Position1=c(569265, 713603), Strand1=c("+", "+"),
                        Chr2=c("chr4", "chr1"), Position2=c(206628, 715110), Strand2=c("+", "-"),
                        row.names=c("A", "B"), stringsAsFactors=FALSE)
    regulators=c("FOXF2", "MZF1")
    #peaks and regulators to be analyzed
    # --- P Graph [] ---
    # Key functions: exprs, call, frame, P_graph
    dset <- exprs(dset)
    net <- do.call(rbind, lapply(1:10, function(i, regulon){
      data.frame(reg=rep(names(regulon)[i], 10),
                 target=names(regulon[[i]][[1]])[1:10],
                 stringsAsFactors = FALSE)}, regulon=regulon))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pagerank_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pagerank_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pagerank_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAGERANK:", paste0("    pagerank: ", packageVersion("pageRank"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pagerank_results.csv
    touch ${prefix}_pagerank_output.rds
    echo "BIOC_PAGERANK:" > versions.yml
    echo "    pagerank: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAGERANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAGERANK(ch_input)

    emit:
    results  = BIOC_PAGERANK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAGERANK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAGERANK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAGERANK.out.versions  // channel: path(versions.yml)
}
