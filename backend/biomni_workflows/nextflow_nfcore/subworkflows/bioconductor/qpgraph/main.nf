#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qpgraph
// Estimate gene and eQTL networks from high-throughput expression and genotyping assays.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qpgraph/inst/doc/eQTLnetworks.R
// Upstream  : graph, grid, qtl
// Downstream: none
//
// Install: BiocManager::install("qpgraph")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QPGRAPH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qpgraph"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qpgraph:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qpgraph:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qpgraph_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qpgraph_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qpgraph_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Seqinfo)
    library(jsonlite)

    # --- Map [] ---
    # Key functions: map
    map <- sim.map(len=rep(100, times=9),
                   n.mar=rep(10, times=9),
                   anchor.tel=FALSE,
                   eq.spacing=TRUE,
                   include.x=FALSE)
    # --- Frame [] ---
    # Key functions: frame

    # --- Lapply [] ---
    # Key functions: Seqinfo, nchr
    pMap <- lapply(map, function(x) x * 5)
    class(pMap) <- "map"
    annot$start <- floor(annot$start * 5)
    annot$end <- floor(annot$end * 5)
    # --- Eqtlnetworkestimationparam [] ---
    # Key functions: eQTLnetworkEstimationParam
    param <- eQTLnetworkEstimationParam(cross, physicalMap=pMap,
                                        geneAnnotation=annot, genome=genome)
    # --- Eqtlnetworkestimate [] ---
    # Key functions: eQTLnetworkEstimate
    eqtlnet.q0 <- eQTLnetworkEstimate(param, ~ marker + gene, verbose=FALSE)
    eqtlnet.q0
    # --- Eqtlnetworkestimate [] ---
    # Key functions: eQTLnetworkEstimate, gene
    eqtlnet.q0.fdr.nrr <- eQTLnetworkEstimate(param, ~ marker + gene | gene(q=3),
                                              estimate=eqtlnet.q0.fdr, verbose=FALSE)
    eqtlnet.q0.fdr.nrr
    # --- Eqtlnetworkestimate [] ---
    # Key functions: eQTLnetworkEstimate
    eqtlnet.q0.fdr.nrr <- eQTLnetworkEstimate(param, estimate=eqtlnet.q0.fdr.nrr,
                                              epsilon=0.1)
    eqtlnet.q0.fdr.nrr
    # --- Alleqtl [] ---
    # Key functions: alleQTL, split
    eqtls <- alleQTL(eqtlnet.q0.fdr.nrr)
    median(sapply(split(eqtls$QTL, eqtls$gene), length))
    # --- Eqtlnetworkestimate [] ---
    # Key functions: eQTLnetworkEstimate
    eqtlnet.q0.fdr.nrr.sel <- eQTLnetworkEstimate(param, estimate=eqtlnet.q0.fdr.nrr,
                                                  alpha=0.05)
    eqtlnet.q0.fdr.nrr.sel
    # --- Hiveplot [] ---
    # Key functions: newpage, pushViewport, viewport
    library(grid)
    library(graph)
    grid.newpage()
    pushViewport(viewport(layout=grid.layout(3, 3)))
    # --- Info [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qpgraph_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qpgraph_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qpgraph_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QPGRAPH:", paste0("    qpgraph: ", packageVersion("qpgraph"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpgraph_results.csv
    touch ${prefix}_qpgraph_output.rds
    echo "BIOC_QPGRAPH:" > versions.yml
    echo "    qpgraph: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QPGRAPH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QPGRAPH(ch_input)

    emit:
    results  = BIOC_QPGRAPH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QPGRAPH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QPGRAPH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QPGRAPH.out.versions  // channel: path(versions.yml)
}
