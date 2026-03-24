#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDDboost
// scDDboost is an R package to analyze changes in the distribution of single-cell expression data betw
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDDboost/inst/doc/scDDboost.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("scDDboost")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDDBOOST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scddboost"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scddboost:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-scddboost:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scddboost_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scddboost_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scddboost_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MulticoreParam)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(sim_dat)
    # --- Assays [] ---
    # Key functions: assays, colData, MulticoreParam, calD, pdd
    ---------------------------------------------------------------------
    data_counts <- SummarizedExperiment::assays(sim_dat)$counts
    conditions <- SummarizedExperiment::colData(sim_dat)$conditions
    rownames(data_counts) <- seq_len(1000)
    ##here we use 2 cores to compute the distance matrix
    # --- Detk [] ---
    # Key functions: detK
    ---------------------------------------------------------------------
    ## determine the number of subtypes
    K <- detK(D_c)
    # --- Getdd [] ---
    # Key functions: getDD
    ---------------------------------------------------------------------
    EDD <- getDD(ProbDD,0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scddboost_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scddboost_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scddboost_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDDBOOST:", paste0("    scddboost: ", packageVersion("scDDboost"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scddboost_results.csv
    touch ${prefix}_scddboost_output.rds
    echo "BIOC_SCDDBOOST:" > versions.yml
    echo "    scddboost: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDDBOOST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCDDBOOST(ch_input)

    emit:
    results  = BIOC_SCDDBOOST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDDBOOST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDDBOOST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDDBOOST.out.versions  // channel: path(versions.yml)
}
