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
    library(Do)
    library(jsonlite)

    # --- Base1 [] ---
    # Key functions: pathways
    humanReactome <- pathways("hsapiens", "reactome")
    names(humanReactome)[1:10]
    p <- humanReactome[["ABC-family proteins mediated transport"]]
    p
    # --- Base2 [] ---
    # Key functions: pathwayTitle
    p <- humanReactome[[21]]
    pathwayTitle(p)
    # --- Base5 [] ---
    # Key functions: nodes, edges
    head(nodes(p), which = "mixed")
    head(edges(p), which = "mixed")
    # --- Graph1 [] ---
    # Key functions: pathwayGraph
    g <- pathwayGraph(p)
    g
    # --- Graph3 [] ---
    # Key functions: pathwayGraph
    g <- pathwayGraph(p, which = "mixed")
    g
    # --- Ident1 [] ---
    # Key functions: convertIdentifiers, nodes
    pSymbol <- convertIdentifiers(p, "SYMBOL")
    pSymbol
    head(nodes(pSymbol))
    # --- Ident2 [] ---
    # Key functions: convertIdentifiers
    reactomeSymbol <- convertIdentifiers(humanReactome[1:5], "SYMBOL")
    # --- Spia1 [] ---
    # Key functions: mapIds, na, pathways
    library(SPIA)
    data(colorectalcancer)
    library(hgu133plus2.db)
    top$ENTREZ <- mapIds(hgu133plus2.db,
                         top$ID, "ENTREZID", "PROBEID", multiVals = "first")
    # --- Unlink [] ---
    # Key functions: unlink
    unlink("keggExSPIA.RData")
    # --- Tg1 [] ---
    # Key functions: pathways, convertIdentifiers, runTopologyGSA
    library(topologyGSA)
    data(examples)
    colnames(y1) <- paste("SYMBOL", colnames(y1), sep = ":")
    colnames(y2) <- paste("SYMBOL", colnames(y2), sep = ":")
    kegg <- pathways("hsapiens", "kegg")
    # --- Bldp [] ---
    # Key functions: frame, buildPathway
    edges <- data.frame(src_type = "ENTREZID", src="672",
                        dest_type = "ENTREZID", dest="7157",
                        direction="undirected", type="binding")
    pathway <- buildPathway("#1", "example", "hsapiens", "database",
                            proteinEdges = edges)
    # --- Bldp2 [] ---
    # Key functions: frame, buildPathway
    edges <- data.frame(src_type = "ENTREZID", src="672",
                        dest_type = "ENTREZID", dest="7157",
                        direction="undirected", type="binding")
    edgemix <- data.frame(src_type = "CHEBI", src="77750",
                        dest_type = "ENTREZID", dest="7157",
    # --- Para2 [] ---
    # Key functions: pathways, Do, convertIdentifiers
    ## original <- pathways("hsapiens", "reactome")
    ##
    ## # Do (will exploit parallelism)
    ## converted <- convertIdentifiers(original, "SYMBOL")
    ##

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
