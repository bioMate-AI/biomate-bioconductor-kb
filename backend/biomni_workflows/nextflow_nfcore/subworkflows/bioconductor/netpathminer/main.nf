#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NetPathMiner
// NetPathMiner is a general framework for network path mining using genome-scale networks. It construc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NetPathMiner/inst/doc/NPMVignette.R
// Upstream  : ALL, RCurl, rBiopaxParser
// Downstream: none
//
// Install: BiocManager::install("NetPathMiner")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETPATHMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-netpathminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-netpathminer:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-netpathminer:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_netpathminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_netpathminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_netpathminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NetPathMiner)
    library(jsonlite)

    # --- fig=TRUE [] ---
    # Key functions: plotClusters
    plotClusters(ybinpaths, p.cluster)
    # --- fig=TRUE [] ---
    # Key functions: plotPaths
    plotPaths(ranked.p, rgraph)
    plotPaths(ranked.p, graph, path.clusters=p.class)
    # --- fig=TRUE [] ---
    # Key functions: plotAllNetworks
    plotAllNetworks(ranked.p, metabolic.net = graph, reaction.net = rgraph,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_netpathminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_netpathminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_netpathminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NETPATHMINER:", paste0("    netpathminer: ", packageVersion("NetPathMiner"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netpathminer_results.csv
    touch ${prefix}_netpathminer_output.rds
    echo "BIOC_NETPATHMINER:" > versions.yml
    echo "    netpathminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NETPATHMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NETPATHMINER(ch_input)

    emit:
    results  = BIOC_NETPATHMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NETPATHMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NETPATHMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NETPATHMINER.out.versions  // channel: path(versions.yml)
}
