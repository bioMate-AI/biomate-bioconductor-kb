#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEGraph
// DEGraph implements recent hypothesis testing methods which directly assess whether a particular gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEGraph/inst/doc/DEGraph.R
// Upstream  : KEGGgraph, RBGL, Rgraphviz, corpcor, fields
// Downstream: none
//
// Install: BiocManager::install("DEGraph")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGRAPH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-degraph"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-degraph:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-degraph:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_degraph_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_degraph_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_degraph_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEGraph)
    library(jsonlite)

    # --- Data Loading and ID Mapping [Data Loading and ID Mapping] ---
    # Key functions: translateGeneID2KEGGID
    data("Loi2008_DEGraphVignette", package="DEGraph")
    exprData <- exprLoi2008
    classData <- classLoi2008
    grList <- grListKEGG
    keggIDs <- translateGeneID2KEGGID(rownames(exprData))

    # --- Pathway-Based Multivariate Testing [Pathway-Based Multivariate Testing] ---
    # Key functions: testOneGraph
    prop <- 0.2
    resList <- list()
    for (ii in seq_along(grList)) {
        gr <- grList[[ii]]
        res <- testOneGraph(gr, exprData, classData, prop=prop)
        resList[[names(grList)[ii]]] <- res
    }

    # --- Pathway Visualization [Pathway Visualization] ---
    # Key functions: plotValuedGraph, translateKEGGID2GeneID, translateGeneID2KEGGID
    gr <- grList[[1]]
    geneSymbols <- translateKEGGID2GeneID(nodes(gr))
    values <- rowMeans(exprData[, classData == 1]) -
        rowMeans(exprData[, classData == 0])
    names(values) <- translateGeneID2KEGGID(rownames(exprData))
    res <- plotValuedGraph(gr, values=values, nodeLabels=geneSymbols,
        qMax=0.95, height=40, lwd=1, cex=0.3)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_degraph_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_degraph_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_degraph_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEGRAPH:", paste0("    degraph: ", packageVersion("DEGraph"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degraph_results.csv
    touch ${prefix}_degraph_output.rds
    echo "BIOC_DEGRAPH:" > versions.yml
    echo "    degraph: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEGRAPH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEGRAPH(ch_input)

    emit:
    results  = BIOC_DEGRAPH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEGRAPH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEGRAPH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEGRAPH.out.versions  // channel: path(versions.yml)
}
