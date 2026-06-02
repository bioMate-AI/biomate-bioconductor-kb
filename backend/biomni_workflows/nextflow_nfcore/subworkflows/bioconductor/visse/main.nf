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

    # --- Getmsigdb [] ---
    # Key functions: getMsigdb, appendKEGG, collections, subsetCollection, sample
    ---------------------------------------------------------------------
    library(msigdb)
    library(GSEABase)
    #load the MSigDB from the msigdb package
    msigdb_hs = getMsigdb()
    # --- Computemsigoverlap [] ---
    # Key functions: computeMsigOverlap, computeMsigNetwork, plotMsigNetwork
    ---------------------------------------------------------------------
    library(vissE)
    #compute gene-set overlap
    gs_ovlap = computeMsigOverlap(geneset_gsc, thresh = 0.25)
    #create an overlap network
    # --- Rnorm [] ---
    # Key functions: rnorm, plotMsigNetwork
    ---------------------------------------------------------------------
    #simulate gene-set statistics
    geneset_stats = rnorm(2500)
    names(geneset_stats) = geneset_res
    head(geneset_stats)
    # --- Findmsigclusters [] ---
    # Key functions: findMsigClusters, plotMsigNetwork
    ---------------------------------------------------------------------
    library(igraph)
    #identify clusters - order based on cluster size and avg gene-set stats
    # --- Plotmsigwordcloud [] ---
    # Key functions: plotMsigWordcloud
    ---------------------------------------------------------------------
    #compute and plot the results of text-mining
    #using gene-set Names
    plotMsigWordcloud(msigdb_hs, grps[1:6], type = 'Name')
    #using gene-set Short descriptions
    # --- Getimex [] ---
    # Key functions: getIMEX, plotMsigPPI
    ---------------------------------------------------------------------
    #load PPI from the msigdb package
    ppi = getIMEX('hs', inferred = TRUE)
    #create the PPI plot
    set.seed(36)

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
