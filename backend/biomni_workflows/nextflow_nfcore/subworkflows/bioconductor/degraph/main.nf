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

    # --- Data [] ---
    # Key functions: data
    data("Loi2008_DEGraphVignette", package="DEGraph")
    classData <- classLoi2008
    exprData <- exprLoi2008
    annData <- annLoi2008
    grList <- grListKEGG
    # --- Ttests [] ---
    # Key functions: test, unlist
    ## Individual t-test p-values
    X1 <- t(exprData[, classData==0])
    X2 <- t(exprData[, classData==1])
    ttpv <- c()
    tts <- c()
    # --- Mvtests [] ---
    # Key functions: testOneGraph, results
    prop <- 0.2
    ## Multivariate tests
    resList <- NULL
    # --- Path1 [] ---
    # Key functions: translateKEGGID2GeneID, nodes, plotValuedGraph, stext, signif
    gIdx <- fSignif[1]
    gr <- graphList[[gIdx]]
    mm <- match(translateKEGGID2GeneID(nodes(gr)), rownames(annData))
    dn <- annData[mm, "NCBI.gene.symbol"]
    res <- plotValuedGraph(gr, values=shift, nodeLabels=dn, qMax=0.95, colorPalette=pal, height=40, lwd=1, cex=0.3, verbose=verbose)
    # --- Path2 [] ---
    # Key functions: translateKEGGID2GeneID, nodes, plotValuedGraph, stext, signif
    gIdx <- fSignif[5]
    gr <- graphList[[gIdx]]
    mm <- match(translateKEGGID2GeneID(nodes(gr)), rownames(annData))
    dn <- annData[mm, "NCBI.gene.symbol"]
    res <- plotValuedGraph(gr, values=shift, nodeLabels=dn, qMax=0.95, colorPalette=pal, height=40, lwd=1, cex=0.3, verbose=verbose)
    # --- Showpath1 [] ---
    # Key functions: translateKEGGID2GeneID, nodes, plotValuedGraph, stext, signif
    gIdx <- fSignif[1]
    gr <- graphList[[gIdx]]
    mm <- match(translateKEGGID2GeneID(nodes(gr)), rownames(annData))
    dn <- annData[mm, "NCBI.gene.symbol"]
    res <- plotValuedGraph(gr, values=shift, nodeLabels=dn, qMax=0.95, colorPalette=pal, height=40, lwd=1, cex=0.3, verbose=verbose)
    # --- Showpath2 [] ---
    # Key functions: translateKEGGID2GeneID, nodes, plotValuedGraph, stext, signif
    gIdx <- fSignif[5]
    gr <- graphList[[gIdx]]
    mm <- match(translateKEGGID2GeneID(nodes(gr)), rownames(annData))
    dn <- annData[mm, "NCBI.gene.symbol"]
    res <- plotValuedGraph(gr, values=shift, nodeLabels=dn, qMax=0.95, colorPalette=pal, height=40, lwd=1, cex=0.3, verbose=verbose)

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
