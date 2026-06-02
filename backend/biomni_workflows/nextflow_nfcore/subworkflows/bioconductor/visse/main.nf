#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vissE
// This package enables the interpretation and analysis of results from a gene set enrichment analysis 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vissE/inst/doc/vissE.R
// Upstream  : GSEABase, ggplot2, igraph, msigdb, patchwork
// Downstream: none
//
// Install: BiocManager::install("vissE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VISSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-visse"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-visse:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-visse:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_visse_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_visse_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_visse_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vissE)
    library(jsonlite)

    # --- Cluster Identification [] ---
    # Key functions: findMsigClusters, plotMsigNetwork
    grps = findMsigClusters(
        gs_ovnet,
        genesetStat = geneset_stats,
        alg = igraph::cluster_walktrap,
        minSize = 5
    )
    net_clust_plot = plotMsigNetwork(
        gs_ovnet,
        markGroups = grps[1:6],
        genesetStat = geneset_stats,
        rmUnmarkedGroups = TRUE
    )


    # --- Text Mining and Wordclouds [] ---
    # Key functions: plotMsigWordcloud
    wc_name = plotMsigWordcloud(msigdb_hs, grps[1:6], type = "Name")
    wc_short = plotMsigWordcloud(msigdb_hs, grps[1:6], type = "Short")


    # --- Gene-level Statistics Analysis [] ---
    # Key functions: plotGeneStats
    gene_plot = plotGeneStats(gene_stats, msigdb_hs, grps[1:6])


    # --- Protein-Protein Interaction Analysis [] ---
    # Key functions: plotMsigPPI
    ppi_plot = plotMsigPPI(
        ppi,
        msigdb_hs,
        grps[1:6],
        geneStat = gene_stats,
        threshStatistic = 0.2,
        threshConfidence = 0.2
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_visse_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_visse_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_visse_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VISSE:", paste0("    visse: ", packageVersion("vissE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visse_results.csv
    touch ${prefix}_visse_output.rds
    echo "BIOC_VISSE:" > versions.yml
    echo "    visse: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VISSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VISSE(ch_input)

    emit:
    results  = BIOC_VISSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VISSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VISSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VISSE.out.versions  // channel: path(versions.yml)
}
