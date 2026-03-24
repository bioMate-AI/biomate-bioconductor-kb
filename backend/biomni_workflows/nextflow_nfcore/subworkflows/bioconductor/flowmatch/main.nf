#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowMatch
// Matching cell populations and building meta-clusters and templates from a collection of FC samples.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowMatch/inst/doc/flowMatch.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowMatch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWMATCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowmatch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowmatch:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowmatch:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowmatch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowmatch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowmatch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClusteredSample)
    library(jsonlite)

    # --- Companionpkg [] ---
    # Key functions: requireNamespace, packages
    ##
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("healthyFlowData")
    # --- Clustering [] ---
    # Key functions: exprs, kmeans, object, ClusteredSample
    ## ------------------------------------------------
    ## load data and retrieve a sample
    ## ------------------------------------------------
    data(hd)
    sample = exprs(hd.flowSet[[1]])
    # --- Stage2 [] ---
    # Key functions: exprs, kmeans, clusters, ClusteredSample, cluster
    ## ------------------------------------------------
    ## load data and retrieve a sample
    ## ------------------------------------------------
    data(hd)
    sample = exprs(hd.flowSet[[1]])
    # --- Stage3 [] ---
    # Key functions: exprs, kmeans, ClusteredSample, clusters
    ## ------------------------------------------------
    ## load data and retrieve two samples
    ## ------------------------------------------------
    data(hd)
    sample1 = exprs(hd.flowSet[[1]])
    # --- Stage4 [] ---
    # Key functions: exprs, kmeans
    ## load data (20 samples in total)
    ## ------------------------------------------------
    data(hd)
    ## ------------------------------------------------
    ## Retrieve each sample, clsuter it and store the
    # --- Template Tree [] ---
    # Key functions: tree
    template.tree(template)
    # --- Mc Plot [] ---
    # Key functions: metaClusters
    # retrieve a metacluster from a template
    mc = get.metaClusters(template)[[1]]
    summary(mc)
    # plot all participating cluster in this meta-cluster
    plot(mc)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowmatch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowmatch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowmatch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWMATCH:", paste0("    flowmatch: ", packageVersion("flowMatch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowmatch_results.csv
    touch ${prefix}_flowmatch_output.rds
    echo "BIOC_FLOWMATCH:" > versions.yml
    echo "    flowmatch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWMATCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWMATCH(ch_input)

    emit:
    results  = BIOC_FLOWMATCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWMATCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWMATCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWMATCH.out.versions  // channel: path(versions.yml)
}
