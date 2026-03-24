#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEfier
// iSEEfier provides a set of functionality to quickly and intuitively create, inspect, and combine ini
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEfier/inst/doc/iSEEfier_userguide.R
// Upstream  : scRNAseq, scuttle, scater, iSEE, ggplot2
// Downstream: none
//
// Install: BiocManager::install("iSEEfier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEFIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseefier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseefier:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseefier:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_iseefier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseefier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseefier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BaronPancreasData)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: logNormCounts
    library("scuttle")
    sce <- logNormCounts(sce)
    # --- Run PCA [] ---
    # Key functions: runPCA, runTSNE, runUMAP
    library("scater")
    sce <- runPCA(sce)
    sce <- runTSNE(sce)
    # --- ISEEinit analysis [] ---
    # Key functions: iSEEinit, BaronPancreasData, iSEE, iSEEnrich, iSEEmarker, view_initial_tiles, view_initial_network, glue_initials
    library(ggplot2)
    view_initial_tiles(initial = initial1)
    view_initial_tiles(initial = results$initial)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseefier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseefier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseefier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEFIER:", paste0("    iseefier: ", packageVersion("iSEEfier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseefier_results.csv
    touch ${prefix}_iseefier_output.rds
    echo "BIOC_ISEEFIER:" > versions.yml
    echo "    iseefier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_ISEEFIER(ch_input)

    emit:
    results  = BIOC_ISEEFIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEFIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEFIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEFIER.out.versions  // channel: path(versions.yml)
}
