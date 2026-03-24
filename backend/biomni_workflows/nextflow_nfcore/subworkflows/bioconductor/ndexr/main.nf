#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ndexr
// This package offers an interface to NDEx servers, e.g. the public server at http://ndexbio.org/. It 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ndexr/inst/doc/ndexr-vignette.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("ndexr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NDEXR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ndexr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ndexr:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ndexr:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ndexr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ndexr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ndexr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ndexr)
    library(jsonlite)

    # --- Ndex Network Get Summary [] ---
    # Key functions: ndex_network_get_summary, ndex_get_network, content
    ---------------------------------------------------------------------
    ## UUID of the first search result
    networkId <- networks[1,'externalId']
    networkId
    ## get summary of the network
    # --- Server [] ---
    # Key functions: server, ndex_find_networks
    ---------------------------------------------------------------------
    ## list networks on server (same as previous)
    networks <- ndex_find_networks(ndexcon, start=0, size=5)
    ## search for "EGFR"
    networksEgfr <- ndex_find_networks(ndexcon, searchString="EGFR")
    # --- Ndex Network Get Summary [] ---
    # Key functions: ndex_network_get_summary, ndex_get_network
    ---------------------------------------------------------------------
    ## UUID of the first search result
    networkId <- networksOfUser[1,'externalId']
    ## get network summary
    networkSummary <- ndex_network_get_summary(ndexcon, networkId)
    # --- Ndex Network Get Metadata [] ---
    # Key functions: ndex_network_get_metadata
    ---------------------------------------------------------------------
    ## get meta-data for a network
    metadata = ndex_network_get_metadata(ndexcon, networkId)
    names(metadata)
    metadata[c('name','elementCount')]
    # --- Ndex Network Get Aspect [] ---
    # Key functions: ndex_network_get_aspect
    ---------------------------------------------------------------------
    ## get aspect "nodeCitations" for the network
    networkAttibutes = ndex_network_get_aspect(ndexcon, networkId, "networkAttributes")
    networkAttibutes
    # --- Some [] ---
    # Key functions: some
    ---------------------------------------------------------------------
    # Copy an existing config
    custom_ndex_config = ndex_config$Version_2.0
    # Change the host connection for a local NDEx server installation
    custom_ndex_config$connection$host ="localhost:8090"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ndexr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ndexr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ndexr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NDEXR:", paste0("    ndexr: ", packageVersion("ndexr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ndexr_results.csv
    touch ${prefix}_ndexr_output.rds
    echo "BIOC_NDEXR:" > versions.yml
    echo "    ndexr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NDEXR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NDEXR(ch_input)

    emit:
    results  = BIOC_NDEXR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NDEXR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NDEXR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NDEXR.out.versions  // channel: path(versions.yml)
}
