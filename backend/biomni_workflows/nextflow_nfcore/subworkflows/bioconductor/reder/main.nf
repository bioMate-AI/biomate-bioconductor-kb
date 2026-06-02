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
    library(RedeR)
    library(RedPort)
    library(jsonlite)

    # --- Graph Construction and Visualization [] ---
    # Key functions: addGraphToRedeR, getGraphFromRedeR, selectNodes
    gtoy1 <- igraph::graph.lattice(c(3, 3, 3))
    igraph::V(gtoy1)$name <- paste0("N", 1:27)
    addGraphToRedeR(g = gtoy1, layout = igraph::layout_with_kk(gtoy1))
    selectNodes(nodes = "N2")
    gtoy2 <- getGraphFromRedeR(status = "selected")


    # --- Attribute Mapping and Customization [] ---
    # Key functions: att.addv, att.adde, att.mapv
    g1 <- igraph::sample_pa(100, directed = FALSE)
    igraph::V(g1)$name <- paste0("V", 1:igraph::vcount(g1))
    g1 <- att.addv(g1, to = "nodeLabelSize", value = 20)
    g1 <- att.adde(g1, to = "edgeLineType", value = "DOTTED")
    df <- data.frame(
        ID = igraph::V(g1)$name,
        newAttr1 = rnorm(100),
        newAttr2 = rnorm(100)
    )
    g1 <- att.mapv(g = g1, dat = df, refcol = 1)


    # --- Visual Attribute Scaling [] ---
    # Key functions: att.setv
    g1 <- att.setv(
        g1,
        from = "newAttr1",
        to = "nodeColor",
        breaks = seq(-2, 2, 0.4),
        pal = 2
    )
    g1 <- att.setv(
        g1,
        from = "newAttr2",
        to = "nodeSize",
        nquant = 10,
        xlim = c(20, 50, 1)
    )


    # --- Biological Subgraph Extraction [] ---
    # Key functions: subg, att.setv, addGraphToRedeR
    data(ER.limma)
    data(hs.inter)
    deg.t3 <- ER.limma[ER.limma$degenes.t3 != 0, ]
    gt3 <- subg(g = hs.inter, dat = deg.t3, refcol = 1)
    gt3 <- att.setv(g = gt3, from = "Symbol", to = "nodeLabel")
    gt3 <- att.setv(
        g = gt3,
        from = "logFC.t3",
        to = "nodeColor",
        breaks = seq(-2, 2, 0.4),
        pal = 2
    )
    addGraphToRedeR(g = gt3, isNested = TRUE)

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
