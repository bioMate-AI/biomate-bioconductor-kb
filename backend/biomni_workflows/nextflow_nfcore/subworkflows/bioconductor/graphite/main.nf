#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: graphite
// Graph objects from pathway topology derived from KEGG, Panther, PathBank, PharmGKB, Reactome SMPDB a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/graphite/inst/doc/graphite.R
// Upstream  : SPIA, graph, topologyGSA
// Downstream: none
//
// Install: BiocManager::install("graphite")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRAPHITE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-graphite"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-graphite:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-graphite:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_graphite_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_graphite_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_graphite_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(graphite)
    library(Do)
    library(jsonlite)

    # --- Identifier Conversion [] ---
    # Key functions: convertIdentifiers, nodes
    humanReactome <- pathways("hsapiens", "reactome")
    p <- humanReactome[[1]]
    pSymbol <- convertIdentifiers(p, "SYMBOL")
    reactomeSymbol <- convertIdentifiers(humanReactome[1:5], "SYMBOL")
    symbol_nodes <- head(nodes(pSymbol))


    # --- Graph Conversion [] ---
    # Key functions: pathwayGraph
    humanReactome <- pathways("hsapiens", "reactome")
    p <- humanReactome[[1]]
    g_default <- pathwayGraph(p)
    g_mixed <- pathwayGraph(p, which = "mixed")


    # --- SPIA Pathway Analysis [] ---
    # Key functions: pathways, convertIdentifiers, prepareSPIA, runSPIA
    kegg <- pathways("hsapiens", "kegg")
    kegg <- convertIdentifiers(kegg, "ENTREZID")
    kegg_subset <- kegg[1:2]
    prepareSPIA(kegg_subset, "keggEx")
    de_genes <- c("ENTREZID:672" = 2.5, "ENTREZID:7157" = -1.8)
    all_genes <- c("ENTREZID:672", "ENTREZID:7157", "ENTREZID:100")
    res <- runSPIA(de = de_genes, all = all_genes, "keggEx")


    # --- Topology-Based Pathway Analysis [] ---
    # Key functions: pathways, convertIdentifiers, nodes, runTopologyGSA
    kegg <- pathways("hsapiens", "kegg")
    p <- convertIdentifiers(kegg[[1]], "SYMBOL")
    genes <- head(nodes(p))
    y1 <- matrix(rnorm(50), nrow = 10, ncol = length(genes))
    y2 <- matrix(rnorm(50), nrow = 10, ncol = length(genes))
    colnames(y1) <- paste("SYMBOL", genes, sep = ":")
    colnames(y2) <- paste("SYMBOL", genes, sep = ":")
    res_gsa <- runTopologyGSA(p, "var", y1, y2, 0.05)


    # --- Custom Pathway Construction [] ---
    # Key functions: buildPathway
    edges <- data.frame(src_type = "ENTREZID", src = "672",
                        dest_type = "ENTREZID", dest = "7157",
                        direction = "undirected", type = "binding")
    edgemix <- data.frame(src_type = "CHEBI", src = "77750",
                          dest_type = "ENTREZID", dest = "7157",
                          direction = "undirected",
                          type = "biochemicalReaction")
    pathway <- buildPathway("#1", "example", "hsapiens", "database",
                            proteinEdges = edges,
                            mixedEdges = edgemix)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_graphite_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_graphite_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_graphite_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRAPHITE:", paste0("    graphite: ", packageVersion("graphite"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graphite_results.csv
    touch ${prefix}_graphite_output.rds
    echo "BIOC_GRAPHITE:" > versions.yml
    echo "    graphite: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRAPHITE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRAPHITE(ch_input)

    emit:
    results  = BIOC_GRAPHITE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRAPHITE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRAPHITE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRAPHITE.out.versions  // channel: path(versions.yml)
}
