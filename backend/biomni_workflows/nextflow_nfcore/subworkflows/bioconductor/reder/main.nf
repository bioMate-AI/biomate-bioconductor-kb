#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RedeR
// RedeR is an R-based package combined with a stand-alone Java application for interactive visualizati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RedeR/inst/doc/RedeR.R
// Upstream  : TreeAndLeaf, igraph
// Downstream: Fletcher2013b, dc3net
//
// Install: BiocManager::install("RedeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-reder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-reder:3.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-reder:3.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_reder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_reder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_reder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RedPort)
    library(jsonlite)

    # --- label='Add a graph' [] ---
    # Key functions: addGraphToRedeR
    gtoy1 <- graph.lattice(c(3,3,3))
    addGraphToRedeR(g=gtoy1, layout=layout_with_kk(gtoy1))
    # --- label='Get a graph' [] ---
    # Key functions: getGraphFromRedeR
    gtoy2 <- getGraphFromRedeR()
    summary(gtoy2)
    + attr: zoom (g/n), name (v/c), x (v/n), y (v/n)
    # --- label='Generate two scale [] ---
    # Key functions: sample_pa, addGraphToRedeR
    g1 <- sample_pa(7)
    g2 <- sample_pa(5)
    V(g1)$name <- paste("m",1:7,sep="")
    # --- label='Select nodes in containers' [] ---
    # Key functions: selectNodes, getGraphFromRedeR
    selectNodes(nodes="N2")
    getGraphFromRedeR(status="selected")
    # --- label='Generate a larger scale [] ---
    # Key functions: sample_pa
    g1 <- sample_pa(100, directed=FALSE)
    V(g1)$name <- paste0("V",1:vcount(g1))
    summary(g1)
    # --- label='Send the g1 graph to RedeR' [] ---
    # Key functions: addGraphToRedeR
    addGraphToRedeR(g=g1, zoom=50)
    # --- label='Run the interactive layout' [] ---
    # Key functions: relaxRedeR
    relaxRedeR(p1=20, p2=150, p3=20, p4=100, p5=10)
    # --- Red Port [] ---
    # Key functions: RedPort, attributes
    rdp <- RedPort()
    attribs <- attributes(rdp)
    attribs$GraphAttr$Usage <- gsub("$","\\$",attribs$GraphAttr$Usage, fixed=TRUE)
    # --- label='Workflow 1: Initialize the RedeR application' [] ---
    # Key functions: startRedeR, resetRedeR
    startRedeR()
    resetRedeR()
    # --- label='Workflow 1: Extract a subgraph and set attributes' [] ---
    # Key functions: subg
    gt3 <- subg(g=hs.inter, dat=deg.t3, refcol=1)
    gt3 <- att.setv(g=gt3, from="Symbol", to="nodeLabel")
    gt3 <- att.setv(g=gt3, from="logFC.t3", to="nodeColor",
    # --- label='Workflow 1: Extract another subgraph and set attributes' [] ---
    # Key functions: subg
    gt6 <- subg(g=hs.inter, dat=deg.t6, refcol=1)
    gt6 <- att.setv(g=gt6, from="Symbol", to="nodeLabel")
    gt6 <- att.setv(g=gt6, from="logFC.t6", to="nodeColor",
    # --- label='=Workflow 1: Extract another subgraph and set attributes' [] ---
    # Key functions: subg
    gt12 <- subg(g=hs.inter, dat=deg.t12, refcol=1)
    gt12 <- att.setv(g=gt12, from="Symbol", to="nodeLabel")
    gt12 <- att.setv(g=gt12, from="logFC.t12", to="nodeColor",
    # --- label='Workflow 1: Send subgraphs to the RedeR application' [] ---
    # Key functions: addGraphToRedeR
    N1 <- addGraphToRedeR(gt3, gcoord=c(10,25), gscale=20,
    N2 <- addGraphToRedeR(gt6, gcoord=c(20,70), gscale=50,
    N3 <- addGraphToRedeR(gt12, gcoord=c(70,55), gscale=80,
    # --- label='Workflow 1: Nest sub [] ---
    # Key functions: nestNodes
    N4 <- nestNodes(nodes=V(gt3)$name, parent=N2, theme='th2')
    N5 <- nestNodes(nodes=V(gt3)$name, parent=N3, theme='th2')
    nestNodes(nodes=V(gt3)$name, parent=N5, theme='th2')
    # --- label='Workflow 1: Assign edges to containers' [] ---
    # Key functions: mergeOutEdges
    mergeOutEdges(nlevels=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_reder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_reder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_reder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REDER:", paste0("    reder: ", packageVersion("RedeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reder_results.csv
    touch ${prefix}_reder_output.rds
    echo "BIOC_REDER:" > versions.yml
    echo "    reder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REDER(ch_input)

    emit:
    results  = BIOC_REDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REDER.out.versions  // channel: path(versions.yml)
}
